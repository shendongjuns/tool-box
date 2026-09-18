import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// ForUI 悬停提示的轻封装：`Tooltip(message:, child:)` 的对位替换。
class AppTooltip extends StatelessWidget {
  const AppTooltip({required this.message, required this.child, super.key});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = context.theme.typography.body.sm;
    return FTooltip(
      control: FTooltipControl.managed(),
      hover: true,
      tipBuilder: (context, controller) =>
          SizedBox(width: 260, child: Text(message, style: style)),
      // 同时把文案挂到语义树：读屏软件能念出图标按钮的用途，
      // 也让测试有一个统一锚点（ForUI 的 FTooltip 不是 Material 的 Tooltip，
      // `find.byTooltip` 找不到它）。
      child: Semantics(tooltip: message, child: child),
    );
  }
}
