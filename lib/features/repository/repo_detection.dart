import 'package:toolbox/features/repository/repo_models.dart';

/// 依据地址特征识别仓库类型。
RepoType detectRepoType(String raw) {
  final url = raw.trim().toLowerCase();
  if (url.isEmpty) return RepoType.svn;

  final isGit = url.startsWith('git@') ||
      url.startsWith('ssh://') ||
      url.startsWith('git://') ||
      _stripTrailingSlash(url).endsWith('.git') ||
      const ['github.com', 'gitlab.', 'gitee.com', 'bitbucket.org']
          .any(url.contains);
  if (isGit) return RepoType.git;

  final isSvn = url.contains('/svn/') ||
      url.startsWith('svn://') ||
      url.startsWith('svn+ssh://');
  if (isSvn) return RepoType.svn;

  // 无法明确识别时默认 SVN（用户可手动修正）。
  return RepoType.svn;
}

/// 从多条地址中识别共通版本号（数字部分，如 `2.8`）。
///
/// 版本号形如 `V2.8`，V 为固定前缀，此处只返回数字部分；自动排除 IP 地址段，
/// 避免把 `10.0.0.10` 误判为版本号。
String? detectVersion(List<String> urls) {
  final ipRegex = RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}\b');
  final versionRegex = RegExp(r'[vV](\d+(?:\.\d+){1,3})');

  final perUrl = <Set<String>>[];
  for (final raw in urls) {
    final url = raw.trim();
    if (url.isEmpty) continue;
    final withoutIp = url.replaceAll(ipRegex, '');
    final candidates = <String>{};
    for (final match in versionRegex.allMatches(withoutIp)) {
      candidates.add(match.group(1)!);
    }
    perUrl.add(candidates);
  }

  if (perUrl.isEmpty) return null;

  // 求各地址版本号数字部分的交集。
  var common = perUrl.first;
  for (final m in perUrl.skip(1)) {
    common = common.intersection(m);
  }
  if (common.isEmpty) return null;

  final sorted = common.toList()..sort();
  return sorted.first;
}

/// 解析批量粘贴文本为仓库列表。
///
/// [version] 为版本号数字部分；SVN 地址中 `V{version}`（含固定 V 前缀）会被
/// 替换为 `{version}` 占位符。Git 地址不做版本替换。
List<Repo> parseBatch(String text, {String? version}) {
  final v = normalizeVersion(version);
  final repos = <Repo>[];
  final seen = <String>{};
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final url = line.trim();
    if (url.isEmpty) continue;
    if (!seen.add(url)) continue;

    final type = detectRepoType(url);
    var template = url;
    if (type == RepoType.svn && v != null) {
      template = _replaceCaseInsensitive(template, 'V$v', '{version}');
    }
    repos.add(Repo(
      id: newId(),
      name: deriveRepoName(url, version: v),
      type: type,
      url: template,
    ));
  }
  return repos;
}

/// 依据地址推导仓库名：取末段，去掉 `V{version}` 后缀与 `.git`。
String deriveRepoName(String rawUrl, {String? version}) {
  var url = rawUrl.trim();
  url = _stripTrailingSlash(url);
  var name = url.split(RegExp(r'[/:]')).last;

  if (name.toLowerCase().endsWith('.git')) {
    name = name.substring(0, name.length - 4);
  }
  final v = normalizeVersion(version);
  if (v != null) {
    name = _replaceCaseInsensitive(name, 'V$v', '');
    name = name.replaceAll(RegExp(r'[-_]$'), '');
  }
  return name.isEmpty ? url : name;
}

/// 解析仓库地址模板：将 `{version}` 替换为 `V` + 版本号（V 为固定前缀）。
String resolveUrl(String url, String? version) {
  final v = normalizeVersion(version);
  return url.replaceAll('{version}', v == null ? '' : 'V$v');
}

String _stripTrailingSlash(String s) {
  var result = s;
  while (result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

String _replaceCaseInsensitive(String input, String from, String to) =>
    input.replaceAll(RegExp(RegExp.escape(from), caseSensitive: false), to);
