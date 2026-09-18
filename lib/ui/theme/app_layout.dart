/// 布局常量。
///
/// 刻意与「样式」分离：ForUI 没有提供间距刻度（`FStyle` 只给了
/// `borderRadius` / `sizes` / `pagePadding` / `shadow`），因此业务布局中的
/// 间隙仍需一组数值常量。本文件**只放布局数值**——颜色、圆角、字体、
/// 阴影等全部由 ForUI 主题负责，不在此处定义。
abstract final class AppLayout {
  static const gapXs = 4.0;
  static const gapSm = 8.0;
  static const gapMd = 12.0;
  static const gapLg = 16.0;
  static const gapXl = 20.0;

  /// 表单行左侧字段名的宽度（`AppFormRow`）。
  static const formLabelWidth = 84.0;

  /// 远程页左侧连接面板宽度（可拖拽，此为初始值）。
  static const connectionPanelWidth = 205.0;
}
