import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/features/repository/repo_models.dart';
import 'package:toolbox/features/repository/repo_store.dart';

final repoStoreProvider = Provider<RepoStore>((ref) => RepoStore());

final repoGroupsProvider =
    NotifierProvider<RepoController, List<RepoGroup>>(RepoController.new);

/// 仓库分组状态：启动加载，每次变更立即持久化到安装目录。
class RepoController extends Notifier<List<RepoGroup>> {
  @override
  List<RepoGroup> build() => ref.watch(repoStoreProvider).load();

  void _persist() => ref.read(repoStoreProvider).save(state);

  RepoGroup _group(String id) => state.firstWhere(
        (g) => g.id == id,
        orElse: () => throw StateError('分组不存在: $id'),
      );

  void addGroup(String name, {String? version}) {
    final group = RepoGroup(
      id: newId(),
      name: name.trim(),
      version: normalizeVersion(version),
      repos: const [],
    );
    state = [...state, group];
    _persist();
  }

  void renameGroup(String id, String name) {
    _group(id);
    state = [
      for (final g in state)
        if (g.id == id)
          RepoGroup(
            id: g.id,
            name: name.trim(),
            version: g.version,
            repos: g.repos,
          )
        else
          g,
    ];
    _persist();
  }

  void setGroupVersion(String id, String? version) {
    _group(id);
    state = [
      for (final g in state)
        if (g.id == id)
          RepoGroup(
            id: g.id,
            name: g.name,
            version: normalizeVersion(version),
            repos: g.repos,
          )
        else
          g,
    ];
    _persist();
  }

  void setGroupLocalPath(String id, String? path) {
    _group(id);
    final p = path?.trim();
    state = [
      for (final g in state)
        if (g.id == id)
          RepoGroup(
            id: g.id,
            name: g.name,
            version: g.version,
            localPath: (p == null || p.isEmpty) ? null : p,
            repos: g.repos,
          )
        else
          g,
    ];
    _persist();
  }

  void deleteGroup(String id) {
    state = state.where((g) => g.id != id).toList();
    _persist();
  }

  void addRepo(String groupId, Repo repo) {
    _group(groupId);
    state = [
      for (final g in state)
        if (g.id == groupId) g.copyWith(repos: [...g.repos, repo]) else g,
    ];
    _persist();
  }

  void updateRepo(String groupId, Repo repo) {
    _group(groupId);
    state = [
      for (final g in state)
        if (g.id == groupId)
          RepoGroup(
            id: g.id,
            name: g.name,
            version: g.version,
            repos: [
              for (final r in g.repos)
                if (r.id == repo.id) repo else r,
            ],
          )
        else
          g,
    ];
    _persist();
  }

  void deleteRepo(String groupId, String repoId) {
    _group(groupId);
    state = [
      for (final g in state)
        if (g.id == groupId)
          RepoGroup(
            id: g.id,
            name: g.name,
            version: g.version,
            repos: g.repos.where((r) => r.id != repoId).toList(),
          )
        else
          g,
    ];
    _persist();
  }

  /// 批量导入仓库：跳过与分组内已有地址重复的项，返回实际新增数量。
  ///
  /// 传入 [version]（非空）时同步更新分组版本号。
  int importRepos(String groupId, List<Repo> repos, {String? version}) {
    if (repos.isEmpty) return 0;
    final group = _group(groupId);
    final existingUrls = {for (final r in group.repos) r.url};
    final incoming = <Repo>[];
    for (final r in repos) {
      if (existingUrls.contains(r.url)) continue;
      existingUrls.add(r.url);
      incoming.add(r);
    }
    if (incoming.isEmpty) return 0;

    final newVersion = normalizeVersion(version);
    state = [
      for (final g in state)
        if (g.id == groupId)
          RepoGroup(
            id: g.id,
            name: g.name,
            version: newVersion ?? g.version,
            repos: [...g.repos, ...incoming],
          )
        else
          g,
    ];
    _persist();
    return incoming.length;
  }
}
