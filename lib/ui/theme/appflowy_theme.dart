import 'package:flutter/material.dart';
import 'appflowy_colors.dart';

/// AppFlowy 风格主题：Material ThemeData 定制。
class AppflowyTheme {
  AppflowyTheme._();

  static ThemeData light() => _build(Brightness.light, AppflowyColors.light);

  static ThemeData dark() => _build(Brightness.dark, AppflowyColors.dark);

  static ThemeData _build(Brightness brightness, AppflowyColors c) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: Colors.white,
      primaryContainer: c.layer02,
      onPrimaryContainer: c.textPrimary,
      secondary: c.primary,
      onSecondary: Colors.white,
      error: c.error,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
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
        titleLarge: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w600, color: c.textPrimary),
        titleMedium: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary),
        bodyLarge: TextStyle(fontSize: 15, color: c.textPrimary),
        bodyMedium: TextStyle(fontSize: 14, color: c.textPrimary),
        bodySmall: TextStyle(fontSize: 12, color: c.textSecondary),
        labelMedium: TextStyle(fontSize: 12, color: c.textTertiary),
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
