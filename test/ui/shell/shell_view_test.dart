import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:toolbox/registry/platform_type.dart';
import 'package:toolbox/registry/tool.dart';
import 'package:toolbox/registry/tool_category.dart';
import 'package:toolbox/registry/tool_registry.dart';
import 'package:toolbox/registry/toolbox_registry.dart';
import 'package:toolbox/ui/shell/shell_view.dart';
import 'package:toolbox/ui/theme/appflowy_theme.dart';
import 'package:toolbox/ui/theme/forui_theme.dart';

class _TestTool extends Tool {
  _TestTool(this._id, this._name, this._category);
  final String _id;
  final String _name;
  final ToolCategory _category;

  @override
  String get id => _id;
  @override
  String get name => _name;
  @override
  String get description => '测试工具';
  @override
  ToolCategory get category => _category;
  @override
  Set<PlatformType> get supportedPlatforms => {PlatformType.windows};
  @override
  Widget buildContent(BuildContext context) => Center(child: Text('内容区:$_name'));
}

class _TestRegistry extends ToolRegistry {
  @override
  List<Tool> registerAll() => [
        _TestTool('t1', '工具一', ToolCategory.database),
        _TestTool('t2', '工具二', ToolCategory.other),
      ];
}

void main() {
  // 注意：flutter test 默认模拟 android 平台，而 _TestTool 仅支持
  // windows（availableTools 按平台过滤）。故每个测试体内固定平台为
  // windows，并在测试体末尾恢复 —— foundation debug 变量的校验
  // （_verifyInvariants）在 tearDown 之前执行，只能测试体内恢复。
  Widget buildApp() => ProviderScope(
        overrides: [
          toolboxRegistryProvider.overrideWith((ref) => _TestRegistry()),
        ],
        child: MaterialApp(
          theme: AppflowyTheme.light(),
          // FSidebar 需要 FTheme 提供样式（与 main.dart 的生产包裹一致）。
          home: FTheme(
            data: buildForuiTheme(Brightness.light),
            child: const ShellView(),
          ),
        ),
      );

  testWidgets('顶部导航显示首页与设置按钮，默认渲染首页占位', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(buildApp());
    // 顶部「首页」与「设置」下拉按钮常驻
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    // 默认显示首页（内容区占位），未选中工具
    expect(find.text('内容区:工具一'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('无工具时不显示设置按钮', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppflowyTheme.light(),
          home: FTheme(
            data: buildForuiTheme(Brightness.light),
            child: const ShellView(),
          ),
        ),
      ),
    );
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('设置'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('点击设置打开下拉菜单，选择工具切换内容区，首页可返回', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(buildApp());
    // 打开下拉菜单：直接显示工具项（不显示分类名）
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('工具一'), findsOneWidget);
    expect(find.text('工具二'), findsOneWidget);
    // 选择「工具二」→ 内容区切换
    await tester.tap(find.text('工具二'));
    await tester.pumpAndSettle();
    expect(find.text('内容区:工具二'), findsOneWidget);
    // 点击「首页」返回
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    expect(find.text('内容区:工具二'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
