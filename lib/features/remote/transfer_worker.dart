import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:toolbox/features/remote/remote_models.dart';
import 'package:toolbox/features/remote/ssh_session.dart';

/// 传输请求（可跨 isolate 发送：全是可序列化字段）。
class TransferRequest {
  const TransferRequest({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.useKeyAuth,
    required this.privateKeyPath,
    required this.keyPassphrase,
    required this.direction,
    required this.localPath,
    required this.remotePath,
    required this.totalBytes,
  });

  final String host;
  final int port;
  final String username;
  final String password;
  final bool useKeyAuth;
  final String? privateKeyPath;
  final String? keyPassphrase;

  /// 'upload' 或 'download'。
  final String direction;
  final String localPath;
  final String remotePath;
  final int totalBytes;
}

/// 后台 isolate 入口：用 dartssh2 高层 API 流式传输。
///
/// 下载用 `download()`（读流水线，chunk 256KB × 256 在途，官方修复
/// 慢速的方案）；上传用 `file.write(stream)` 流式写入。通过 [sendPort]
/// 回传精确字节进度、完成/错误；监听 `['cancel']` 时中断。
void transferWorkerMain(List<Object?> args) async {
  final sendPort = args[0] as SendPort;
  final req = args[1] as TransferRequest;

  void report(Object msg) => sendPort.send(msg);

  SSHClient? client;
  try {
    client = await defaultSshConnector(SshConnection(
      id: '',
      name: '',
      host: req.host,
      port: req.port,
      username: req.username,
      password: req.password,
      useKeyAuth: req.useKeyAuth,
      privateKeyPath: req.privateKeyPath,
      keyPassphrase: req.keyPassphrase,
    ));
    final sftp = await client.sftp();

    // 取消监听：取消时关闭 SSH 连接，强制中断传输。
    final cancelPort = ReceivePort();
    var cancelled = false;
    final cancelSub = cancelPort.listen((_) {
      cancelled = true;
      try {
        client?.close();
      } catch (_) {}
    });
    sendPort.send(['cancelPort', cancelPort.sendPort]);

    var last = DateTime.now();
    void throttled(int bytes) {
      if (cancelled) return;
      final now = DateTime.now();
      if (now.difference(last).inMilliseconds >= 300) {
        last = now;
        report(['progress', bytes]);
      }
    }

    if (req.direction == 'upload') {
      final remote = await sftp.open(
        req.remotePath,
        mode: SftpFileOpenMode.write |
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate,
      );
      // 流式上传：16KB 分块、1MB 在途流控、onProgress 精确进度。
      final stream = File(req.localPath)
          .openRead()
          .map((c) => Uint8List.fromList(c));
      await remote
          .write(stream, onProgress: (bytes) => throttled(bytes))
          .done;
      await remote.close();
      report(['progress', req.totalBytes]);
    } else {
      final remote = await sftp.open(
        req.remotePath,
        mode: SftpFileOpenMode.read,
      );
      final size = (await remote.stat()).size ?? req.totalBytes;
      report(['total', size]);
      final sink = File(req.localPath).openWrite();
      try {
        // 读流水线：256KB chunk × 256 在途，高吞吐。
        await remote.downloadTo(
          sink,
          chunkSize: 256 * 1024,
          maxPendingRequests: 256,
          onProgress: (bytes) => throttled(bytes),
        );
        await sink.flush();
      } finally {
        await sink.close();
        try {
          await remote.close();
        } catch (_) {}
      }
      report(['progress', size]);
    }

    cancelSub.cancel();
    cancelPort.close();
    try {
      await client.close();
    } catch (_) {}
    client = null;

    if (cancelled) {
      report(['cancelled']);
    } else {
      report(['done']);
    }
  } catch (e) {
    report(['error', '$e']);
  }
}

/// 启动后台传输 isolate。
///
/// 返回一个 [ReceivePort]；调用方监听进度消息。
ReceivePort startTransferWorker(TransferRequest req) {
  final port = ReceivePort();
  Isolate.spawn(transferWorkerMain, [port.sendPort, req]);
  return port;
}
