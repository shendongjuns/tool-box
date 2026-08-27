import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/features/remote/remote_models.dart';
import 'package:toolbox/features/remote/ssh_session.dart';

/// SFTP 速度基准（vendor dartssh2 优化前后对比）。
/// 需本机 SSH（管理员密钥），用 --run-skipped 显式运行。
void main() {
  final key = '${Platform.environment['USERPROFILE']}/.ssh/id_rsa';

  test('SFTP 上传/下载 50MB 速度', () async {
    // 准备本地 50MB 文件。
    final local = File('${Directory.systemTemp.path}/bench50.bin');
    await local.writeAsBytes(List<int>.filled(50 * 1024 * 1024, 9));

    final conn = SshConnection(
      id: 's', name: 's', host: 'localhost', port: 22, username: 'Administrator',
      password: '', useKeyAuth: true, privateKeyPath: key,
    );
    final client = await defaultSshConnector(conn);
    final sftp = await client.sftp();

    // 上传测速。
    final remote = await sftp.open('bench50_up.bin',
        mode: SftpFileOpenMode.write |
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate);
    final sw = Stopwatch()..start();
    // 分块上传（与 worker 相同策略）。
    final raf = await local.open();
    const chunk = 256 * 1024;
    var offset = 0;
    while (offset < 50 * 1024 * 1024) {
      final len = (50 * 1024 * 1024 - offset).clamp(0, chunk);
      final data = await raf.read(len);
      await remote.writeBytes(Uint8List.fromList(data), offset: offset);
      offset += len;
    }
    await raf.close();
    await remote.close();
    sw.stop();
    final upMb = 50.0 / (sw.elapsedMilliseconds / 1000);
    debugPrint('SFTP 上传: ${upMb.toStringAsFixed(1)} MB/s (${sw.elapsedMilliseconds}ms)');

    // 下载测速。
    final remote2 = await sftp.open('bench50_up.bin', mode: SftpFileOpenMode.read);
    final out = File('${Directory.systemTemp.path}/bench50_down.bin');
    sw.reset();
    sw.start();
    final sink = out.openWrite();
    await remote2.downloadTo(sink, chunkSize: 256 * 1024, maxPendingRequests: 256);
    await sink.close();
    sw.stop();
    final downMb = 50.0 / (sw.elapsedMilliseconds / 1000);
    debugPrint('SFTP 下载: ${downMb.toStringAsFixed(1)} MB/s (${sw.elapsedMilliseconds}ms)');
    expect(out.lengthSync(), 50 * 1024 * 1024);

    await remote2.close();
    try {
      await sftp.remove('bench50_up.bin');
    } catch (_) {}
    await client.close();
    local.deleteSync();
    out.deleteSync();

    // 断言：优化后应远高于原始 0.9MB/s（≥12MB/s 保护回归）。
    expect(upMb, greaterThanOrEqualTo(12), reason: '上传应≥12MB/s，实际 $upMb');
    expect(downMb, greaterThanOrEqualTo(12), reason: '下载应≥12MB/s，实际 $downMb');
  }, skip: '需本机 SSH', timeout: const Timeout(Duration(minutes: 4)));
}
