import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/ui/widgets/app_tooltip.dart';

/// 按「提示文案」查找控件。
///
/// 1.5.0 起所有提示统一由 ForUI 提供，**不再有 Material 的 `Tooltip` 组件**，
/// 所以 `find.byTooltip(...)` 在本项目里永远找不到东西（改造时这类断言静默失效，
/// 直到 2026-09-18 首次跑通 `flutter test` 才暴露）。
///
/// 这里按两种实际落地形态匹配，语义等价于旧断言：
/// - `AppTooltip(message: ...)` —— 图标按钮的悬停提示；
/// - `FButton(semanticsTooltip: ...)` —— 落到 `Semantics(properties.tooltip)`。
Finder byTip(String message) => find.byWidgetPredicate(
  (widget) =>
      (widget is AppTooltip && widget.message == message) ||
      (widget is Semantics && widget.properties.tooltip == message),
  description: '提示为「$message」的控件',
);
