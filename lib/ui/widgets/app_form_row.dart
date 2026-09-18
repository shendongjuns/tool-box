import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:toolbox/ui/theme/app_layout.dart';

/// 表单行：**左侧字段名（悬停显示详细说明）+ 右侧输入控件**。
///
/// 为什么不用 ForUI 的 `FTextField.label`：它固定渲染在输入框**上方**，
/// 桌面端一个字段要占两行，字段一多弹窗就被撑得很长。改成横向排布后，
/// 名称在左形成一列、输入框在右形成一列，一屏能放下更多字段。
///
/// 详细说明（原来写在名称括号里的那段）移到悬停提示，界面更干净。
class AppFormRow extends StatelessWidget {
  const AppFormRow({
    required this.label,
    required this.child,
    this.description,
    this.labelWidth = AppLayout.formLabelWidth,
    super.key,
  });

  /// 左侧字段名，建议 2~4 个字。
  final String label;

  /// 悬停时展示的详细说明；为空则退化成普通文本。
  final String? description;

  /// 右侧输入控件。
  final Widget child;

  /// 名称列宽度（同一弹窗内保持一致才能对齐）。
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: theme.typography.body.sm.copyWith(
        color: theme.colors.mutedForeground,
      ),
    );

    return Row(
      children: [
        SizedBox(
          width: labelWidth,
          child: description == null
              ? text
              : FTooltip(
                  control: FTooltipControl.managed(),
                  hover: true,
                  tipBuilder: (context, controller) => SizedBox(
                    width: 240,
                    child: Text(
                      description!,
                      style: theme.typography.body.sm,
                    ),
                  ),
                  child: text,
                ),
        ),
        const SizedBox(width: AppLayout.gapMd),
        Expanded(child: child),
      ],
    );
  }
}
