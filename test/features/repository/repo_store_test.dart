import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/features/repository/repo_models.dart';
import 'package:toolbox/features/repository/repo_store.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('repo_store_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('保存后读取可往返（含 localPath/远程绑定）', () {
    final store = RepoStore(dir: tempDir.path);
    store.save([
      RepoGroup(
        id: 'g1',
        name: 'group',
        version: '2.8',
        localPath: 'D:\\work\\tz',
        remotes: {
          'conn-1': const RepoRemoteBinding(
            remotePath: '/home/user/code',
            svnUsername: 'svnuser',
            svnPassword: 'svnpass',
          ),
        },
        repos: [
          Repo(
            id: 'r1',
            name: 'tz',
            type: RepoType.svn,
            url: 'https://x/tz-{version}',
          ),
        ],
      ),
    ]);

    final loaded = store.load();
    expect(loaded, hasLength(1));
    expect(loaded.single.name, 'group');
    expect(loaded.single.version, '2.8');
    expect(loaded.single.localPath, 'D:\\work\\tz');
    expect(loaded.single.remotes['conn-1']!.remotePath, '/home/user/code');
    expect(loaded.single.remotes['conn-1']!.svnUsername, 'svnuser');
    expect(loaded.single.repos.single.url, 'https://x/tz-{version}');
  });

  test('旧字段 remoteConnectionId/remotePath 迁移到 remotes', () {
    final store = RepoStore(dir: tempDir.path);
    // 模拟旧版本数据（直接用旧字段写 JSON）。
    store.save([
      RepoGroup.fromJson({
        'id': 'g1',
        'name': 'group',
        'version': '2.8',
        'remoteConnectionId': 'conn-1',
        'remotePath': '/home/user/code',
        'svnUsername': 'u',
        'svnPassword': 'p',
        'repos': <dynamic>[],
      }),
    ]);

    final loaded = store.load();
    final binding = loaded.single.remotes['conn-1'];
    expect(binding, isNotNull);
    expect(binding!.remotePath, '/home/user/code');
    expect(binding.svnUsername, 'u');
  });

  test('文件不存在时返回空列表', () {
    final store = RepoStore(dir: tempDir.path);
    expect(store.load(), isEmpty);
  });

  test('文件损坏时返回空列表', () {
    final dir = Directory(tempDir.path);
    final file = File('${tempDir.path}${Platform.pathSeparator}repo_groups.json');
    file.writeAsStringSync('not-json');
    final store = RepoStore(dir: dir.path);
    expect(store.load(), isEmpty);
  });
}
