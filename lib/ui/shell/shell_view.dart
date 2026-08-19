import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/registry/tool.dart';
import 'package:toolbox/registry/toolbox_registry.dart';
import 'package:toolbox/ui/shell/navigation_controller.dart';
import 'package:toolbox/ui/theme/appflowy_colors.dart';
import 'top_nav_bar.dart';

/// 壳层布局：顶部菜单导航栏 + 内容区（含页面标签条）。
class ShellView extends ConsumerWidget {
  const ShellView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          const TopNavBar(),
          Expanded(
            child: Container(
              color: Theme.of(context).colorScheme.surface,
              child: const ToolPagesHost(),
            ),
          ),
        ],
      ),
    );
  }
}

/// 页面会话宿主：缓存已打开的工具页面（State 保活），
/// 用 IndexedStack 承载「首页 + 已打开页面」，切换只改显隐。
class ToolPagesHost extends ConsumerStatefulWidget {
  const ToolPagesHost({super.key});

  @override
  ConsumerState<ToolPagesHost> createState() => _ToolPagesHostState();
}

class _ToolPagesHostState extends ConsumerState<ToolPagesHost> {
  /// 已打开页面的 widget 缓存：id -> 页面（首次打开生成，关闭时移除）。
  final Map<String, Widget> _pages = {};

  Tool? _toolById(String id) {
    final registry = ref.read(toolboxRegistryProvider);
    for (final tool in registry.availableTools()) {
      if (tool.id == id) return tool;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final nav = ref.watch(pageNavProvider);

    // 为新增页面生成缓存；已关闭的页面从缓存移除。
    final openIds = nav.openIds;
    _pages.removeWhere((id, _) => !openIds.contains(id));
    for (final id in openIds) {
      if (!_pages.containsKey(id)) {
        final tool = _toolById(id);
        if (tool != null) _pages[id] = tool.buildContent(context);
      }
    }

    final children = <Widget>[
      const HomePage(),
      for (final id in openIds)
        if (_pages.containsKey(id)) _pages[id]!,
    ];
    final activeIndex = nav.isHome ? 0 : openIds.indexOf(nav.activeId!) + 1;

    return Column(
      children: [
        if (openIds.isNotEmpty)
          _PageTabBar(
            openIds: openIds,
            activeId: nav.activeId,
            onActivate: (id) =>
                ref.read(pageNavProvider.notifier).activate(id),
            onClose: (id) => ref.read(pageNavProvider.notifier).close(id),
          ),
        Expanded(
          child: IndexedStack(
            index: activeIndex,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// 页面标签条：每个已打开页面一个标签（工具名 + 关闭按钮），
/// 点击切换、点 × 关闭、当前页高亮。
class _PageTabBar extends ConsumerWidget {
  const _PageTabBar({
    required this.openIds,
    required this.activeId,
    required this.onActivate,
    required this.onClose,
  });

  final List<String> openIds;
  final String? activeId;
  final ValueChanged<String> onActivate;
  final ValueChanged<String> onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final registry = ref.watch(toolboxRegistryProvider);

    String toolName(String id) {
      for (final tool in registry.availableTools()) {
        if (tool.id == id) return tool.name;
      }
      return id;
    }

    return Container(
      height: 36,
      color: scheme.surface,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          AppflowySpacing.m,
          AppflowySpacing.xs,
          AppflowySpacing.m,
          AppflowySpacing.xs,
        ),
        itemCount: openIds.length,
        itemBuilder: (_, i) {
          final id = openIds[i];
          final active = id == activeId;
          return Padding(
            padding: const EdgeInsets.only(right: AppflowySpacing.s),
            child: _PageTab(
              label: toolName(id),
              active: active,
              onTap: () => onActivate(id),
              onClose: () => onClose(id),
            ),
          );
        },
      ),
    );
  }
}

/// 单个页面标签：圆角胶囊，当前页主色高亮，hover 提亮，带关闭按钮。
class _PageTab extends StatefulWidget {
  const _PageTab({
    required this.label,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  State<_PageTab> createState() => _PageTabState();
}

class _PageTabState extends State<_PageTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final palette = Theme.of(context).brightness == Brightness.dark
        ? AppflowyColors.dark
        : AppflowyColors.light;
    final bg = widget.active
        ? scheme.primary.withValues(alpha: 0.12)
        : (_hovered ? palette.layer01 : Colors.transparent);
    final fg = widget.active ? scheme.primary : scheme.onSurface;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppflowyRadius.s),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppflowyRadius.s),
          child: Padding(
            padding: const EdgeInsets.only(left: AppflowySpacing.m),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: textTheme.bodyMedium?.copyWith(
                    color: fg,
                    fontWeight:
                        widget.active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                const SizedBox(width: AppflowySpacing.xs),
                InkWell(
                  onTap: widget.onClose,
                  borderRadius: BorderRadius.circular(AppflowyRadius.xs),
                  child: Padding(
                    padding: const EdgeInsets.all(AppflowySpacing.xs),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 首页占位：内容待定（暂空）。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '内容待定',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
