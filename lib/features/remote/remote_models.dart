import 'package:flutter/foundation.dart';

/// 生成唯一 id（时间戳 + 自增序号，避免依赖 uuid 包）。
int _remoteIdCounter = 0;
String newRemoteId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${_remoteIdCounter += 1}';

/// SSH 连接信息。
@immutable
class SshConnection {
  const SshConnection({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.useKeyAuth = false,
    this.privateKeyPath,
    this.keyPassphrase,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String password;

  /// 是否使用私钥认证（true 时优先私钥，密码作保留）。
  final bool useKeyAuth;

  /// 私钥文件路径（OpenSSH / RSA PKCS#1 / EC 私钥）。
  final String? privateKeyPath;

  /// 私钥口令（可选）。
  final String? keyPassphrase;

  /// 展示用的 host:port 组合。
  String get hostLabel => '$host:$port';

  SshConnection copyWith({
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    bool? useKeyAuth,
    String? privateKeyPath,
    String? keyPassphrase,
  }) =>
      SshConnection(
        id: id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        password: password ?? this.password,
        useKeyAuth: useKeyAuth ?? this.useKeyAuth,
        privateKeyPath: privateKeyPath ?? this.privateKeyPath,
        keyPassphrase: keyPassphrase ?? this.keyPassphrase,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'useKeyAuth': useKeyAuth,
        'privateKeyPath': privateKeyPath,
        'keyPassphrase': keyPassphrase,
      };

  factory SshConnection.fromJson(Map<String, dynamic> json) => SshConnection(
        id: json['id'] as String,
        name: json['name'] as String,
        host: json['host'] as String,
        port: json['port'] as int? ?? 22,
        username: json['username'] as String,
        password: json['password'] as String? ?? '',
        useKeyAuth: json['useKeyAuth'] as bool? ?? false,
        privateKeyPath: json['privateKeyPath'] as String?,
        keyPassphrase: json['keyPassphrase'] as String?,
      );
}
