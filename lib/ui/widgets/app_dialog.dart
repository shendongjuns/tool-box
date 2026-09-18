import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:toolbox/ui/theme/app_layout.dart';
import 'package:toolbox/ui/theme/forui_theme.dart';

/// Esc 关闭弹窗的快捷键意图（配合 [Shortcuts] 使用）。
class _DismissDialogIntent extends Intent {
  const _DismissDialogIntent();
}

/// 弹窗关闭后安全释放 [TextEditingController]。
///
/// `Navigator.pop` 会让 `showFDialog` 的 future 立即 resolve，但弹窗的
/// 退出动画仍在进行、TextField 还挂在树上；此时 dispose controller 会在
/// 动画帧里触发 "used after being disposed" 崩溃。
///
/// 因此等退出动画真正结束再释放。时长取自 ForUI 主题
/// （[AppTheme.dialogExitAnimation]，默认 150ms），不再是写死的魔法值；
/// ForUI 调整动画时长时这里会自动跟上。
///
/// ⚠️ 调用约定：本函数是**延时释放**，调用点必须在它返回之前（其实是
/// `await` 之后同步地）读完控制器里的值——现有调用点都是这个顺序。
Future<void> disposeAfterDialog(List<TextEditingController> controllers) async {
  await Future<void>.delayed(
    AppTheme.dialogExitAnimation + const Duration(milliseconds: 50),
  );
  for (final controller in controllers) {
    controller.dispose();
  }
}

/// 弹窗宽度档位：同类弹窗严格等宽，视觉上才整齐。
/// - [dialogWidthSmall]  确认类、1~2 个字段
/// - [dialogWidthMedium] 常规表单
/// - [dialogWidthLarge]  宽表单、多按钮一行
const double dialogWidthSmall = 420;
const double dialogWidthMedium = 500;
const double dialogWidthLarge = 560;

/// 弹窗内表单的校验状态：(错误文案, 用户是否已动过表单)。
typedef DialogFormStatus = (String?, bool);

/// 弹窗内表单校验状态的持有者。
///
/// 解决的问题：旧实现是「点保存 → 弹窗关闭 → 才提示必填项为空」，
/// 用户刚填的内容会**随弹窗一起丢掉**。现在把校验前移：
/// - 保存 / 测试按钮按 [canSubmit] 置灰；
/// - 用户动过表单后才显示 [visibleError]（不打扰刚打开弹窗的人）。
///
/// 用法：
/// ```dart
/// final form = DialogFormState();
/// // 字段 onChange: (_) => form.check(validate);
/// // 按钮: ListenableBuilder(listenable: form, builder: (_, _) => FButton(
/// //   onPress: form.canSubmit ? () => Navigator.pop(context, true) : null, ...))
/// ```
class DialogFormState extends ValueNotifier<DialogFormStatus> {
  DialogFormState() : super((null, false));

  /// 重新校验；`validate` 返回 null 表示全部合法。
  void check(String? Function() validate) => value = (validate(), true);

  /// 当前是否可提交。
  bool get canSubmit => value.$1 == null;

  /// 需要展示的错误文案（用户还没动过表单时为 null）。
  String? get visibleError => value.$2 ? value.$1 : null;
}

/// 弹窗内的校验提示行：无错误时不占任何高度。
class DialogFormHint extends StatelessWidget {
  const DialogFormHint({required this.state, super.key});

