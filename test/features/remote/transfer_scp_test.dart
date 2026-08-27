import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/features/remote/transfer_worker.dart';

/// 系统 scp 传输集成测试（连本机 OpenSSH，需密钥认证已配置）。
/// 默认跳过，用 --run-skipped 显式运行。
void main() {
  const host = 'localhost';
  const user = 'Administrator';
  final keyPath = '${Platform.environment['USERPROFILE']}\\.ssh\\id_rsa';

  TransferRequest req({
    required String direction,
    required String localPath,
    required String remotePath,
    required int total,
  }) =>
      TransferRequest(
        host: host,
        port: 22,
        username: user,
        password: '',
        useKeyAuth: true,
        privateKeyPath: keyPath,
        keyPassphrase: null,
        direction: direction,
        localPath: localPath,
        remotePath: remotePath,
        totalBytes: total,
      );

  /// 启动 worker 并等待终态，返回 (终态类型, 消息)。
  Future<(String, String?)> runWorker(TransferRequest r) async {
    final port = startTransferWorker(r);
    final completer = Completer<(String, String?)>();
    var done = false;
    port.listen((msg) {
      if (done) return;
      final list = msg as List<Object?>;
      final type = list[0] as String;
      if (type == 'done' || type == 'error' || type == 'cancelled') {
        done = true;
        completer.complete((type, list.length > 1 ? '${list[1]}' : null));
      }
    });
    return completer.future.timeout(const Duration(seconds: 60));
  }

  test('scp 上传+下载往返，取消后清理残留', () async {
    final tempDir = Directory.systemTemp.createTempSync('scp_test');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final up = File('${tempDir.path}${Platform.pathSeparator}up.bin');
    await up.writeAsBytes(Uint8List(2 * 1024 * 1024));

    // 1) 上传。
    final upRes = await runWorker(req(
      direction: 'upload',
      localPath: up.path,
      remotePath: 'scp_test_up.bin',
      total: up.lengthSync(),
    ));
    expect(upRes.$1, 'done', reason: '上传应成功: $upRes');

    // 2) 下载到本地新文件。
    final down = File('${tempDir.path}${Platform.pathSeparator}down.bin');
    final downRes = await runWorker(req(
      direction: 'download',
      localPath: down.path,
      remotePath: 'scp_test_up.bin',
      total: up.lengthSync(),
    ));
    expect(downRes.$1, 'done', reason: '下载应成功: $downRes');
    expect(down.lengthSync(), up.lengthSync(), reason: '下载文件大小应一致');

    // 3) 失败场景：下载不存在的文件 → 报错且本地残留被清理。
    final ghost = File('${tempDir.path}${Platform.pathSeparator}ghost.bin');
    final ghostRes = await runWorker(req(
      direction: 'download',
      localPath: ghost.path,
      remotePath: 'no_such_file_xyz.bin',
      total: 0,
    ));
    expect(ghostRes.$1, 'error', reason: '下载不存在的文件应报错');
    expect(await ghost.exists(), isFalse, reason: '失败后本地残留应被清理');

    // 4) 取消场景：启动大文件上传后立即取消 → cancelled 且远端被清理。
    final big = File('${tempDir.path}${Platform.pathSeparator}big.bin');
    await big.writeAsBytes(Uint8List(50 * 1024 * 1024));
    final port = startTransferWorker(req(
      direction: 'upload',
      localPath: big.path,
      remotePath: 'scp_test_cancel.bin',
      total: big.lengthSync(),
    ));
    final cancelCompleter = Completer<(String, String?)>();
    var done = false;
    SendPort? cancelPort;
    port.listen((msg) {
      final list = msg as List<Object?>;
      final type = list[0] as String;
      if (type == 'cancelPort') {
        cancelPort = list[1] as SendPort;
      } else if (type == 'done' || type == 'error' || type == 'cancelled') {
        if (!done) {
          done = true;
          cancelCompleter.complete((type, list.length > 1 ? '${list[1]}' : null));
        }
      }
    });
    // 等 cancelPort 就绪后取消。
    for (var i = 0; i < 50 && cancelPort == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    cancelPort?.send(['cancel']);
    final cancelRes = await cancelCompleter.future
        .timeout(const Duration(seconds: 30));
    expect(cancelRes.$1, 'cancelled', reason: '应返回 cancelled: $cancelRes');

    // 清理远端上传的测试文件。
    try {
      await Process.run(r'C:\Windows\System32\OpenSSH\ssh.exe', [
        '-o', 'StrictHostKeyChecking=no',
        '-i', keyPath,
        'Administrator@localhost',
        'rm -f scp_test_up.bin scp_test_cancel.bin',
      ]);
    } catch (_) {}
  }, skip: '需本机 SSH；用 --run-skipped 显式运行', timeout: const Timeout(Duration(minutes: 3)));
}
