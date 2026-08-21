import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/features/repository/pull_controller.dart';
import 'package:toolbox/features/repository/repo_models.dart';
import 'package:toolbox/features/repository/svn_client.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pull_controller_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  RepoGroup groupWith({
    required String localPath,
    List<Repo>? repos,
    String? version,
  }) =>
      RepoGroup(
        id: 'g1',
        name: 'group',
        version: version,
        localPath: localPath,
        repos: repos ?? const [],
      );

  Repo svnRepo(String id, String name, String url) =>
      Repo(id: id, name: name, type: RepoType.svn, url: url);

  ProviderContainer containerWith(SvnRunner runner) {
    final container = ProviderContainer(
      overrides: [svnRunnerProvider.overrideWithValue(runner)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('成功检出全部 SVN 仓库并解析版本地址', () async {
    final calls = <List<String>>[];
    final container = containerWith(
      (List<String> args, {Duration timeout = const Duration(minutes: 10)}) async {
        calls.add(args);
        return 'ok';
      },
    );
    final group = groupWith(
      localPath: tempDir.path,
      version: '2.8',
      repos: [
        svnRepo('r1', 'tz', 'https://x/tz-{version}'),
        svnRepo('r2', 'tz_ui', 'https://x/tz_ui-{version}'),
      ],
    );

    final summary = await container
        .read(repoPullControllerProvider.notifier)
        .pullGroup(group);

    expect(summary!.success, 2);
    expect(summary.skipped, 0);
    expect(summary.failed, 0);
    expect(calls, hasLength(2));
    expect(
      calls[0],
      [
        'checkout',
        '--non-interactive',
        'https://x/proj-V1.0',
        '${tempDir.path}${Platform.pathSeparator}proj-V1.0',
      ],
    );
    final statuses = container.read(repoPullControllerProvider);
    expect(statuses['r1'], PullStatus.success);
    expect(statuses['r2'], PullStatus.success);
  });

  test('目标目录已存在且非空时执行 svn update', () async {
    final calls = <List<String>>[];
    final container = containerWith(
      (List<String> args, {Duration timeout = const Duration(minutes: 10)}) async {
        calls.add(args);
        return 'ok';
      },
    );
    Directory('${tempDir.path}${Platform.pathSeparator}tz').createSync();
    File('${tempDir.path}${Platform.pathSeparator}tz${Platform.pathSeparator}x')
        .writeAsStringSync('x');
    final group = groupWith(
      localPath: tempDir.path,
      repos: [svnRepo('r1', 'tz', 'https://x/tz')],
    );

    final summary = await container
        .read(repoPullControllerProvider.notifier)
        .pullGroup(group);

    expect(summary!.success, 1);
    expect(summary.skipped, 0);
    // 已有代码 → 执行 update 而非 checkout。
    expect(calls, hasLength(1));
    expect(calls.first.first, 'update');
    expect(
      container.read(repoPullControllerProvider)['r1'],
      PullStatus.success,
    );
  });

  test('Git 仓库跳过', () async {
    final calls = <List<String>>[];
    final container = containerWith(
      (List<String> args, {Duration timeout = const Duration(minutes: 10)}) async {
        calls.add(args);
        return 'ok';
      },
    );
    final group = groupWith(
      localPath: tempDir.path,
      repos: [
        Repo(
          id: 'r1',
          name: 'tool-box',
          type: RepoType.git,
          url: 'https://github.com/x/tool-box.git',
        ),
      ],
    );

    final summary = await container
        .read(repoPullControllerProvider.notifier)
        .pullGroup(group);

    expect(summary!.skipped, 1);
    expect(calls, isEmpty);
  });

  test('runner 抛异常时标记失败并继续后续仓库', () async {
    var calls = 0;
    final container = containerWith(
      (List<String> args, {Duration timeout = const Duration(minutes: 10)}) async {
        calls++;
        if (calls == 1) throw const SvnException('boom');
        return 'ok';
      },
    );
    final group = groupWith(
      localPath: tempDir.path,
      repos: [
        svnRepo('r1', 'a', 'https://x/a'),
        svnRepo('r2', 'b', 'https://x/b'),
      ],
    );

    final summary = await container
        .read(repoPullControllerProvider.notifier)
        .pullGroup(group);

    expect(summary!.failed, 1);
    expect(summary.success, 1);
    final statuses = container.read(repoPullControllerProvider);
    expect(statuses['r1'], PullStatus.failed);
    expect(statuses['r2'], PullStatus.success);
  });

  test('未绑定文件夹时返回 null，不执行 svn', () async {
    final calls = <List<String>>[];
    final container = containerWith(
      (List<String> args, {Duration timeout = const Duration(minutes: 10)}) async {
        calls.add(args);
        return 'ok';
      },
    );
    final group = groupWith(
      localPath: '',
      repos: [svnRepo('r1', 'a', 'https://x/a')],
    );

    final summary = await container
        .read(repoPullControllerProvider.notifier)
        .pullGroup(group);

    expect(summary, isNull);
    expect(calls, isEmpty);
  });
}
