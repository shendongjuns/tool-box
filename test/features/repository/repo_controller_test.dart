import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/features/repository/repo_controller.dart';
import 'package:toolbox/features/repository/repo_detection.dart';
import 'package:toolbox/features/repository/repo_models.dart';
import 'package:toolbox/features/repository/repo_store.dart';

void main() {
  late Directory tempDir;

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        repoStoreProvider.overrideWithValue(RepoStore(dir: tempDir.path)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('repo_controller_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('新增分组与仓库，并持久化', () {
    final container = makeContainer();
    final notifier = container.read(repoGroupsProvider.notifier);
    notifier.addGroup('group', version: '2.8');
    final groupId = container.read(repoGroupsProvider).single.id;
    notifier.addRepo(
      groupId,
      Repo(
        id: 'r1',
        name: 'tz',
        type: RepoType.svn,
        url: 'https://x/tz-{version}',
      ),
    );

    final loaded = RepoStore(dir: tempDir.path).load();
    expect(loaded, hasLength(1));
    expect(loaded.single.version, '2.8');
    expect(loaded.single.repos.single.name, 'tz');
  });

  test('修改分组版本后，解析地址同步更新', () {
    final container = makeContainer();
    final notifier = container.read(repoGroupsProvider.notifier);
    notifier.addGroup('group', version: '2.8');
    final groupId = container.read(repoGroupsProvider).single.id;
    notifier.addRepo(
      groupId,
      Repo(
        id: 'r1',
        name: 'tz',
        type: RepoType.svn,
        url: 'https://x/tz-{version}',
      ),
    );

    notifier.setGroupVersion(groupId, 'V3.0');
    final group = container.read(repoGroupsProvider).single;
    expect(group.version, '3.0');
    expect(
      resolveUrl(group.repos.single.url, group.version),
      'https://x/tz-V3.0',
    );
  });

  test('删除分组后持久化同步', () {
    final container = makeContainer();
    final notifier = container.read(repoGroupsProvider.notifier);
    notifier.addGroup('group');
    final groupId = container.read(repoGroupsProvider).single.id;
    notifier.deleteGroup(groupId);
    expect(container.read(repoGroupsProvider), isEmpty);
    expect(RepoStore(dir: tempDir.path).load(), isEmpty);
  });

  test('setGroupLocalPath 设置并持久化本地文件夹', () {
    final container = makeContainer();
    final notifier = container.read(repoGroupsProvider.notifier);
    notifier.addGroup('group');
    final groupId = container.read(repoGroupsProvider).single.id;

    notifier.setGroupLocalPath(groupId, 'D:\\work\\tz');
    expect(container.read(repoGroupsProvider).single.localPath, 'D:\\work\\tz');
    expect(
      RepoStore(dir: tempDir.path).load().single.localPath,
      'D:\\work\\tz',
    );

    // 空值清除绑定
    notifier.setGroupLocalPath(groupId, '');
    expect(container.read(repoGroupsProvider).single.localPath, isNull);
  });

  test('批量导入时保存版本号并归一化', () {
    final container = makeContainer();
    final notifier = container.read(repoGroupsProvider.notifier);
    notifier.addGroup('group');
    final groupId = container.read(repoGroupsProvider).single.id;

    notifier.importRepos(
      groupId,
      [
        Repo(
          id: 'r1',
          name: 'tz',
          type: RepoType.svn,
          url: 'https://x/tz-{version}',
        ),
      ],
      version: 'V2.8',
    );

    final group = container.read(repoGroupsProvider).single;
    expect(group.version, '2.8');
  });

  test('批量导入时跳过重复仓库并返回新增数量', () {
    final container = makeContainer();
    final notifier = container.read(repoGroupsProvider.notifier);
    notifier.addGroup('group', version: '2.8');
    final groupId = container.read(repoGroupsProvider).single.id;
    notifier.addRepo(
      groupId,
      Repo(
        id: 'r1',
        name: 'tz',
        type: RepoType.svn,
        url: 'https://x/tz-{version}',
      ),
    );

    final added = notifier.importRepos(
      groupId,
      [
        // 与已有仓库地址重复 → 跳过
        Repo(
          id: 'r2',
          name: 'tz',
          type: RepoType.svn,
          url: 'https://x/tz-{version}',
        ),
        // 新仓库 → 导入
        Repo(
          id: 'r3',
          name: 'tz_ui',
          type: RepoType.svn,
          url: 'https://x/tz_ui-{version}',
        ),
      ],
      version: '2.8',
    );

    expect(added, 1);
    expect(container.read(repoGroupsProvider).single.repos, hasLength(2));
  });

  test('setGroupRemote 按连接分别保存绑定，切换连接互不影响', () {
    final container = makeContainer();
    final notifier = container.read(repoGroupsProvider.notifier);
    notifier.addGroup('group');
    final groupId = container.read(repoGroupsProvider).single.id;

    // 连接 A 绑定目录1
    notifier.setGroupRemote(groupId, 'conn-a',
        remotePath: '/home/a', svnUsername: 'ua', svnPassword: 'pa');
    // 连接 B 绑定目录2
    notifier.setGroupRemote(groupId, 'conn-b',
        remotePath: '/home/b', svnUsername: 'ub', svnPassword: 'pb');

    final group = container.read(repoGroupsProvider).single;
    expect(group.remotes['conn-a']!.remotePath, '/home/a');
    expect(group.remotes['conn-a']!.svnUsername, 'ua');
    expect(group.remotes['conn-b']!.remotePath, '/home/b');
    expect(group.remotes['conn-b']!.svnUsername, 'ub');

    // 清空连接 B 目录 → 移除 B 绑定，A 保留。
    notifier.setGroupRemote(groupId, 'conn-b', remotePath: '');
    final after = container.read(repoGroupsProvider).single;
    expect(after.remotes.containsKey('conn-b'), isFalse);
    expect(after.remotes['conn-a']!.remotePath, '/home/a');
  });

}
