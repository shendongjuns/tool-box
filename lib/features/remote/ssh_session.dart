import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import 'remote_models.dart';

/// 会话状态。
enum SshSessionStatus { connecting, connected, error, closed }

/// 建立 SSH 连接的连接器；测试中可注入假实现。
typedef SshConnector = Future<SSHClient> Function(SshConnection connection);

/// SSH 连接/认证失败异常。
class SshConnectException implements Exception {
  const SshConnectException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 依据连接信息创建 SSHClient（支持密码与私钥认证）。
///
/// [onPasswordRequest] 为可选的密码回调（测试连接不需要时传 null）。
Future<SSHClient> _buildClient(
  SshConnection connection,
  FutureOr<String?> Function()? onPasswordRequest,
) async {
  // 私钥认证：读取并解析私钥文件，传给 SSHClient.identities。
  var identities = <SSHKeyPair>[];
  if (connection.useKeyAuth) {
    final keyPath = connection.privateKeyPath;
    if (keyPath == null || keyPath.trim().isEmpty) {
      throw const SshConnectException('已选择私钥认证，但未指定私钥文件');
    }
    final file = File(keyPath.trim());
    if (!file.existsSync()) {
      throw SshConnectException('私钥文件不存在：$keyPath');
    }
    final pem = file.readAsStringSync();
    if (pem.trim().isEmpty) {
      throw SshConnectException('私钥文件为空：$keyPath');
    }
    try {
      identities = SSHKeyPair.fromPem(pem, connection.keyPassphrase);
    } catch (e) {
      throw SshConnectException('私钥解析失败：$e');
    }
  }

  final socket = await SSHSocket.connect(
    connection.host,
    connection.port,
    timeout: const Duration(seconds: 15),
  );
  final client = SSHClient(
    socket,
    username: connection.username,
    identities: identities.isEmpty ? null : identities,
    // 密钥认证失败或未启用密钥时回退到密码认证。
    onPasswordRequest: connection.password.isNotEmpty
        ? () => connection.password
        : onPasswordRequest,
    disableHostkeyVerification: true,
    authTimeout: const Duration(seconds: 15),
  );
  await client.authenticated;
  return client;
}

/// 默认连接器：TCP 连接 + 密码/私钥认证（首次连接接受未知主机密钥）。
Future<SSHClient> defaultSshConnector(SshConnection connection) =>
    _buildClient(connection, null);

final sshConnectorProvider = Provider<SshConnector>((ref) => defaultSshConnector);

/// 单个 SSH 会话运行时：终端 + SSH 连接 + SFTP 客户端。
///
/// [status]/[error] 用 ValueNotifier 暴露给 UI；会话关闭后不再被引用，
/// 交由 GC 回收（ValueNotifier 无原生资源，无需显式 dispose）。
class SshSessionHandle {
  SshSessionHandle({
    required this.connection,
    required this.terminal,
  });

  final SshConnection connection;
  final Terminal terminal;

  final ValueNotifier<SshSessionStatus> status =
      ValueNotifier(SshSessionStatus.connecting);
  final ValueNotifier<String?> error = ValueNotifier(null);

  SSHClient? _client;
  SSHSession? _shell;
  SftpClient? _sftp;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  bool _closed = false;

  bool get isConnected => status.value == SshSessionStatus.connected;

  /// 已建立的 SSH 连接（未连接时返回 null）。
  SSHClient? get client => _client;

  /// 建立连接并启动交互终端。
  Future<void> connect(SshConnector connector) async {
    final shell = _shell;
    if (shell != null) {
      shell.resizeTerminal(
        terminal.viewWidth,
        terminal.viewHeight,
      );
      return;
    }

    final client = await connector(connection);
    _client = client;

    // 终端输入 → SSH
    terminal.onOutput = (data) => _shell?.write(utf8.encode(data));
    // 终端尺寸变化 → SSH 窗口大小
    terminal.onResize = (width, height, _, _) =>
        _shell?.resizeTerminal(width, height);

    final started = await client.shell();
    _shell = started;

    terminal.onOutput = (data) => started.write(utf8.encode(data));
    terminal.onResize = (width, height, _, _) =>
        started.resizeTerminal(width, height);

    // SSH 输出 → 终端（UTF-8 容错解码，避免多字节被截断）
    _stdoutSub = started.stdout.listen((bytes) {
      terminal.write(utf8.decode(bytes, allowMalformed: true));
    });
    _stderrSub = started.stderr.listen((bytes) {
      terminal.write(utf8.decode(bytes, allowMalformed: true));
    });

    status.value = SshSessionStatus.connected;
    error.value = null;

    // 远端关闭时更新状态
    unawaited(client.done.whenComplete(() {
      if (_closed) return;
      _closed = true;
      status.value = SshSessionStatus.closed;
    }));
  }

  /// 获取（懒创建）SFTP 客户端；未连接时抛出。
  Future<SftpClient> sftp() async {
    if (_sftp != null) return _sftp!;
    final client = _client;
    if (client == null) {
      throw StateError('SSH 未连接');
    }
    _sftp = await client.sftp();
    return _sftp!;
  }

  /// 关闭会话：取消订阅、关闭连接与终端。
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    try {
      await _sftp?.close();
    } catch (_) {}
    try {
      _shell?.close();
    } catch (_) {}
    try {
      _client?.close();
    } catch (_) {}
    status.value = SshSessionStatus.closed;
  }
}

/// 多开 SSH 会话管理：连接 id -> 会话句柄。
final sshSessionsProvider =
    NotifierProvider<SshSessionsController, Map<String, SshSessionHandle>>(
  SshSessionsController.new,
);

class SshSessionsController extends Notifier<Map<String, SshSessionHandle>> {
  @override
  Map<String, SshSessionHandle> build() => const {};

  /// 打开一个会话（同一连接只开一个实例）。
  Future<void> open(SshConnection connection) async {
    if (state.containsKey(connection.id)) return;
    final handle = SshSessionHandle(
      connection: connection,
      terminal: Terminal(maxLines: 5000),
    );
    state = {...state, connection.id: handle};
    try {
      await handle.connect(ref.read(sshConnectorProvider));
    } catch (e) {
      handle.status.value = SshSessionStatus.error;
      handle.error.value = '连接失败：$e';
      handle.terminal.write('连接失败：$e\r\n');
    }
  }

  /// 关闭会话。
  void close(String connectionId) {
    final handle = state[connectionId];
    if (handle == null) return;
    handle.dispose();
    final next = {...state}..remove(connectionId);
    state = next;
  }
}
