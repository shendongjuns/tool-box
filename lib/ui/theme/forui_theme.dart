import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// ToolBox 1.5.0 主题。
///
/// 设计原则：**完全基于 ForUI 内置能力，不定义任何自定义样式与配色**。
/// * 色板：使用 ForUI 内置的 [FColors.neutralLight] / [FColors.neutralDark]
/// * Widget 样式：不向 [FThemeData] 传任何 `*Style` 覆盖，全部由 ForUI 自行派生
/// * Material 兜底层：不手写任何 `ThemeData`，直接用框架默认值（见 `main.dart`）
///
/// ### 为什么不用 `FThemeData.toApproximateMaterialTheme()`
/// ForUI 提供了这个 Material 桥接方法，但本项目无法使用：
/// ForUI 0.26 依赖的是独立包 `material_ui`，它的 `ThemeData` 与 SDK 内
/// `package:flutter/material.dart` 的 `ThemeData` 是**两个不同的类**，不能互相赋值。
/// 而 vendored 的 `xterm` 内部用的是 SDK 版 Material —— 若改为依赖 `material_ui`，
/// 会在同一棵 widget 树里形成两套 Material 并存，反而更不稳定。
/// 因此 Material 层只保留框架默认外观，视觉一致性全部交给 ForUI 负责。
abstract final class AppTheme {
  /// 浅色 ForUI 主题。
  static final FThemeData light = _build(FColors.neutralLight, 'ToolBox Light');

  /// 深色 ForUI 主题。
  static final FThemeData dark = _build(FColors.neutralDark, 'ToolBox Dark');

  /// 按亮度取对应的 [FThemeData]。
  static FThemeData of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// 弹窗退场动画时长（取自 ForUI 路由主题，默认 150ms）。
  ///
  /// 给 `disposeAfterDialog` 用：调用点在 `await` 之后释放弹窗里的控制器，
  /// 若在调用点读主题就要跨 async gap 传 `BuildContext`（会触发
  /// `use_build_context_synchronously`），所以在这里集中暴露一次。
  /// ForUI 调整动画时长时这里会自动跟上，不需要改业务代码。
  static Duration get dialogExitAnimation =>
      light.dialogRouteStyle.motion.exitDuration;

  static FThemeData _build(FColors colors, String label) => FThemeData(
    colors: colors,
    // Windows 桌面端：必须显式传 false，否则会拿到触屏尺寸规范。
    touch: false,
    debugLabel: label,
    typography: _typography(colors),
  );

  /// 中文字形配置。
  ///
  /// ForUI 默认字体是 `packages/forui/Inter`，**不含 CJK 字形**。不声明字体族时
  /// 中文会走系统字体回退，在 Windows 上可能落到宋体一类不适合 UI 的字体。
  ///
  /// 这里用 ForUI 自己的 API 只覆盖**字体族**，字号 / 字重 / 行高仍完全由
  /// ForUI 的字号体系决定 —— 属于渲染配置，不是样式定制。
  /// 若要绝对零覆盖，删掉 `typography: _typography(colors)` 这一行即可。
  static FTypography _typography(FColors colors) {
    final typeface = FTypeface.inherit(
      colors: colors,
      touch: false,
      fontFamily: 'Microsoft YaHei UI',
    );
    return FTypography(display: typeface, body: typeface);
  }
}