  final DialogFormState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return ValueListenableBuilder<DialogFormStatus>(
      valueListenable: state,
      builder: (context, _, _) {
        final error = state.visibleError;
        if (error == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppLayout.gapMd),
          child: Row(
            children: [
              Icon(FLucideIcons.info, size: 15, color: colors.destructive),
              const SizedBox(width: AppLayout.gapSm),
              Expanded(
                child: Text(
                  error,
                  style: context.theme.typography.body.sm.copyWith(
                    color: colors.destructive,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 标准弹窗，由 ForUI 的 [showFDialog] + [FDialog] 构成。
///
/// ForUI 0.24 起 `FDialog` 不再提供内置内容布局（只有单个 builder），
/// 所以标题 / 内容 / 操作区在这里按主题 Token 组装，内部全部是 ForUI 组件。
///
/// 统一骨架：标题 → 副标题 → 正文 → 分隔线 → 操作区（次要靠左、主要靠右）。
/// 宽度用 `tightFor` 固定为传入的档位（[dialogWidthSmall] 等），
/// 不再随内容浮动 —— 这是「弹窗大小不一、不居中」的根因。
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  required Widget content,

  /// 底部操作区。**为空则不渲染整块**（含其上方分隔线）——
  /// 「设置」这类只靠右上角 × 退出的弹窗就是这种情况。
  List<Widget> actions = const [],
  List<Widget> leadingActions = const [],
  double width = dialogWidthMedium,
}) {
  final theme = context.theme;

  return showFDialog<T>(
    context: context,
    builder: (context, style, animation) => Shortcuts(
      // Esc 关闭弹窗：挂在 Shortcuts 上（而非 Focus），不会抢占输入框焦点，
      // 未被处理的 Escape 会沿着焦点链冒泡到这里。
      shortcuts: {
        SingleActivator(LogicalKeyboardKey.escape): const _DismissDialogIntent(),
      },
      child: Actions(
        actions: {
          _DismissDialogIntent: CallbackAction<_DismissDialogIntent>(
            onInvoke: (intent) {
              Navigator.of(context).pop();
              return null;
            },
          ),
        },
        child: FDialog(
          style: style,
          animation: animation,
          constraints: BoxConstraints.tightFor(width: width),
          builder: (context, style) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题行：右侧固定一个关闭按钮（等价于「取消」）。
                // 有些弹窗只有右上角的 X（例如「设置」），有些则底部还有操作区，
                // 两条退出路径并存是桌面端的惯例。
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(title, style: theme.typography.body.lg),
                      ),
                    ),
                    const SizedBox(width: AppLayout.gapSm),
                    FButton(
                      mainAxisSize: MainAxisSize.min,
                      variant: FButtonVariant.ghost,
                      size: FButtonSizeVariant.sm,
                      semanticsTooltip: '关闭',
                      onPress: () => Navigator.of(context).pop(),
                      child: const Icon(FLucideIcons.x, size: 16),
                    ),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppLayout.gapXs),
                  Text(
                    subtitle,
                    style: theme.typography.body.sm.copyWith(
                      color: theme.colors.mutedForeground,
                    ),
                  ),
                ],
                const SizedBox(height: AppLayout.gapLg),
                // 正文可滚动：内容高于弹窗可用高度时滚动，而不是溢出。
                // （弹性布局只在 Column 高度受限时生效，弹窗最大高度由
                // 窗口高度决定；设置弹窗在 800x600 下曾因此溢出 54px。）
                // 标题与操作区保持固定，只有正文滚动。
                Flexible(child: SingleChildScrollView(child: content)),
                if (actions.isNotEmpty || leadingActions.isNotEmpty) ...[
                  const SizedBox(height: AppLayout.gapXl),
                  const FDivider(),
                  const SizedBox(height: AppLayout.gapMd),
                  // 操作区同一行：左侧是次要操作（如「测试连接」），右侧是主操作。
                  // 主操作按钮用 Wrap 右对齐，按钮多或弹窗窄时自动换行，
                  // 避免 Row 溢出把最后一个按钮（通常是「删除」）裁掉。
                  //
                  // ⚠️ 放进 Wrap 的按钮必须显式 `mainAxisSize: MainAxisSize.min`：
                  // ForUI 的 FButton 默认是 MainAxisSize.max（撑满可用宽度），
                  // 而 Wrap 会把整行宽度交给每个子项，于是每个按钮各占一行。
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ...leadingActions,
                      if (leadingActions.isNotEmpty)
                        const SizedBox(width: AppLayout.gapSm),
                      Expanded(
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: AppLayout.gapSm,
                          runSpacing: AppLayout.gapSm,
                          children: actions,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// 通用删除确认弹窗（不可撤销提示 + 危险色删除按钮）。
Future<bool> showDeleteConfirm(
  BuildContext context, {
  required String title,
  required String description,
}) async {
  final theme = context.theme;

  final ok = await showAppDialog<bool>(
    context: context,
    title: title,
    width: dialogWidthSmall,
    content: Text(
      description,
      style: theme.typography.body.sm.copyWith(
        height: 1.6,
        color: theme.colors.mutedForeground,
      ),
    ),
    actions: [
      FButton(
        mainAxisSize: MainAxisSize.min,
        variant: FButtonVariant.ghost,
        onPress: () => Navigator.pop(context, false),
        child: const Text('取消'),
      ),
      FButton(
        mainAxisSize: MainAxisSize.min,
        variant: FButtonVariant.destructive,
        onPress: () => Navigator.pop(context, true),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FLucideIcons.trash2, size: 16),
            SizedBox(width: 6),
            Text('删除'),
          ],
        ),
      ),
    ],
  );
  return ok == true;
}
