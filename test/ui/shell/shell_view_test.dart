import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:toolbox/common/settings_store.dart';
import 'package:toolbox/registry/platform_type.dart';
import 'package:toolbox/registry/tool.dart';
import 'package:toolbox/registry/tool_category.dart';
import 'package:toolbox/registry/tool_registry.dart';
import 'package:toolbox/registry/toolbox_registry.dart';
import 'package:toolbox/ui/shell/shell_view.dart';
import 'package:toolbox/ui/theme/appflowy_theme.dart';
import 'package:toolbox/ui/theme/forui_theme.dart';
import 'package:toolbox/ui/theme/theme_controller.dart';

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

/// 带自增计数的假工具：用于验证页面切换后 State 保活。
class _CounterTool extends Tool {
  @override
  String get id => 'counter';
  @override
  String get name => '计数器';
  @override
  String get description => '测试状态保活';
  @override
  ToolCategory get category => ToolCategory.work;
  @override
  Set<PlatformType> get supportedPlatforms => {PlatformType.windows};
  @override
  Widget buildContent(BuildContext context) => const _CounterPage();
}

class _CounterPage extends StatefulWidget {
  const _CounterPage();

  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('计数:$_count'),
          TextButton(
            onPressed: () => setState(() => _count++),
            child: const Text('加一'),
          ),
        ],
      ),
    );
  }
}

class _TestRegistry extends ToolRegistry {
  @override
  List<Tool> registerAll() => [
        _TestTool('t1', '工具一', ToolCategory.database),
        _TestTool('t2', '工具二', ToolCategory.other),
        _CounterTool(),
      ];
}

void main() {
  // 注意：flutter test 默认模拟 android 平台，而 _TestTool 仅支持
  // windows（availableTools 按平台过滤）。故每个测试体内固定平台为
  // windows，并在测试体末尾恢复 —— foundation debug 变量的校验
  // （_verifyInvariants）在 tearDown 之前执行，只能测试体内恢复。
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('shell_view_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Widget buildApp() => ProviderScope(
        overrides: [
          toolboxRegistryProvider.overrideWith((ref) => _TestRegistry()),
          settingsStoreProvider
              .overrideWithValue(SettingsStore(dir: tempDir.path)),
        ],
        child: MaterialApp(
          theme: AppflowyTheme.light(),
          // FTheme 需要提供样式（与 main.dart 的生产包裹一致）。
          home: FTheme(
            data: buildForuiTheme(Brightness.light),
            child: const ShellView(),
          ),
        ),
      );

  testWidgets('顶部导航显示首页与分类菜单，默认渲染首页占位', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(buildApp());
    // 顶部「首页」常驻，每个有工具的分类一个菜单项
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('工作'), findsOneWidget);
    expect(find.text('数据库管理'), findsOneWidget);
    expect(find.text('其他工具'), findsOneWidget);
    // 默认显示首页占位，未打开任何页面（无标签条）
    expect(find.text('内容待定').hitTestable(), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('无工具时不显示分类菜单', (tester) async {
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
    expect(find.text('数据库管理'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('打开工具出现标签条，回首页后页面保活可切回', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(buildApp());
    // 打开「数据库管理」→「工具一」
    await tester.tap(find.text('数据库管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('工具一'));
    await tester.pumpAndSettle();
    // 内容区显示工具一，标签条出现（工具一 + 关闭按钮）
    expect(find.text('内容区:工具一').hitTestable(), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    // 点「首页」：首页可见，但页面保活（标签条仍在，可切回）
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    expect(find.text('内容待定').hitTestable(), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    // 点标签切回工具一
    await tester.tap(find.text('工具一'));
    await tester.pumpAndSettle();
    expect(find.text('内容区:工具一').hitTestable(), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('切换工具后页面 State 保活（计数不丢失）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(buildApp());
    // 打开「工作」→「计数器」，点两次「加一」
    await tester.tap(find.text('工作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计数器'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加一'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加一'));
    await tester.pumpAndSettle();
    expect(find.text('计数:2'), findsOneWidget);
    // 打开「工具一」：当前页切走
    await tester.tap(find.text('数据库管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('工具一'));
    await tester.pumpAndSettle();
    // 切回「计数器」标签：State 保活，计数仍为 2
    await tester.tap(find.text('计数器'));
    await tester.pumpAndSettle();
    expect(find.text('计数:2'), findsOneWidget);
    expect(find.text('计数:0'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('关闭当前页回退相邻页，关闭最后一页回首页', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(buildApp());
    // 打开两个页面：工具一、工具二（当前为工具二）
    await tester.tap(find.text('数据库管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('工具一'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('其他工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('工具二'));
    await tester.pumpAndSettle();
    // 关闭当前页「工具二」（最后一个标签的 ×）：回退到「工具一」
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();
    expect(find.text('内容区:工具二'), findsNothing);
    expect(find.text('内容区:工具一').hitTestable(), findsOneWidget);
    // 关闭最后一页「工具一」：回首页，无标签条
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(find.text('内容区:工具一'), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.text('内容待定').hitTestable(), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('点击主题按钮循环切换主题模式', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(buildApp());
    // 初始为跟随系统
    expect(find.byIcon(Icons.brightness_auto), findsOneWidget);
    // 系统 → 浅色
    await tester.tap(find.byIcon(Icons.brightness_auto));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.light_mode), findsOneWidget);
    // 浅色 → 深色
    await tester.tap(find.byIcon(Icons.light_mode));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.dark_mode), findsOneWidget);
    // 深色 → 系统
    await tester.tap(find.byIcon(Icons.dark_mode));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.brightness_auto), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
