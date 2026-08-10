import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/registry/tool.dart';
import 'package:toolbox/registry/toolbox_registry.dart';
import 'package:toolbox/ui/theme/appflowy_colors.dart';
import 'navigation_controller.dart';

/// 顶部导航栏（VSCode 菜单栏风格）：logo + 「首页」「设置」文字菜单项。
/// 点击菜单项展开下拉面板（自绘 Overlay：圆角/阴影/hover 高亮），
/// 选择工具进入对应功能页面。
class TopNavBar extends ConsumerStatefulWidget {
  const TopNavBar({super.key});

  @override
  ConsumerState<TopNavBar> createState() => _TopNavBarState();
}

class _TopNavBarState extends ConsumerState<TopNavBar> {
  /// 设置菜单锚点（定位下拉面板）。
  final GlobalKey _settingsKey = GlobalKey();
  OverlayEntry? _menuEntry;

  @override
  void dispose() {
    _closeMenu();
    super.dispose();
  }

  void _closeMenu() {
    _menuEntry?.remove();
    _menuEntry = null;
  }

  void _toggleMenu() {
    if (_menuEntry != null) {
      _closeMenu();
      return;
    }
    final box = _settingsKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero, ancestor: overlay);
    final registry = ref.read(toolboxRegistryProvider);
    final tools = registry.availableTools();

    _menuEntry = OverlayEntry(
      builder: (_) => _SettingsMenu(
        anchorOffset: offset,
        anchorSize: box.size,
        tools: tools,
        onSelect: (tool) {
          _closeMenu();
          ref.read(selectedToolProvider.notifier).select(tool);
        },
        onDismiss: _closeMenu,
      ),
    );
    Overlay.of(context).insert(_menuEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedToolProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      height: 48,
      color: scheme.surface,
      child: Row(
        children: [
          const SizedBox(width: AppflowySpacing.m),
          // 首页菜单项
          _MenuBarItem(
            label: '首页',
            active: selected == null,
            onTap: () {
              _closeMenu();
              ref.read(selectedToolProvider.notifier).goHome();
            },
          ),
          // 设置菜单项（点击展开下拉）
          _MenuBarItem(
            key: _settingsKey,
            label: '设置',
            active: _menuEntry != null,
            onTap: _toggleMenu,
          ),
          const Spacer(),
          // 当前页面名（仅选中工具时显示）
          if (selected != null)
            Padding(
              padding: const EdgeInsets.only(right: AppflowySpacing.xl),
              child: Text(
                selected.name,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 顶部菜单栏项（VSCode 风格）：文字，hover 提亮，active 时主色。
class _MenuBarItem extends StatefulWidget {
  const _MenuBarItem({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_MenuBarItem> createState() => _MenuBarItemState();
}

class _MenuBarItemState extends State<_MenuBarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final palette = Theme.of(context).brightness == Brightness.dark
        ? AppflowyColors.dark
        : AppflowyColors.light;
    final bg = widget.active || _hovered ? palette.layer01 : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(AppflowyRadius.m),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(AppflowyRadius.m),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppflowySpacing.m,
                vertical: AppflowySpacing.s,
              ),
              child: Text(
                widget.label,
                style: textTheme.bodyMedium?.copyWith(
                  color: widget.active ? scheme.primary : scheme.onSurface,
                  fontWeight:
                      widget.active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 设置下拉面板（Overlay）：VSCode 菜单风格 —— 圆角面板 + 阴影 + 边框，
/// 菜单项 hover 高亮，工具按分类分隔。
class _SettingsMenu extends StatelessWidget {
  const _SettingsMenu({
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
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // 全屏透明屏障：点击外部关闭
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        // 下拉面板（定宽：Positioned 仅 left/top 会给子组件无限宽约束）
        Positioned(
          left: anchorOffset.dx,
          top: anchorOffset.dy + anchorSize.height + 4,
          width: 200,
          child: Material(
            color: scheme.surface,
            elevation: 8,
            shadowColor: Colors.black26,
            borderRadius: BorderRadius.circular(AppflowyRadius.m),
            child: Container(
              constraints: const BoxConstraints(minWidth: 180),
              padding: const EdgeInsets.symmetric(
                vertical: AppflowySpacing.s,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(AppflowyRadius.m),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 直接平铺工具项（纯文字，不显示分类名与图标）
                  for (final tool in tools)
                    _MenuItem(
                      label: tool.name,
                      onTap: () => onSelect(tool),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 菜单项：文字，hover 高亮。
class _MenuItem extends StatefulWidget {
  const _MenuItem({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = Theme.of(context).brightness == Brightness.dark
        ? AppflowyColors.dark
        : AppflowyColors.light;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppflowySpacing.s),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: _hovered ? palette.layer01 : Colors.transparent,
          borderRadius: BorderRadius.circular(AppflowyRadius.s),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(AppflowyRadius.s),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppflowySpacing.m,
                vertical: AppflowySpacing.s,
              ),
              child: Text(widget.label, style: textTheme.bodyMedium),
            ),
          ),
        ),
      ),
    );
  }
}

