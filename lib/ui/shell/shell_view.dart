import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/registry/tool.dart';
import 'package:toolbox/registry/toolbox_registry.dart';
import 'package:toolbox/ui/shell/navigation_controller.dart';
import 'package:toolbox/ui/theme/app_icons.dart';
import 'package:toolbox/ui/theme/mochi_cat_tokens.dart';
import 'package:toolbox/ui/widgets/mochi_widgets.dart';
import 'top_nav_bar.dart';

/// 壳层布局：顶部导航栏 + 内容区。
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
              color: MochiCatPalette.of(context).background,
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

    return IndexedStack(
      index: activeIndex,
      children: children,
    );
  }
}

/// 首页：糯米猫主题欢迎页，展示当前可用工具的快捷入口。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tools = ref.watch(toolboxRegistryProvider).availableTools();
    final p = MochiCatPalette.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;
        final contentWidth = constraints.maxWidth > 980
            ? 980.0
            : constraints.maxWidth;
        final cardWidth = compact
            ? contentWidth - MochiCatSpacing.xl * 2
            : (contentWidth - MochiCatSpacing.xl * 3) / 2;
        return SingleChildScrollView(
          padding: EdgeInsets.all(compact ? MochiCatSpacing.xl : 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HomeHero(
                    compact: compact,
                    onStart: tools.isEmpty
                        ? null
                        : () => ref
                            .read(pageNavProvider.notifier)
                            .open(tools.first.id),
                  ),
                  const SizedBox(height: MochiCatSpacing.xxl),
                  Row(
                    children: [
                      const Text(
                        '常用工具',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: MochiCatSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: MochiCatSpacing.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: p.primarySoft,
                          borderRadius: BorderRadius.circular(MochiCatRadius.sm),
                        ),
                        child: Text(
                          '${tools.length} 个工具',
                          style: TextStyle(
                            fontSize: 11,
                            color: p.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MochiCatSpacing.lg),
                  Wrap(
                    spacing: MochiCatSpacing.xl,
                    runSpacing: MochiCatSpacing.xl,
                    children: [
                      for (final tool in tools)
                        SizedBox(
                          width: cardWidth,
                          child: _ToolShortcut(
                            tool: tool,
                            onTap: () =>
                                ref.read(pageNavProvider.notifier).open(tool.id),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: MochiCatSpacing.xxl),
                  // 页脚便签
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: MochiCatSpacing.lg,
                      vertical: MochiCatSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(MochiCatRadius.md),
                      border: Border.all(color: p.border),
                    ),
                    child: Row(
                      children: [
                        Icon(AppIcons.pets, color: p.primary, size: 17),
                        const SizedBox(width: MochiCatSpacing.sm),
                        Expanded(
                          child: Text(
                            '愿你的每次操作都顺顺利利',
                            style: TextStyle(
                              fontSize: 12,
                              color: p.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          'ToolBox 1.4.0',
                          style: TextStyle(
                            fontSize: 11,
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 顶部欢迎 Hero：淡紫到奶杏渐变 + 右侧猫咪吉祥物 + 主动作按钮。
class _HomeHero extends StatelessWidget {
  const _HomeHero({required this.compact, required this.onStart});

  final bool compact;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 174),
      padding: EdgeInsets.all(compact ? MochiCatSpacing.xl : 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: dark
              ? [const Color(0xFF3A3350), const Color(0xFF44333C)]
              : [const Color(0xFFEEE7FF), const Color(0xFFFFF0E9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(MochiCatRadius.hero),
      ),
      child: Stack(
        children: [
          Positioned(
            right: compact ? -6 : 38,
            top: compact ? 4 : -4,
            child: Opacity(
              opacity: compact ? 0.3 : 1,
              child: const _CatMascot(),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(right: compact ? 0 : 190),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '喵，今天想先做点什么？',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: MochiCatSpacing.sm),
                Text(
                  '常用开发工具整齐收好，专注完成每一次工作。',
                  style: TextStyle(fontSize: 13, color: p.textSecondary),
                ),
                const SizedBox(height: MochiCatSpacing.lg),
                MochiButton(
                  label: '开始工作',
                  icon: AppIcons.sparkles,
                  type: MochiButtonType.primary,
                  onPressed: onStart,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 猫咪吉祥物：白色圆形 + 猫脸，用于 Hero 右侧。
class _CatMascot extends StatelessWidget {
  const _CatMascot();

  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);
    return Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        color: p.surface,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: p.primary.withValues(alpha: .14),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: const Center(
        child: Text('🐱', style: TextStyle(fontSize: 70)),
      ),
    );
  }
}

class _ToolShortcut extends StatefulWidget {
  const _ToolShortcut({required this.tool, required this.onTap});
  final Tool tool;
  final VoidCallback onTap;
  @override
  State<_ToolShortcut> createState() => _ToolShortcutState();
}

class _ToolShortcutState extends State<_ToolShortcut> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);
    final icon = switch (widget.tool.id) {
      'repository' => AppIcons.repository,
      'remote' => AppIcons.remote,
      _ => AppIcons.fallback,
    };
    final iconBackground =
        widget.tool.id == 'remote' ? p.mintSoft : p.primarySoft;
    final iconColor = widget.tool.id == 'remote' ? p.mint : p.primary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(MochiCatRadius.xl),
          border: Border.all(
            color: _hovered
                ? p.primary.withValues(alpha: .45)
                : p.border,
          ),
          boxShadow: _hovered ? const [MochiCatShadow.hover] : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(MochiCatRadius.xl),
            child: Padding(
              padding: const EdgeInsets.all(MochiCatSpacing.lg + 4),
              child: Row(children: [
                Container(
                  width: 43,
                  height: 43,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(MochiCatRadius.lg),
                  ),
                  child: Icon(icon, color: iconColor, size: 21),
                ),
                const SizedBox(width: MochiCatSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.tool.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.tool.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: p.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  AppIcons.chevronRight,
                  color: p.textSecondary,
                  size: 20,
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
