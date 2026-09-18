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

  /// 反序列化：**尽量救回数据**。
  ///
  /// 旧版本或用外部工具改过的文件里，数字可能被写成字符串（`"port": "22"`）、
  /// 布尔可能缺失。这里做宽松取值而不是直接 `as` 强转——强转会让
  /// 「一条记录的类型不对」升级成「整份文件报废」。
  /// 只有 `id` 缺失才判定该条无用（由调用方跳过）。
  factory SshConnection.fromJson(Map<String, dynamic> json) => SshConnection(
    id: _requireId(json['id']),
    name: _asString(json['name']) ?? '',
    host: _asString(json['host']) ?? '',
    port: _asPort(json['port']),
    username: _asString(json['username']) ?? '',
    password: _asString(json['password']) ?? '',
    useKeyAuth: _asBool(json['useKeyAuth']) ?? false,
    privateKeyPath: _asString(json['privateKeyPath']),
    keyPassphrase: _asString(json['keyPassphrase']),
  );
}

/// `id` 缺失/为空时该条记录不可用（由调用方跳过），其余字段一律宽松取值。
String _requireId(Object? value) {
  final id = _asString(value);
  if (id == null || id.isEmpty) throw const FormatException('缺少 id');
  return id;
}

/// 端口：非数字或超出 1–65535 时回落到默认 22。
int _asPort(Object? value) {
  final port = _asInt(value);
  return (port == null || port < 1 || port > 65535) ? 22 : port;
}

/// 宽松取字符串：非字符串类型返回其字符串形式，null 仍为 null。
String? _asString(Object? value) => switch (value) {
  final String v => v,
  null => null,
  _ => '$value',
};

/// 宽松取整数：兼容 `22` / `22.0` / `"22"`。
int? _asInt(Object? value) => switch (value) {
  final int v => v,
  final num v => v.toInt(),
  final String v => int.tryParse(v.trim()),
  _ => null,
};

bool? _asBool(Object? value) => switch (value) {
  final bool v => v,
  final String v => v.toLowerCase() == 'true'
      ? true
      : (v.toLowerCase() == 'false' ? false : null),
  _ => null,
};
