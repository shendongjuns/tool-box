import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:toolbox/ui/theme/forui_theme.dart';
import 'package:toolbox/ui/widgets/app_empty_hint.dart';

/// 空状态溢出回归测试。
///
/// 背景：空状态出现在可拖拽 / 可折叠的面板里（文件面板、监控栏、仓库列表），
/// 面板被拖小后可用高度可能只剩 100px 出头。旧实现是固定尺寸的 Column，
/// 用户实际看到过 `BOTTOM OVERFLOWED BY 92 PIXELS`。
void main() {
  Widget wrap(Widget child) => FTheme(
    data: AppTheme.light,
    child: MaterialApp(home: Scaffold(body: child)),
  );

  /// 一轮「按尺寸渲染并收集渲染期异常」。
  Future<List<FlutterErrorDetails>> renderAt(
    WidgetTester tester,
    Size paneSize,
  ) async {
    final errors = <FlutterErrorDetails>[];
    final old = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details);
      old?.call(details);
    };
    try {
      await tester.pumpWidget(
        wrap(
          Center(
            child: SizedBox(
              width: paneSize.width,
              height: paneSize.height,
              child: AppEmptyHint(
                icon: FLucideIcons.package,
                text: '这个分组还没有仓库',
                detail: '可以手动新增，或批量导入地址',
                onAction: () {},
                actionLabel: '新增仓库',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    } finally {
      FlutterError.onError = old;
    }
    return errors;
  }

  testWidgets('任何面板高度下都不溢出（含带操作按钮的最坏情况）', (tester) async {
    // 从「足够高」到「几乎压扁」，覆盖拖拽全过程会遇到的高度
    const sizes = [
      Size(320, 320),
      Size(320, 220),
      Size(320, 168), // 用户截图里溢出 92px 的档位
      Size(320, 130),
      Size(320, 90),
      Size(320, 56),
      Size(200, 40),
    ];

    for (final size in sizes) {
      final errors = await renderAt(tester, size);
      expect(
        errors,
        isEmpty,
        reason: '面板 $size 下出现渲染异常：'
            '${errors.map((e) => e.exception.toString()).join(' | ')}',
      );
    }
  });

  testWidgets('空间不足时依次省略 按钮 → 图标 → 说明，标题始终保留', (tester) async {
    // 够高：图标/说明/按钮齐全
    await renderAt(tester, const Size(320, 320));
    expect(find.text('这个分组还没有仓库'), findsOneWidget);
    expect(find.text('可以手动新增，或批量导入地址'), findsOneWidget);
    expect(find.text('新增仓库'), findsOneWidget);

    // 中等：按钮先让位（它是可选的，标题与说明更重要）
    await renderAt(tester, const Size(320, 130));
    expect(find.text('这个分组还没有仓库'), findsOneWidget);
    expect(find.text('可以手动新增，或批量导入地址'), findsOneWidget);
    expect(find.text('新增仓库'), findsNothing);

    // 很矮：只留标题
    await renderAt(tester, const Size(320, 40));
    expect(find.text('这个分组还没有仓库'), findsOneWidget);
    expect(find.text('可以手动新增，或批量导入地址'), findsNothing);
  });
}
