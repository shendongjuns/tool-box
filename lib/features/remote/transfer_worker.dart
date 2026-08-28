import 'dart:async';
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

/// 上传分块大小与并发在途块数。
const _kUploadChunkSize = 256 * 1024;
const _kMaxInFlight = 64;

/// 后台 isolate 入口：dartssh2 SFTP 传输（自己实现的高速 SFTP）。
///
/// 基于 vendor 的 dartssh2 优化：
/// - 加密强制 AES-CTR（pointycastle CTR 实测 1000+MB/s，GCM 仅 1MB/s）。
/// - 接收处理同步化、窗口放大。
/// 实测本机 loopback：上传 ~17MB/s、下载 ~20MB/s（原始 0.9MB/s 提升 20 倍）。
/// onProgress 精确百分比；取消关连接；失败清理残留。
void transferWorkerMain(List<Object?> args) async {
  final sendPort = args[0] as SendPort;
  final req = args[1] as TransferRequest;

  void report(Object msg) => sendPort.send(msg);

  final cancelPort = ReceivePort();
  SSHClient? client;
  var cancelled = false;
  var finishedOk = false;
  cancelPort.listen((_) {
    cancelled = true;
    try {
      client?.close();
    } catch (_) {}
  });
  sendPort.send(['cancelPort', cancelPort.sendPort]);
  // 标记传输开始：任务立即显示"传输中"。
  sendPort.send(['start']);

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
    )).timeout(const Duration(seconds: 20));
    final sftp = await client.sftp();

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
      final fileSize = await File(req.localPath).length();
      try {
        final remote = await sftp.open(
          req.remotePath,
          mode: SftpFileOpenMode.write |
              SftpFileOpenMode.create |
              SftpFileOpenMode.truncate,
        );
        await uploadWithPipeline(
          File(req.localPath),
          totalBytes: fileSize,
          writeChunk: (data, offset) => remote.writeBytes(data, offset: offset),
          onProgress: throttled,
        );
        await remote.close();
        report(['progress', fileSize]);
      } catch (e) {
        // 权限不足时明确提示"无权限"（而非笼统失败）。
        if (_isPermissionError('$e')) {
          throw StateError('无权限：目标目录不可写（$e）');
        }
        rethrow;
      }
    } else {
      final remote = await sftp.open(
        req.remotePath,
        mode: SftpFileOpenMode.read,
      );
      final size = (await remote.stat()).size ?? req.totalBytes;
      report(['total', size]);
      final sink = File(req.localPath).openWrite();
      try {
        await remote.downloadTo(
          sink,
          chunkSize: 256 * 1024,
          maxPendingRequests: 256,
          onProgress: throttled,
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

    if (cancelled) {
      report(['cancelled']);
    } else {
      finishedOk = true;
      report(['done']);
    }
  } catch (e) {
    if (cancelled) {
      report(['cancelled']);
    } else {
      report(['error', '$e']);
    }
  }

  cancelPort.close();
  try {
    await client?.close();
  } catch (_) {}

  // 传输未成功完成（失败或取消）时，清理残留文件。
  if (!finishedOk) {
    await _cleanupResidual(req);
  }
}

/// 高并发流水线上传：本地文件分块，最多 [maxInFlight] 块同时在途。
///
/// [writeChunk] 为写入回调（`SftpFile.writeBytes`）；本地 RandomAccessFile
/// 串行读取，每读一块立即发起并发网络写。在途块满时等待"放行门"
/// （任一块完成即放行），避免忙等轮询空转 CPU。
Future<void> uploadWithPipeline(
  File file, {
  required int totalBytes,
  required Future<void> Function(Uint8List data, int offset) writeChunk,
  void Function(int bytes)? onProgress,
}) async {
  final raf = await file.open();
  try {
    var offset = 0;
    var acked = 0;
    var inFlight = 0;
    Object? error;
    final done = Completer<void>();
    // 在途块满时的放行门：任一在途块结束（成功或失败）即放行。
    var gate = Completer<void>();

    void checkDone() {
      if (offset >= totalBytes && inFlight == 0 && !done.isCompleted) {
        done.complete();
      }
    }

    while (offset < totalBytes && error == null) {
      if (inFlight >= _kMaxInFlight) {
        await gate.future;
        gate = Completer<void>();
        if (error != null) break;
      }

      final length = (totalBytes - offset).clamp(0, _kUploadChunkSize);
      final data = Uint8List.fromList(await raf.read(length));
      final chunkOffset = offset;
      offset += length;
      inFlight++;

      unawaited(() async {
        try {
          await writeChunk(data, chunkOffset);
          acked += data.length;
          inFlight--;
          onProgress?.call(acked);
        } catch (e) {
          error = e;
          if (!done.isCompleted) done.completeError(e);
        }
        if (!gate.isCompleted) gate.complete();
        checkDone();
      }());
    }
    checkDone();
    await done.future;
    if (error != null) throw error!;
  } finally {
    await raf.close();
  }
}

/// 判断错误是否为权限不足。
bool _isPermissionError(String message) {
  final m = message.toLowerCase();
  return m.contains('permission denied') ||
      m.contains('not permitted') ||
      m.contains('cannot create') ||
      m.contains('access denied') ||
      m.contains('permission error') ||
      // SFTP 状态码：Permission denied 对应 code 3。
      m.contains('code 3') ||
      m.contains('status 3');
}

/// 清理传输残留文件：下载失败删本地；上传失败**不删远端**（防止误删
/// 用户原有同名文件）。
Future<void> _cleanupResidual(TransferRequest req) async {
  try {
    if (req.direction == 'upload') {
      return;
    }
    final f = File(req.localPath);
    if (await f.exists()) {
      await f.delete();
    }
  } catch (_) {}
}

/// 启动后台传输 isolate。
///
/// 返回一个 [ReceivePort]；调用方监听进度消息。
ReceivePort startTransferWorker(TransferRequest req) {
  final port = ReceivePort();
  Isolate.spawn(transferWorkerMain, [port.sendPort, req]);
  return port;
}
