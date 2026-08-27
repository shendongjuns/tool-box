import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/features/remote/remote_models.dart';
import 'package:toolbox/features/remote/ssh_session.dart';
import 'package:toolbox/features/remote/transfer_worker.dart';

/// 真实 SSH 上传基准测试（连本机 OpenSSH）。
/// 需要本机 SSH 密钥认证已配置（id_rsa → administrators_authorized_keys）。
void main() {
  const host = 'localhost';
  const user = 'Administrator';
  final keyPath = '${Platform.environment['USERPROFILE']}\\.ssh\\id_rsa';

  test(
    'dartssh2 SFTP vs 系统 scp 上传速度对比',
    () async {
    final tempDir = Directory.systemTemp.createTempSync('bench');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final file = File('${tempDir.path}${Platform.pathSeparator}bench.bin');
    await file.writeAsBytes(Uint8List(20 * 1024 * 1024));

    Future<double> measure(String label, Future<void> Function() run) async {
      final sw = Stopwatch()..start();
      await run();
      final secs = sw.elapsedMilliseconds / 1000;
      final mb = 20.0;
      debugPrint('$label: ${(mb / secs).toStringAsFixed(2)} MB/s (${secs.toStringAsFixed(2)}s)');
      return mb / secs;
    }

    // 方案 A：dartssh2 SftpFileWriter。
    final speedA = await measure('dartssh2 SftpFileWriter', () async {
      final client = await defaultSshConnector(_conn());
      try {
        final sftp = await client.sftp();
        final remote = await sftp.open(
          'bench_a.bin',
          mode: SftpFileOpenMode.write |
              SftpFileOpenMode.create |
              SftpFileOpenMode.truncate,
        );
        await remote.write(file.openRead().map((c) => Uint8List.fromList(c))).done;
        await remote.close();
        try {
          await sftp.remove('bench_a.bin');
        } catch (_) {}
      } finally {
        await client.close();
      }
    });

    // 方案 B：系统 scp 命令。
    final speedB = await measure('系统 scp', () async {
      final req = TransferRequest(
        host: host,
        port: 22,
        username: user,
        password: '',
        useKeyAuth: true,
        privateKeyPath: keyPath,
        keyPassphrase: null,
        direction: 'upload',
        localPath: file.path,
        remotePath: 'bench_b.bin',
        totalBytes: 20 * 1024 * 1024,
      );
      final port = startTransferWorker(req);
      final completer = Completer<String?>();
      port.listen((msg) {
        final list = msg as List<Object?>;
        final type = list[0] as String;
        if (type == 'done') {
          if (!completer.isCompleted) completer.complete(null);
        } else if (type == 'error') {
          if (!completer.isCompleted) completer.complete('${list[1]}');
        }
      });
      final err = await completer.future.timeout(const Duration(seconds: 60));
      if (err != null) throw StateError('scp 失败: $err');
    });

    debugPrint('速度对比：dartssh2=${speedA.toStringAsFixed(2)} MB/s, scp=${speedB.toStringAsFixed(2)} MB/s');
    // scp 应显著快于 dartssh2。
    expect(speedB, greaterThan(speedA));
    },
    // 基准测试较慢（dartssh2 慢速对比），默认跳过，可用 --run-skipped 显式运行。
    skip: '性能基准，需本机 SSH；用 --run-skipped 显式运行',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

SshConnection _conn() => SshConnection(
      id: 'bench',
      name: 'bench',
      host: 'localhost',
      port: 22,
      username: 'Administrator',
      password: '',
      useKeyAuth: true,
      privateKeyPath: '${Platform.environment['USERPROFILE']}\\.ssh\\id_rsa',
    );
