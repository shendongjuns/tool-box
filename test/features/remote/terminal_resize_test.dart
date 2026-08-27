import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/features/remote/remote_models.dart';
import 'package:toolbox/features/remote/ssh_session.dart';
import 'package:toolbox/ui/theme/mochi_cat_theme.dart';
import 'package:xterm/xterm.dart';

/// 验证终端面板在窗口尺寸变化时无溢出。
void main() {
  testWidgets('终端面板 resize 无溢出', (tester) async {
    final conn = SshConnection(
      id: 'c1', name: 't', host: 'h', port: 22, username: 'u', password: '',
    );
    final handle = SshSessionHandle(connection: conn, terminal: Terminal());

    final errors = <FlutterErrorDetails>[];
    final old = FlutterError.onError;
    FlutterError.onError = (d) {
      errors.add(d);
      old?.call(d);
    };
    addTearDown(() => FlutterError.onError = old);

    Widget build(double height) => MaterialApp(
          theme: MochiCatTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: height,
                child: _TestTerminalPane(handle: handle),
              ),
            ),
          ),
        );

    // 初始 300px，缩小到 150，再放大到 350。
    await tester.pumpWidget(build(300));
    await tester.pump();
    await tester.pumpWidget(build(150));
    await tester.pump();
    await tester.pumpWidget(build(350));
    await tester.pump();

    expect(errors, isEmpty,
        reason: errors.map((e) => e.exception.toString()).join('\n'));
  });
}

class _TestTerminalPane extends StatelessWidget {
  const _TestTerminalPane({required this.handle});
  final SshSessionHandle handle;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF272634),
      child: Column(
        children: [
          Container(height: 36, color: Colors.white),
          Expanded(
            child: ClipRect(
              child: TerminalView(handle.terminal, hardwareKeyboardOnly: true),
            ),
          ),
        ],
      ),
    );
  }
}
