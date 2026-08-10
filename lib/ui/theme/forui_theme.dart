import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'appflowy_colors.dart';

/// 构建 Forui 主题：Appflowy 色板映射到 FColors token。
///
/// 样式（style 及各组件 style）用 Forui 默认值
/// （[FThemeData] 工厂内自动 inherit），仅定制色板与字体
/// （Forui 默认 Inter 打包字体，统一改为 Windows 系统字体微软雅黑）。
FThemeData buildForuiTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final c = isDark ? AppflowyColors.dark : AppflowyColors.light;

  final colors = FColors(
    brightness: brightness,
    // 状态栏图标颜色与主题背景相反：浅色主题用深色图标，深色主题用浅色图标。
    systemOverlayStyle:
        isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    barrier: Colors.black54,
    background: c.surface,
    foreground: c.textPrimary,
    primary: c.primary,
    primaryForeground: Colors.white,
    secondary: c.layer02,
    secondaryForeground: c.textPrimary,
    muted: c.layer01,
    mutedForeground: c.textTertiary,
    destructive: c.error,
    destructiveForeground: Colors.white,
    error: c.error,
    errorForeground: Colors.white,
    card: c.surface,
    border: c.border,
  );

  return FThemeData(
    colors: colors,
    // 桌面应用非触屏优化。
    touch: false,
    // FTypography 无 fontFamily 参数，字体在 FTypeface 上（Forui 默认
    // 打包 Inter）。用 FTypeface.inherit 保持 FThemeData 默认的字色继承
    // 与非触屏字号，仅替换字体为 Windows 系统字体微软雅黑。
    typography: FTypography(
      display: FTypeface.inherit(
        colors: colors,
        touch: false,
        fontFamily: 'Microsoft YaHei UI',
      ),
      body: FTypeface.inherit(
        colors: colors,
        touch: false,
        fontFamily: 'Microsoft YaHei UI',
      ),
    ),
  );
}
