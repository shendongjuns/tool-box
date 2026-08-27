import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/features/remote/remote_controller.dart';
import 'package:toolbox/features/remote/remote_models.dart';
import 'package:toolbox/features/remote/remote_store.dart';
import 'package:toolbox/features/remote/remote_view.dart';
import 'package:toolbox/features/remote/ssh_session.dart';
import 'package:toolbox/ui/theme/mochi_cat_theme.dart';
import 'package:xterm/xterm.dart';

/// 预置假会话（未连接，仅用于渲染布局）。
class _FakeSessionsController extends SshSessionsController {
  _FakeSessionsController(this._handles);
  final Map<String, SshSessionHandle> _handles;
  @override
  Map<String, SshSessionHandle> build() => _handles;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('remote_layout_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Widget buildApp(Map<String, SshSessionHandle> sessions) {
    return ProviderScope(
      overrides: [
        remoteStoreProvider.overrideWithValue(RemoteStore(dir: tempDir.path)),
        sshSessionsProvider.overrideWith(() => _FakeSessionsController(sessions)),
      ],
      child: MaterialApp(
        theme: MochiCatTheme.light(),
        home: const Scaffold(body: RemoteView()),
      ),
    );
  }

  SshSessionHandle makeHandle(String id, String name) => SshSessionHandle(
        connection: SshConnection(
          id: id,
          name: name,
          host: '10.0.0.1',
          port: 22,
          username: 'root',
          password: '',
        ),
        terminal: Terminal(),
      );

  testWidgets('远程工作台 1200x800 有会话时终端/文件/监控齐全', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final errors = <FlutterErrorDetails>[];
    final oldOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details);
      oldOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = oldOnError);

    await tester.pumpWidget(buildApp({'c1': makeHandle('c1', '测试服务器')}));
    await tester.pump(const Duration(milliseconds: 200));

    // 终端/文件面板标题、监控标题齐全
    expect(find.text('终端'), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);
    // 终端/文件各自有隐藏按钮（tooltip）
    expect(find.byTooltip('隐藏终端'), findsOneWidget);
    expect(find.byTooltip('隐藏文件'), findsOneWidget);

    expect(errors, isEmpty,
        reason: errors.map((e) => e.exception.toString()).join('\n'));
  });

  testWidgets('隐藏终端后出现恢复条，可恢复', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildApp({'c1': makeHandle('c1', '测试服务器')}));
    await tester.pump(const Duration(milliseconds: 200));

    // 隐藏终端
    await tester.tap(find.byTooltip('隐藏终端'));
    await tester.pump(const Duration(milliseconds: 150));
    // 终端隐藏后无"隐藏终端"，出现"显示终端"恢复条
    expect(find.byTooltip('隐藏终端'), findsNothing);
    expect(find.text('显示终端'), findsOneWidget);

    // 恢复终端
    await tester.tap(find.text('显示终端'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byTooltip('隐藏终端'), findsOneWidget);
  });

  testWidgets('隐藏文件后出现恢复条，可恢复', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildApp({'c1': makeHandle('c1', '测试服务器')}));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byTooltip('隐藏文件'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byTooltip('隐藏文件'), findsNothing);
    expect(find.text('显示文件'), findsOneWidget);

    await tester.tap(find.text('显示文件'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byTooltip('隐藏文件'), findsOneWidget);
  });
}
