import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// 磁贴（列表行）内的小图标按钮：**明确的悬停反馈**。
///
/// ForUI 的 ghost 按钮悬停底色与磁贴自身底色几乎同色，视觉上「没有反应」；
/// 这里直接用 [FTappable] 的 hovered 变体画一层比磁贴底色深一档的高亮，
/// 危险操作（删除）悬停时图标与底色转 destructive。
///
/// 命中区是 [size]×[size]（桌面端建议 ≥ 30），但**悬停高亮只画在
/// 内缩 2px 的 26×26 圆角块上** —— 相邻按钮即便紧挨着排列，
/// 两块高亮之间也始终有可见间隙，不会「连成一片」。
class TileIconButton extends StatelessWidget {
  const TileIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPress,
    this.destructive = false,
    this.iconSize = 15,
    this.size = 30,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPress;

  /// 危险操作：悬停时图标/底色转 destructive。
  final bool destructive;

  final double iconSize;

  /// 命中区边长（桌面端建议 ≥ 30）。
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTappable(
      onPress: onPress,
      semanticsTooltip: tooltip,
      builder: (context, variants, child) {
        final hovered = variants.contains(FTappableVariant.hovered);
        final fg = destructive && hovered
            ? colors.destructive
            : colors.mutedForeground;
        return SizedBox(
          width: size,
          height: size,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              width: size - 4,
              height: size - 4,
              decoration: ShapeDecoration(
                color: hovered
                    ? (destructive
                          ? colors.destructive.withValues(alpha: .12)
                          : colors.muted)
                    : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: context.theme.style.borderRadius.sm,
                ),
              ),
              child: Icon(icon, size: iconSize, color: fg),
            ),
          ),
        );
      },
    );
  }
}
