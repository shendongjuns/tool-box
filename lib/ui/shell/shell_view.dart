import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:toolbox/common/app_meta.dart';
import 'package:toolbox/common/single_instance.dart';
import 'package:toolbox/registry/tool_category.dart';
import 'package:toolbox/registry/toolbox_registry.dart';
import 'package:toolbox/ui/shell/navigation_controller.dart';
import 'package:toolbox/ui/shell/settings_dialog.dart';
import 'package:toolbox/ui/theme/app_layout.dart';
import 'package:toolbox/ui/theme/theme_controller.dart';
import 'package:toolbox/ui/widgets/app_dialog.dart';
import 'package:toolbox/ui/widgets/app_resize_handle.dart';

/// 壳层：左侧导航 + 内容区。
///
/// 无顶栏、无页签栏 —— 导航完全由 [FSidebar] 承担，页面切换靠
/// [ToolPagesHost] 的 IndexedStack 保活（切走的页面 State 不销毁）。
///
/// 首帧后会把启动期收集到的问题（数据目录回退、多实例）弹一次告知用户
/// —— 这类问题如果不提示，用户只会看到「保存了却不见」。
class ShellView extends ConsumerStatefulWidget {
  const ShellView({super.key});

  @override
  ConsumerState<ShellView> createState() => _ShellViewState();
}

class _ShellViewState extends ConsumerState<ShellView> {
  @override
  void initState() {
    super.initState();
    if (StartupNotice.hasAny) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showNotices());
    }
  }

  Future<void> _showNotices() async {
    if (!mounted) return;
    final messages = StartupNotice.messages;
    StartupNotice.clear();
    await showAppDialog<void>(
      context: context,
      title: '启动提示',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final message in messages) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(FLucideIcons.info, size: 16),
                const SizedBox(width: AppLayout.gapSm),
                Expanded(child: Text(message)),
              ],
            ),
            if (message != messages.last) const SizedBox(height: AppLayout.gapMd),
          ],
        ],
      ),
      actions: [
        FButton(
          mainAxisSize: MainAxisSize.min,
          variant: FButtonVariant.primary,
          onPress: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) =>
      const FScaffold(sidebar: ToolSidebar(), childPad: false, child: ToolPagesHost());
}

/// 左侧导航：首页 + 有工具的分类（展开后是具体工具）。
///
/// 支持收缩：收缩后只保留图标（分类摊平成工具图标列表）；
/// 顶部是展开/收起按钮，底部是「设置 / 主题切换」+ 右侧应用版本号。
class ToolSidebar extends ConsumerStatefulWidget {
  const ToolSidebar({super.key});

  @override
  ConsumerState<ToolSidebar> createState() => _ToolSidebarState();
}

class _ToolSidebarState extends ConsumerState<ToolSidebar> {
  /// 展开态宽度在 `settings.json` 里的键。
  static const String _widthKey = 'ui.sidebarWidth';

  /// 收缩态固定宽度。
  static const double collapsedWidth = 64;

  /// 展开态可拖拽区间。
  static const double minWidth = 180;
  static const double maxWidth = 420;

  /// ForUI 侧栏默认宽度，作为首次启动值。
  static const double defaultWidth = 256;

  double _width = defaultWidth;
  bool _collapsed = false;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _width = _clampWidth(
      (ref.read(settingsStoreProvider).read()[_widthKey] as num?)?.toDouble() ??
          defaultWidth,
    );
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  static double _clampWidth(double value) =>
      value.clamp(minWidth, maxWidth).toDouble();

  /// 拖拽结束后防抖写盘（拖拽过程每帧都会触发，不能每帧写盘）。
  void _persist() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () {
      final store = ref.read(settingsStoreProvider);
      store.write({...store.read(), _widthKey: _width});
    });
  }

  void _onDrag(double dx) {
    setState(() => _width = _clampWidth(_width + dx));
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final nav = ref.watch(pageNavProvider);
    final notifier = ref.read(pageNavProvider.notifier);
    final tools = ref.watch(toolboxRegistryProvider).availableTools();

    void toggle() => setState(() => _collapsed = !_collapsed);

    if (_collapsed) {
      return FSidebar(
        style: FSidebarStyleDelta.delta(
          constraints: const BoxConstraints.tightFor(width: collapsedWidth),
        ),
        footer: _SidebarFooter(collapsed: true, onToggleCollapsed: toggle),
        children: [
          for (final tool in tools)
            FSidebarItem(
              // 收缩态没有 label：FSidebarItem 内部会把 icon 放进一个
              // `Expanded(child: Row(mainAxisAlignment: start))`，图标因此贴左，
              // 与底部按钮（设置/主题/收起）不在同一列。
              // 这里再包一层 Expanded + Center，让图标落在侧栏中轴线上。
              icon: Expanded(child: Center(child: Icon(toolIcon(tool.id)))),
              selected: nav.activeId == tool.id,
              onPress: () => notifier.open(tool.id),
            ),
        ],
      );
    }

    final categories = [
      for (final c in ToolCategory.values)
        if (tools.any((t) => t.category == c)) c,
    ];

    // 展开态：右侧挂一条 6px 拖拽条改宽度，宽度持久化到 settings.json。
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FSidebar(
          style: FSidebarStyleDelta.delta(
            constraints: BoxConstraints.tightFor(width: _width),
          ),
          footer: _SidebarFooter(collapsed: false, onToggleCollapsed: toggle),
          children: [
            for (final category in categories)
              FSidebarItem(
                icon: Icon(categoryIcon(category)),
                label: Text(category.displayName),
                initiallyExpanded: true,
                children: [
                  for (final tool in tools.where((t) => t.category == category))
                    FSidebarItem(
                      icon: Icon(toolIcon(tool.id)),
                      label: Text(tool.name),
                      selected: nav.activeId == tool.id,
                      onPress: () => notifier.open(tool.id),
                    ),
                ],
              ),
          ],
        ),
        AppResizeHandle(onDrag: _onDrag, onDragEnd: _persist),
      ],
    );
  }
}

