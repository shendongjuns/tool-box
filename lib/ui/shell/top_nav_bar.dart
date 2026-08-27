import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/registry/tool.dart';
import 'package:toolbox/registry/tool_category.dart';
import 'package:toolbox/registry/toolbox_registry.dart';
import 'package:toolbox/ui/theme/app_icons.dart';
import 'package:toolbox/ui/theme/mochi_cat_tokens.dart';
import 'package:toolbox/ui/theme/theme_controller.dart';
import 'navigation_controller.dart';

/// 顶部导航栏（52px）：「品牌区」+「首页 / 分类菜单」+「已打开工具标签」+
/// 主题按钮。点击分类菜单展开下拉面板，选择工具进入对应页面。
class TopNavBar extends ConsumerStatefulWidget {
  const TopNavBar({super.key});

  @override
  ConsumerState<TopNavBar> createState() => _TopNavBarState();
}

class _TopNavBarState extends ConsumerState<TopNavBar> {
  /// 每个分类菜单的锚点（定位下拉面板）。
  final Map<ToolCategory, GlobalKey> _anchors = {
    for (final c in ToolCategory.values) c: GlobalKey(),
  };
  ToolCategory? _openCategory;
  OverlayEntry? _menuEntry;

  @override
  void dispose() {
    _closeMenu();
    super.dispose();
  }

  void _closeMenu() {
    _menuEntry?.remove();
    _menuEntry = null;
    _openCategory = null;
  }

  void _toggleMenu(ToolCategory category) {
    if (_openCategory == category) {
      _closeMenu();
      return;
    }
    _closeMenu();
    final anchor = _anchors[category]!;
    final box = anchor.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero, ancestor: overlay);
    final registry = ref.read(toolboxRegistryProvider);
    final tools = registry
        .availableTools()
        .where((t) => t.category == category)
        .toList();

    _openCategory = category;
    _menuEntry = OverlayEntry(
      builder: (_) => _CategoryMenu(
        anchorOffset: offset,
        anchorSize: box.size,
        tools: tools,
        onSelect: (tool) {
          _closeMenu();
          ref.read(pageNavProvider.notifier).open(tool.id);
        },
        onDismiss: _closeMenu,
      ),
    );
    Overlay.of(context).insert(_menuEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final nav = ref.watch(pageNavProvider);
    final registry = ref.watch(toolboxRegistryProvider);
    final tools = registry.availableTools();
    final p = MochiCatPalette.of(context);

    // 有工具的分类（保持枚举声明顺序）。
    final categories = [
      for (final c in ToolCategory.values)
        if (tools.any((t) => t.category == c)) c,
    ];

    return Container(
      height: MochiCatSize.topBarHeight,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: MochiCatSpacing.lg),
          // 首页菜单项
          _NavItem(
            label: '首页',
            icon: AppIcons.home,
            active: nav.isHome,
            onTap: () {
              _closeMenu();
              ref.read(pageNavProvider.notifier).goHome();
            },
          ),
          // 每个分类一个菜单项（无工具的分类不显示）
          for (final category in categories)
            _NavItem(
              key: _anchors[category],
              label: category.displayName,
              icon: _categoryIcon(category),
              showChevron: true,
              active: _openCategory == category,
              onTap: () => _toggleMenu(category),
            ),
          if (nav.openIds.isNotEmpty) ...[
            const SizedBox(width: MochiCatSpacing.sm),
            Expanded(
              child: _OpenToolTabs(
                openIds: nav.openIds,
                activeId: nav.activeId,
                onActivate: (id) =>
                    ref.read(pageNavProvider.notifier).activate(id),
                onClose: (id) => ref.read(pageNavProvider.notifier).close(id),
              ),
            ),
          ] else
            const Spacer(),
          // 主题循环切换按钮（跟随系统 → 浅色 → 深色）
          const _ThemeToggleButton(),
          const SizedBox(width: MochiCatSpacing.sm),
        ],
      ),
    );
  }
}

/// 内嵌在顶部导航栏的页面标签，避免额外占用一行高度。
class _OpenToolTabs extends ConsumerWidget {
  const _OpenToolTabs({
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
    final registry = ref.watch(toolboxRegistryProvider);
    final tools = registry.availableTools();
    String nameOf(String id) {
      for (final tool in tools) {
        if (tool.id == id) return tool.name;
      }
      return id;
    }

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: MochiCatSpacing.sm),
      itemCount: openIds.length,
      separatorBuilder: (_, _) => const SizedBox(width: MochiCatSpacing.xs),
      itemBuilder: (_, index) {
        final id = openIds[index];
        return _InlineToolTab(
          label: nameOf(id),
          active: activeId == id,
          onTap: () => onActivate(id),
          onClose: () => onClose(id),
        );
      },
    );
  }
}

IconData _categoryIcon(ToolCategory category) => switch (category) {
      ToolCategory.work => AppIcons.work,
      ToolCategory.data => AppIcons.data,
      ToolCategory.database => AppIcons.database,
      ToolCategory.text => AppIcons.text,
      ToolCategory.encode => AppIcons.encode,
      ToolCategory.system => AppIcons.system,
      ToolCategory.other => AppIcons.other,
    };

