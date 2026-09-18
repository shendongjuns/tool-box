import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// 应用内轻提示（ForUI Toaster：右上角浮层，可点击关闭/划动消除）。
///
/// 替代 Material 的 SnackBar。组件树中必须有 [FToaster] 祖先
/// （main.dart 的 builder 里已挂载）。
void showAppToast(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  final variant = error ? FToastVariant.destructive : FToastVariant.primary;
  FToaster.of(context).show(
    variant: variant,
    builder: (context, entry) => FToast(
      variant: variant,
      title: Text(message),
    ),
  );
}
