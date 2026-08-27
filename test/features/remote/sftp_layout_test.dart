import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/features/remote/remote_models.dart';
import 'package:toolbox/features/remote/sftp_view.dart';
import 'package:toolbox/features/remote/ssh_session.dart';
import 'package:toolbox/ui/theme/mochi_cat_theme.dart';
import 'package:xterm/xterm.dart';

void main() {
  testWidgets('SftpView 在 200px 高内不溢出', (tester) async {
    final conn = SshConnection(
      id: 'c1',
      name: 't',
      host: 'h',
      port: 22,
      username: 'u',
      password: '',
    );
    final handle = SshSessionHandle(connection: conn, terminal: Terminal());

    final errors = <FlutterErrorDetails>[];
    final old = FlutterError.onError;
    FlutterError.onError = (d) {
      errors.add(d);
      old?.call(d);
    };
    addTearDown(() => FlutterError.onError = old);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: MochiCatTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 330,
                height: 166,
                child: SftpView(handle: handle),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(errors, isEmpty,
        reason: errors.map((e) => e.exception.toString()).join('\n'));
  });

  testWidgets('默认文件面板宽度(440px)下工具栏按钮可见', (tester) async {
    final conn = SshConnection(
      id: 'c1',
      name: 't',
      host: 'h',
      port: 22,
      username: 'u',
      password: '',
    );
    final handle = SshSessionHandle(connection: conn, terminal: Terminal());

    final errors = <FlutterErrorDetails>[];
    final old = FlutterError.onError;
    FlutterError.onError = (d) {
      errors.add(d);
      old?.call(d);
    };
    addTearDown(() => FlutterError.onError = old);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: MochiCatTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 440,
                height: 300,
                child: SftpView(handle: handle),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 排序(显示默认选中"名称")/新建目录/上传/传输记录按钮都应在工具栏中
    expect(find.text('名称'), findsOneWidget);
    expect(find.text('新建目录'), findsOneWidget);
    expect(find.text('上传'), findsOneWidget);
    expect(find.byTooltip('传输记录'), findsOneWidget);

    expect(errors, isEmpty,
        reason: errors.map((e) => e.exception.toString()).join('\n'));
  });
}