class _InlineToolTab extends StatefulWidget {
  const _InlineToolTab({
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
  State<_InlineToolTab> createState() => _InlineToolTabState();
}

class _InlineToolTabState extends State<_InlineToolTab> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);
    final background =
        widget.active
            ? p.primarySoft
            : (_hovered ? p.background : Colors.transparent);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(MochiCatRadius.sm),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(MochiCatRadius.sm),
          child: Container(
            height: 30,
            padding: const EdgeInsets.only(left: MochiCatSpacing.md),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                Icons.circle,
                size: 6,
                color: widget.active
                    ? p.primary
                    : p.textSecondary.withValues(alpha: .6),
              ),
              const SizedBox(width: MochiCatSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.active
                        ? p.primary
                        : p.textSecondary,
                    fontWeight:
                        widget.active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              InkWell(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(MochiCatRadius.xs),
                child: Padding(
                  padding: const EdgeInsets.all(MochiCatSpacing.xs + 2),
                  child: Icon(
                    AppIcons.close,
                    size: 13,
                    color: p.textSecondary.withValues(alpha: .75),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 主题循环切换按钮（跟随系统 → 浅色 → 深色）。
class _ThemeToggleButton extends ConsumerWidget {
  const _ThemeToggleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeControllerProvider);
    final (icon, tooltip) = switch (themeMode) {
      ThemeMode.system => (AppIcons.themeIcon(ThemeMode.system), '主题：跟随系统'),
      ThemeMode.light => (AppIcons.themeIcon(ThemeMode.light), '主题：浅色'),
      ThemeMode.dark => (AppIcons.themeIcon(ThemeMode.dark), '主题：深色'),
    };
    final p = MochiCatPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: MochiCatSpacing.xs),
      child: IconButton(
        constraints: const BoxConstraints.tightFor(
          width: MochiCatSize.iconButton,
          height: MochiCatSize.iconButton,
        ),
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 18),
        tooltip: tooltip,
        color: p.textSecondary,
        onPressed: () => ref.read(themeControllerProvider.notifier).cycle(),
      ),
    );
  }
}

/// 悬停高亮的可点击容器：统一「菜单栏项」与「下拉菜单项」的 hover/涟漪交互。
class _HoverInkWell extends StatefulWidget {
  const _HoverInkWell({
    required this.borderRadius,
    required this.onTap,
    required this.child,
    this.highlighted = false,
  });

  final double borderRadius;
  final VoidCallback onTap;
  final Widget child;

  /// 强制高亮（如菜单栏项 active 态），即使未 hover 也显示背景。
  final bool highlighted;

  @override
  State<_HoverInkWell> createState() => _HoverInkWellState();
}

class _HoverInkWellState extends State<_HoverInkWell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);
    final bg = (widget.highlighted || _hovered)
        ? p.primarySoft
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: widget.child,
        ),
      ),
    );
  }
}

/// 顶部菜单栏项：图标+文字，hover 淡紫背景，active 时主色。
class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.showChevron = false,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: _HoverInkWell(
        borderRadius: MochiCatRadius.sm,
        highlighted: active,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MochiCatSpacing.md,
            vertical: MochiCatSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: active ? p.primary : p.textSecondary,
              ),
              const SizedBox(width: MochiCatSpacing.sm),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: active ? p.primary : p.textPrimary,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (showChevron) ...[
                const SizedBox(width: 2),
                Icon(
                  AppIcons.chevronDown,
                  size: 15,
                  color: p.textSecondary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 分类下拉面板（Overlay）：圆角面板 + 阴影 + 边框，菜单项 hover 高亮。
class _CategoryMenu extends StatelessWidget {
  const _CategoryMenu({
    required this.anchorOffset,
    required this.anchorSize,
    required this.tools,
    required this.onSelect,
    required this.onDismiss,
  });

  final Offset anchorOffset;
  final Size anchorSize;
  final List<Tool> tools;
  final ValueChanged<Tool> onSelect;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);

    return Stack(
      children: [
        // 全屏透明屏障：点击外部关闭
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        // 下拉面板
        Positioned(
          left: anchorOffset.dx,
          top: anchorOffset.dy + anchorSize.height + 4,
          width: 210,
          child: Material(
            color: p.surface,
            elevation: 8,
            shadowColor: Colors.black26,
            borderRadius: BorderRadius.circular(MochiCatRadius.md),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: MochiCatSpacing.sm),
              decoration: BoxDecoration(
                border: Border.all(color: p.border),
                borderRadius: BorderRadius.circular(MochiCatRadius.md),
                boxShadow: const [MochiCatShadow.hover],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      MochiCatSpacing.lg,
                      MochiCatSpacing.sm,
                      MochiCatSpacing.lg,
                      MochiCatSpacing.xs,
                    ),
                    child: Text(
                      '${toolsTitle(tools)}工具',
                      style: TextStyle(
                        fontSize: 11,
                        color: p.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final tool in tools)
                    _MenuItem(tool: tool, onTap: () => onSelect(tool)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String toolsTitle(List<Tool> tools) =>
    tools.isEmpty ? '' : tools.first.category.displayName;

/// 菜单项：图标 + 文字，hover 高亮。
class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.tool, required this.onTap});

  final Tool tool;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MochiCatSpacing.sm),
      child: _HoverInkWell(
        borderRadius: MochiCatRadius.sm,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MochiCatSpacing.lg,
            vertical: MochiCatSpacing.sm + 2,
          ),
          child: Row(
            children: [
              Icon(_toolIcon(tool.id), size: 17, color: p.primary),
              const SizedBox(width: MochiCatSpacing.md),
              Expanded(
                child: Text(
                  tool.name,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _toolIcon(String id) => switch (id) {
      'repository' => AppIcons.repository,
      'remote' => AppIcons.remote,
      _ => AppIcons.fallback,
    };
