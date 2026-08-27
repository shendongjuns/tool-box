import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/features/repository/repo_controller.dart';
import 'package:toolbox/features/repository/repo_models.dart';
import 'package:toolbox/features/repository/repo_store.dart';
import 'package:toolbox/features/repository/repo_view.dart';
import 'package:toolbox/ui/theme/mochi_cat_theme.dart';

class _FakeRepoController extends RepoController {
  _FakeRepoController(this._groups);
  final List<RepoGroup> _groups;
  @override
  List<RepoGroup> build() => _groups;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('repo_layout_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  RepoGroup makeGroup() => RepoGroup(
        id: 'g1',
        name: '支付中心',
        version: '2.8',
        localPath: r'D:\workspace\payment',
        repos: [
          Repo(id: 'r1', name: 'order-service', type: RepoType.svn, url: 'svn.example.com/order'),
          Repo(id: 'r2', name: 'user-center', type: RepoType.git, url: 'github.com/user-center'),
        ],
      );

  testWidgets('仓库页四个操作按钮同一行且无溢出', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final errors = <FlutterErrorDetails>[];
    final old = FlutterError.onError;
    FlutterError.onError = (d) {
      errors.add(d);
      old?.call(d);
    };
    addTearDown(() => FlutterError.onError = old);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repoStoreProvider.overrideWithValue(RepoStore(dir: tempDir.path)),
          repoGroupsProvider.overrideWith(() => _FakeRepoController([makeGroup()])),
        ],
        child: MaterialApp(
          theme: MochiCatTheme.light(),
          home: const Scaffold(body: RepositoryView()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // 四个操作按钮
    expect(find.text('本地拉取'), findsOneWidget);
    expect(find.text('远程拉取'), findsOneWidget);
    expect(find.text('新增仓库'), findsOneWidget);
    expect(find.text('批量导入'), findsOneWidget);

    // 验证四个按钮在同一行：它们的 dy 坐标一致
    final localDy = tester.getTopLeft(find.text('本地拉取')).dy;
    final remoteDy = tester.getTopLeft(find.text('远程拉取')).dy;
    final addDy = tester.getTopLeft(find.text('新增仓库')).dy;
    final importDy = tester.getTopLeft(find.text('批量导入')).dy;
    expect(localDy, closeTo(remoteDy, 1));
    expect(localDy, closeTo(addDy, 1));
    expect(localDy, closeTo(importDy, 1));

    expect(errors, isEmpty,
        reason: errors.map((e) => e.exception.toString()).join('\n'));
  });
}
