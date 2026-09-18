import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:toolbox/common/app_meta.dart';
import 'package:toolbox/common/settings_store.dart';
import 'package:toolbox/common/single_instance.dart';
import 'package:toolbox/registry/platform_type.dart';
import 'package:toolbox/registry/tool.dart';
import 'package:toolbox/registry/tool_category.dart';
import 'package:toolbox/registry/tool_registry.dart';
import 'package:toolbox/registry/toolbox_registry.dart';
import 'package:toolbox/ui/shell/navigation_controller.dart';
import 'package:toolbox/ui/shell/shell_view.dart';
import 'package:toolbox/ui/theme/forui_theme.dart';
import 'package:toolbox/ui/theme/theme_controller.dart';

import '../../support/app_finders.dart';

/// 1.5.0 版本形态：**左侧栏导航**（无顶栏、无页签）+ IndexedStack 保活。
///
/// 与 1.4.x 的差异（本文件已按新形态重写）：
/// * 「首页」系统整体移除，无任何页面时显示一行空状态提示；
/// * 导航由 [FSidebar] 承担：一级为分类，展开后是具体工具；
/// * 没有可见的标签条，切换只改显隐，页面 State 一律保活；
/// * 主题/设置/收起三个按钮都在侧栏底部。

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
  Widget buildContent(BuildContext context) =>
      Center(child: Text('内容区:$_name'));
}

