import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// 拖拽分隔条的两种外观。
enum ResizeHandleStyle {
  /// 细线：命中区 6px，默认完全透明，悬停时显出一条 2px 的线（侧栏、仓库分组栏）。
  ///
  /// 适合紧贴内容的分隔（例如侧栏右缘），平时不占视觉。
  line(hitSize: 6, thickness: 2, length: null, tintHitArea: false),

  /// 胶囊：命中区 14px，悬停时整条变底色、中间露出一颗 40px 的胶囊
  /// （终端 / 文件面板之间、监控面板上下之间）。
  ///
  /// 适合两条内容之间的分隔 —— 命中区更宽、提示更明显，因为它两侧都是可操作区域。
  capsule(hitSize: 14, thickness: 3, length: 40, tintHitArea: true);

  const ResizeHandleStyle({
    required this.hitSize,
    required this.thickness,
    required this.length,
    required this.tintHitArea,
  });

  /// 命中区宽度（横轴）/ 高度（纵轴）。
  final double hitSize;

  /// 提示线粗细。
  final double thickness;

  /// 提示线长度；null 表示撑满可用空间。
  final double? length;

  /// 悬停时是否给整条命中区上底色。
  final bool tintHitArea;
}

/// 拖拽分隔条：拖动调整相邻面板的尺寸。
///
/// 全应用**只有这一个实现**。此前远程页（左右）、监控面板（上下）、仓库分组栏、侧栏
/// 各写了一份，命中区宽度、悬停提示、光标都不一致（仓库那份甚至没有任何悬停反馈，
/// 用户根本看不出那里能拖）。统一之后，改交互只需要动这一个文件。
///
/// 用法：把 [onDrag] 收到的增量累加到目标面板的尺寸上即可，
/// 横向分隔条收到 `dx`、纵向收到 `dy`（由 [axis] 决定）。
class AppResizeHandle extends StatefulWidget {
  const AppResizeHandle({
    required this.onDrag,
    this.axis = Axis.horizontal,
    this.onDragEnd,
    this.style = ResizeHandleStyle.line,
    super.key,
  });

  /// 沿 [axis] 的拖拽增量（像素）。
  final ValueChanged<double> onDrag;

  /// 拖拽方向：[Axis.horizontal] 表示左右拖动改变宽度。
  final Axis axis;

  /// 拖拽结束回调（用于立刻落盘，例如把面板宽度写进设置）。
  final VoidCallback? onDragEnd;

  /// 外观档位，见 [ResizeHandleStyle]。
  final ResizeHandleStyle style;

  @override
  State<AppResizeHandle> createState() => _AppResizeHandleState();
}

class _AppResizeHandleState extends State<AppResizeHandle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final style = widget.style;
    final horizontal = widget.axis == Axis.horizontal;

    final indicator = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: horizontal ? style.thickness : (style.length ?? double.infinity),
      height: horizontal ? (style.length ?? double.infinity) : style.thickness,
      decoration: BoxDecoration(
        color: switch (style) {
          ResizeHandleStyle.line => _hovered
              ? colors.border
              : const Color(0x00000000),
          ResizeHandleStyle.capsule => _hovered ? colors.primary : colors.border,
        },
        borderRadius: BorderRadius.circular(style.thickness / 2),
      ),
    );

    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: horizontal
            ? (details) => widget.onDrag(details.delta.dx)
            : null,
        onVerticalDragUpdate: horizontal
            ? null
            : (details) => widget.onDrag(details.delta.dy),
        onHorizontalDragEnd: horizontal
            ? (_) => widget.onDragEnd?.call()
            : null,
        onVerticalDragEnd: horizontal ? null : (_) => widget.onDragEnd?.call(),
        child: Container(
          width: horizontal ? style.hitSize : null,
          height: horizontal ? null : style.hitSize,
          color: style.tintHitArea && _hovered ? colors.secondary : null,
          alignment: Alignment.center,
          child: indicator,
        ),
      ),
    );
  }
}
