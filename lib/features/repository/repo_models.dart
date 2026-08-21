import 'package:flutter/foundation.dart';

/// 仓库类型。
enum RepoType {
  svn('svn', 'SVN'),
  git('git', 'Git');

  const RepoType(this.name, this.label);

  /// 序列化用标识。
  final String name;

  /// 界面展示名。
  final String label;

  static RepoType fromName(String? name) => values.firstWhere(
        (e) => e.name == name,
        orElse: () => RepoType.svn,
      );
}

/// 生成唯一 id（时间戳 + 自增序号，避免依赖 uuid 包）。
int _idCounter = 0;
String newId() => '${DateTime.now().microsecondsSinceEpoch}-${_idCounter += 1}';

/// 单个仓库地址。
@immutable
class Repo {
  const Repo({
    required this.id,
    required this.name,
    required this.type,
    required this.url,
  });

  final String id;
  final String name;
  final RepoType type;

  /// 仓库地址模板；SVN 地址可用 `{version}` 占位符引用分组的版本变量。
  final String url;

  Repo copyWith({String? name, RepoType? type, String? url}) => Repo(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        url: url ?? this.url,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'url': url,
      };

  factory Repo.fromJson(Map<String, dynamic> json) => Repo(
        id: json['id'] as String,
        name: json['name'] as String,
        type: RepoType.fromName(json['type'] as String?),
        url: json['url'] as String,
      );
}

/// 仓库分组：一组仓库 + 共享的版本变量 + 本地落地文件夹。
@immutable
/// 单个 SSH 连接的远程拉取绑定（远程目录 + SVN 账号）。
class RepoRemoteBinding {
  const RepoRemoteBinding({
    required this.remotePath,
    this.svnUsername,
    this.svnPassword,
  });

  final String remotePath;
  final String? svnUsername;
  final String? svnPassword;

  Map<String, dynamic> toJson() => {
        'remotePath': remotePath,
        'svnUsername': svnUsername,
        'svnPassword': svnPassword,
      };

  factory RepoRemoteBinding.fromJson(Map<String, dynamic> json) =>
      RepoRemoteBinding(
        remotePath: json['remotePath'] as String? ?? '',
        svnUsername: json['svnUsername'] as String?,
        svnPassword: json['svnPassword'] as String?,
      );
}

class RepoGroup {
  const RepoGroup({
    required this.id,
    required this.name,
    required this.version,
    this.localPath,
    this.remotes = const {},
    this.activeRemoteConnId,
    required this.repos,
  });

  final String id;
  final String name;

  /// 版本变量（如 `2.8`）；为 null 表示未设置。
  final String? version;

  /// 本地落地文件夹（一键拉取的根目录）；为 null 表示未绑定。
  final String? localPath;

  /// 远程拉取绑定：SSH 连接 id -> 绑定（远程目录 + SVN 账号）。
  final Map<String, RepoRemoteBinding> remotes;

  /// 当前远程拉取目标连接（上次使用的）；为 null 时取第一个绑定。
  final String? activeRemoteConnId;
  final List<Repo> repos;

  RepoGroup copyWith({
    String? name,
    String? version,
    String? localPath,
    Map<String, RepoRemoteBinding>? remotes,
    String? activeRemoteConnId,
    List<Repo>? repos,
  }) =>
      RepoGroup(
        id: id,
        name: name ?? this.name,
        version: version ?? this.version,
        localPath: localPath ?? this.localPath,
        remotes: remotes ?? this.remotes,
        activeRemoteConnId: activeRemoteConnId ?? this.activeRemoteConnId,
        repos: repos ?? this.repos,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'localPath': localPath,
        'remotes': remotes.map((k, v) => MapEntry(k, v.toJson())),
        'activeRemoteConnId': activeRemoteConnId,
        'repos': repos.map((e) => e.toJson()).toList(),
      };

  factory RepoGroup.fromJson(Map<String, dynamic> json) {
    // 兼容旧字段：remoteConnectionId/remotePath/svn* 迁移到 remotes。
    final legacyConn = json['remoteConnectionId'] as String?;
    final legacyPath = json['remotePath'] as String?;
    final remotes = <String, RepoRemoteBinding>{};
    final jsonRemotes = json['remotes'];
    if (jsonRemotes is Map<String, dynamic>) {
      jsonRemotes.forEach((k, v) {
        if (v is Map<String, dynamic>) {
          remotes[k] = RepoRemoteBinding.fromJson(v);
        }
      });
    }
    if (legacyConn != null && legacyPath != null && legacyPath.isNotEmpty) {
      remotes.putIfAbsent(legacyConn, () => RepoRemoteBinding(
            remotePath: legacyPath,
            svnUsername: json['svnUsername'] as String?,
            svnPassword: json['svnPassword'] as String?,
          ));
    }
    return RepoGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String?,
      localPath: json['localPath'] as String?,
      remotes: remotes,
      activeRemoteConnId: json['activeRemoteConnId'] as String?,
      repos: (json['repos'] as List<dynamic>? ?? const [])
          .map((e) => Repo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// 归一化版本号：去除首部 V/v 并去空白；空值返回 null。
///
/// 版本号（如 `V2.8`）中的 V 是固定前缀，录入与存储时省略，解析/展示时统一补回。
String? normalizeVersion(String? raw) {
  final v = raw?.trim();
  if (v == null || v.isEmpty) return null;
  return v.replaceFirst(RegExp(r'^[vV]'), '');
}