/// 带自增计数的假工具：验证切页后 State 是否保活。
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
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => setState(() => _count++),
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
  // 注意：flutter test 默认模拟 android 平台，而 _TestTool 仅支持 windows
  // （availableTools 按平台过滤）。故每个测试体内固定平台为 windows。
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('shell_view_test');
    // 启动告警是全局状态，逐用例清掉，避免互相影响。
    StartupNotice.clear();
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Widget buildApp() => ProviderScope(
    overrides: [
      toolboxRegistryProvider.overrideWith((ref) => _TestRegistry()),
      settingsStoreProvider.overrideWithValue(SettingsStore(dir: tempDir.path)),
    ],
    child: FTheme(
      data: AppTheme.light,
      child: MaterialApp(home: const ShellView()),
    ),
  );

  testWidgets('侧栏展示分类与其下工具；未打开页面时显示空状态提示', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(buildApp());

    // 三个分类各出现一次（有工具的分类才显示）
    expect(find.text('工作'), findsOneWidget);
    expect(find.text('数据库管理'), findsOneWidget);
    expect(find.text('其他工具'), findsOneWidget);
    // 分类默认展开，工具直接可见
    expect(find.text('工具一'), findsOneWidget);
    expect(find.text('工具二'), findsOneWidget);
    expect(find.text('计数器'), findsOneWidget);

    // 1.5.0 已无「首页」入口，也没有任何标签条
    expect(find.text('首页'), findsNothing);
    // 空状态交给内容区一行提示
    expect(find.text('从左侧选择工具开始'), findsOneWidget);
    // 底部显示版本号
    expect(find.text('v$appVersion'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('无工具时不显示任何分类项', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(
            SettingsStore(dir: tempDir.path),
          ),
        ],
        child: FTheme(
          data: AppTheme.light,
          child: MaterialApp(home: const ShellView()),
        ),
      ),
    );
    expect(find.text('数据库管理'), findsNothing);
    expect(find.text('从左侧选择工具开始'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('点击侧栏工具项打开对应页面', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(buildApp());

    await tester.tap(find.text('工具一'));
    await tester.pumpAndSettle();

    expect(find.text('内容区:工具一').hitTestable(), findsOneWidget);
    expect(find.text('从左侧选择工具开始'), findsNothing);

    // 再打开第二个工具：两个页面同时存在，只有当前页可命中
    await tester.tap(find.text('工具二'));
    await tester.pumpAndSettle();
    expect(find.text('内容区:工具二').hitTestable(), findsOneWidget);
    expect(find.text('内容区:工具一').hitTestable(), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('切换工具后页面 State 保活（计数不丢失）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(buildApp());

    await tester.tap(find.text('计数器'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加一'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加一'));
    await tester.pumpAndSettle();
    expect(find.text('计数:2'), findsOneWidget);

    // 切到另一个工具再切回来
    await tester.tap(find.text('工具一'));
    await tester.pumpAndSettle();
    expect(find.text('计数:2').hitTestable(), findsNothing);

    await tester.tap(find.text('计数器'));
    await tester.pumpAndSettle();
    expect(find.text('计数:2'), findsOneWidget);
    expect(find.text('计数:0'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('主题按钮循环切换 跟随系统 → 浅色 → 深色', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(buildApp());

    expect(find.byIcon(FLucideIcons.sunMoon), findsOneWidget);
    await tester.tap(find.byIcon(FLucideIcons.sunMoon));
    await tester.pumpAndSettle();
    expect(find.byIcon(FLucideIcons.sun), findsOneWidget);

    await tester.tap(find.byIcon(FLucideIcons.sun));
    await tester.pumpAndSettle();
    expect(find.byIcon(FLucideIcons.moon), findsOneWidget);

    await tester.tap(find.byIcon(FLucideIcons.moon));
    await tester.pumpAndSettle();
    expect(find.byIcon(FLucideIcons.sunMoon), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('收起侧栏后只剩图标，且可再展开', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(buildApp());

    expect(find.byIcon(FLucideIcons.panelLeftClose), findsOneWidget);
    await tester.tap(find.byIcon(FLucideIcons.panelLeftClose));
    await tester.pumpAndSettle();

    // 收缩态：分类与工具的文字全部隐藏，展开按钮出现
    expect(find.text('工作'), findsNothing);
    expect(find.text('工具一'), findsNothing);
    expect(find.byIcon(FLucideIcons.panelLeftOpen), findsOneWidget);

    await tester.tap(find.byIcon(FLucideIcons.panelLeftOpen));
    await tester.pumpAndSettle();
    expect(find.text('工具一'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('设置弹窗：名称+控件两列，长说明走悬停提示', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(buildApp());

    await tester.tap(find.byIcon(FLucideIcons.settings));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
    // 1.5.0 改版：不再展示数据目录与版本号，也没有底部「关闭」按钮
    expect(find.text('数据目录'), findsNothing);
    expect(find.text('关闭'), findsNothing);
    // 更新由安装包负责，设置里不再有「检查更新」入口
    expect(find.text('检查更新'), findsNothing);
    expect(find.text('更新'), findsNothing);
    // 常规设置项
    expect(find.text('关闭窗口时'), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    // 数据备份两项
    expect(find.text('数据备份'), findsOneWidget);
    expect(find.text('导出备份'), findsOneWidget);
    expect(find.text('导入备份'), findsOneWidget);
    expect(find.text('导出到 zip…'), findsOneWidget);
    expect(find.text('从 zip 恢复…'), findsOneWidget);
    expect(find.text('格式化数据'), findsOneWidget);
    expect(find.text('清空全部数据…'), findsOneWidget);
    // 快捷键区
    expect(find.text('快捷键'), findsOneWidget);
    expect(find.text('Ctrl + W'), findsOneWidget);
    // 右上角的 × 是唯一退出入口
    expect(byTip('关闭'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('侧栏可拖拽改宽并持久化到 settings.json', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(buildApp());

    final before = tester.getSize(find.byType(FSidebar)).width;
    expect(before, 256, reason: '首次启动用 ForUI 默认宽度');

    // 拖拽条贴在侧栏右缘（6px 宽），从它上面往右拖 60px
    await tester.dragFrom(Offset(before + 3, 300), const Offset(60, 0));
    await tester.pumpAndSettle();

    final after = tester.getSize(find.byType(FSidebar)).width;
    expect(after, greaterThan(before + 30), reason: '拖拽应让侧栏变宽');

    // 防抖 400ms 后落盘
    await tester.pump(const Duration(milliseconds: 600));
    final saved = SettingsStore(dir: tempDir.path).read()['ui.sidebarWidth'];
    expect(saved, isA<num>());
    expect((saved! as num).toDouble(), closeTo(after, 1.0));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('页面导航状态：open 后激活，重复 open 不重复入栈', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final nav = container.read(pageNavProvider.notifier);

    expect(container.read(pageNavProvider).activeId, isNull);
    nav.open('t1');
    nav.open('t2');
    nav.open('t1');
    final state = container.read(pageNavProvider);
    expect(state.openIds, ['t1', 't2']);
    expect(state.activeId, 't1');
    nav.close('t1');
    expect(container.read(pageNavProvider).openIds, ['t2']);
  });
}
