import 'package:flutter/material.dart';
import 'appflowy_colors.dart';

/// AppFlowy 配色主题：基于 AppFlowy 色板定制的 Material ThemeData。
class AppflowyTheme {
  AppflowyTheme._();

  static ThemeData light() => _build(Brightness.light, AppflowyColors.light);

  static ThemeData dark() => _build(Brightness.dark, AppflowyColors.dark);

  static ThemeData _build(Brightness brightness, AppflowyColors c) {
    // 反向色板用于 inverse* 语义色（浅色主题的 inverse 取深色色板）。
    final inverse = brightness == Brightness.light
        ? AppflowyColors.dark
        : AppflowyColors.light;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: Colors.white,
      primaryContainer: c.layer02,
      onPrimaryContainer: c.textPrimary,
      secondary: c.primary,
      onSecondary: Colors.white,
      tertiary: c.textSecondary,
      onTertiary: Colors.white,
      error: c.error,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      surfaceContainerLowest: c.surface,
      surfaceContainerLow: c.layer01,
      surfaceContainer: c.layer01,
      surfaceContainerHigh: c.layer02,
      surfaceContainerHighest: c.layer03,
      inverseSurface: inverse.surface,
      onInverseSurface: inverse.textPrimary,
      inversePrimary: inverse.primary,
      surfaceTint: Colors.transparent,
      outline: c.border,
      outlineVariant: c.layer02,
    );

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: c.surface,
      fontFamily: 'Microsoft YaHei UI',
      textTheme: TextTheme(
        headlineLarge: TextStyle(
            fontSize: 28, fontWeight: FontWeight.w700, color: c.textPrimary),
        headlineMedium: TextStyle(
            fontSize: 24, fontWeight: FontWeight.w600, color: c.textPrimary),
        headlineSmall: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w600, color: c.textPrimary),
        titleLarge: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w600, color: c.textPrimary),
        titleMedium: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary),
        titleSmall: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: c.textPrimary),
        bodyLarge: TextStyle(fontSize: 15, color: c.textPrimary),
        bodyMedium: TextStyle(fontSize: 14, color: c.textPrimary),
        bodySmall: TextStyle(fontSize: 12, color: c.textSecondary),
        labelLarge: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: c.textPrimary),
        labelMedium: TextStyle(fontSize: 12, color: c.textTertiary),
        labelSmall: TextStyle(fontSize: 11, color: c.textTertiary),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppflowyRadius.m),
          side: BorderSide(color: c.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppflowyRadius.m),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppflowyRadius.m),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppflowyRadius.m),
          borderSide: BorderSide(color: c.primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          overlayColor: c.primaryHover,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppflowyRadius.m),
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: AppflowySpacing.xl, vertical: AppflowySpacing.m),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          side: BorderSide(color: c.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppflowyRadius.m),
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: AppflowySpacing.xl, vertical: AppflowySpacing.m),
        ),
      ),
    );
  }
}