/// 侧栏底部：设置 / 主题切换 / 收起按钮与版本号。
class _SidebarFooter extends ConsumerWidget {
  const _SidebarFooter({
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  final bool collapsed;

  /// 收起 / 展开左侧导航。
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeControllerProvider);
    final (icon, label) = switch (mode) {
      ThemeMode.system => (FLucideIcons.sunMoon, '主题：跟随系统'),
      ThemeMode.light => (FLucideIcons.sun, '主题：浅色'),
      ThemeMode.dark => (FLucideIcons.moon, '主题：深色'),
    };

    final settings = FButton(
      mainAxisSize: MainAxisSize.min,
      variant: FButtonVariant.ghost,
      size: FButtonSizeVariant.sm,
      semanticsTooltip: '设置',
      onPress: () => showSettingsDialog(context),
      child: const Icon(FLucideIcons.settings),
    );
    final themeToggle = FButton(
      mainAxisSize: MainAxisSize.min,
      variant: FButtonVariant.ghost,
      size: FButtonSizeVariant.sm,
      semanticsTooltip: label,
      onPress: () => ref.read(themeControllerProvider.notifier).cycle(),
      child: Icon(icon),
    );
    final collapseToggle = FButton(
      mainAxisSize: MainAxisSize.min,
      variant: FButtonVariant.ghost,
      size: FButtonSizeVariant.sm,
      semanticsTooltip: collapsed ? '展开导航' : '收起导航',
      onPress: onToggleCollapsed,
      child: Icon(
        collapsed ? FLucideIcons.panelLeftOpen : FLucideIcons.panelLeftClose,
      ),
    );

    // 收缩态：竖排（64px 不够横排），此时不显示版本号。
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppLayout.gapSm),
        child: Column(
          children: [
            settings,
            const SizedBox(height: AppLayout.gapXs),
            themeToggle,
            const SizedBox(height: AppLayout.gapXs),
            collapseToggle,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppLayout.gapSm),
      child: Row(
        children: [
          settings,
          const SizedBox(width: AppLayout.gapXs),
          themeToggle,
          const Spacer(),
          Text(
            'v$appVersion',
            style: context.theme.typography.body.xs.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
          const SizedBox(width: AppLayout.gapSm),
          collapseToggle,
        ],
      ),
    );
  }
}

/// 页面会话宿主：用 IndexedStack 承载已打开的页面。
///
/// 切换只改显隐、不换页面，因此各页面 State 全部保活
/// （终端、表单、滚动位置都不会因为切走再切回而丢失）。
class ToolPagesHost extends ConsumerStatefulWidget {
  const ToolPagesHost({super.key});

  @override
  ConsumerState<ToolPagesHost> createState() => _ToolPagesHostState();
}

class _ToolPagesHostState extends ConsumerState<ToolPagesHost> {
  /// 已打开页面的 widget 缓存：id -> 页面（首次打开时生成）。
  final Map<String, Widget> _pages = {};

  @override
  Widget build(BuildContext context) {
    final nav = ref.watch(pageNavProvider);
    final openIds = nav.openIds;

    // 为新增页面生成缓存。
    for (final id in openIds) {
      if (_pages.containsKey(id)) continue;
      for (final tool in ref.read(toolboxRegistryProvider).availableTools()) {
        if (tool.id == id) {
          _pages[id] = tool.buildContent(context);
          break;
        }
      }
    }

    final children = <Widget>[
      for (final id in openIds)
        if (_pages.containsKey(id)) _pages[id]!,
    ];

    // 已无首页系统：没有任何已打开页面时给一个极轻的空状态提示，
    // 避免「程序像没加载出来」。不是首页，只是一行灰字。
    if (children.isEmpty) {
      return Center(
        child: Text(
          '从左侧选择工具开始',
          style: context.theme.typography.body.sm.copyWith(
            color: context.theme.colors.mutedForeground.withValues(alpha: .8),
          ),
        ),
      );
    }

    final index = openIds
        .indexOf(nav.activeId ?? '')
        .clamp(0, children.length - 1);

    return IndexedStack(index: index, children: children);
  }
}

/// 分类图标。
IconData categoryIcon(ToolCategory category) => switch (category) {
  ToolCategory.work => FLucideIcons.briefcase,
  ToolCategory.data => FLucideIcons.braces,
  ToolCategory.database => FLucideIcons.database,
  ToolCategory.text => FLucideIcons.type,
  ToolCategory.encode => FLucideIcons.code,
  ToolCategory.system => FLucideIcons.slidersHorizontal,
  ToolCategory.other => FLucideIcons.shapes,
};

/// 工具图标。
IconData toolIcon(String id) => switch (id) {
  'repository' => FLucideIcons.network,
  'remote' => FLucideIcons.server,
  _ => FLucideIcons.puzzle,
};
