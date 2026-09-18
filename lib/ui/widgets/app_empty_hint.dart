import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:toolbox/ui/theme/app_layout.dart';

/// 面板空状态：图标 + 标题 + 说明（+ 可选操作按钮）。
///
/// **必须自适应可用高度**：空状态出现在可拖拽 / 可折叠的面板里
/// （文件面板、监控栏、仓库列表），可用高度可能被压到 100px 出头。
/// 早期版本用固定尺寸的 Column，把面板拖小后会直接
/// `BOTTOM OVERFLOWED BY 92 PIXELS`（用户实际截图报过这个问题）。
///
/// 处理方式：
/// 1. 按可用高度**分级降级**：空间不够时依次省略 按钮 → 图标 → 说明，
///    标题永不省略；
/// 2. 最外层套一层不带滚动条的 `SingleChildScrollView` 作兜底，
///    保证任何尺寸下都不会溢出 —— 「宁可少显示，也不报红」。
class AppEmptyHint extends StatelessWidget {
  const AppEmptyHint({
    required this.icon,
    required this.text,
    required this.detail,
    this.onAction,
    this.actionLabel,
    this.compact = false,
    super.key,
  });

  final IconData icon;
  final String text;
  final String detail;
  final VoidCallback? onAction;
  final String? actionLabel;

  /// 紧凑模式（用于很矮的面板，缩小图标）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final iconSize = compact ? 26.0 : 40.0;

    // 各分级所需的可用高度（含上下内边距 16 与元素间距），按实际字号估算。
    const double textBlock = 24; // 一行标题 + 内边距
    const double detailBlock = 25; // 说明 + 间距
    const double iconBlock = 12 + 40; // 间距 + 图标
    const double actionBlock = 12 + 34; // 间距 + 按钮

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final showDetail = h >= textBlock + detailBlock;
        final showIcon = showDetail && h >= textBlock + detailBlock + iconBlock;
        final showAction =
            onAction != null && showIcon && h >= textBlock + detailBlock + iconBlock + actionBlock;

        return Center(
          child: ScrollConfiguration(
            // 兜底滚动不显示滚动条：正常情况下阈值分级已经让内容放得下，
            // 空状态里挂一条滚动条观感很差。
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppLayout.gapLg,
                vertical: AppLayout.gapSm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showIcon) ...[
                    Icon(
                      icon,
                      size: iconSize,
                      color: theme.colors.primary.withValues(alpha: .55),
                    ),
                    const SizedBox(height: AppLayout.gapMd),
                  ],
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: theme.typography.body.sm.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (showDetail) ...[
                    const SizedBox(height: AppLayout.gapXs),
                    Text(
                      detail,
                      textAlign: TextAlign.center,
                      style: theme.typography.body.xs.copyWith(
                        color: theme.colors.mutedForeground,
                      ),
                    ),
                  ],
                  if (showAction) ...[
                    const SizedBox(height: AppLayout.gapMd),
                    FButton(
                      mainAxisSize: MainAxisSize.min,
                      variant: FButtonVariant.primary,
                      onPress: onAction,
                      child: Text(actionLabel ?? '开始'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
