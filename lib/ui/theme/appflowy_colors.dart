import 'package:flutter/material.dart';

/// AppFlowy 色板常量（浅色/深色各一套）。
/// 来源：AppFlowy 主题源码（primitive + semantic token）。
class AppflowyColors {
  const AppflowyColors._({
    required this.surface,
    required this.layer01,
    required this.layer02,
    required this.layer03,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.primary,
    required this.primaryHover,
    required this.border,
    required this.error,
  });

  final Color surface;
  final Color layer01;
  final Color layer02;
  final Color layer03;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color primary;
  final Color primaryHover;
  final Color border;
  final Color error;

  static const light = AppflowyColors._(
    surface: Color(0xFFFFFFFF),
    layer01: Color(0xFFF8FAFF),
    layer02: Color(0xFFE4E8F5),
    layer03: Color(0xFFCED3E6),
    textPrimary: Color(0xFF21232A),
    textSecondary: Color(0xFF6F748C),
    textTertiary: Color(0xFF989EB7),
    primary: Color(0xFF0092D6),
    primaryHover: Color(0xFF0078C0),
    border: Color(0xFFE4E8F5),
    error: Color(0xFFE85D5D),
  );

  static const dark = AppflowyColors._(
    surface: Color(0xFF21232A),
    layer01: Color(0xFF272930),
    layer02: Color(0xFF32343F),
    layer03: Color(0xFF3D404F),
    textPrimary: Color(0xFFF8FAFF),
    textSecondary: Color(0xFFB5BBD3),
    textTertiary: Color(0xFF989EB7),
    primary: Color(0xFF4EC1FF),
    primaryHover: Color(0xFF80D2FF),
    border: Color(0xFF3D404F),
    error: Color(0xFFF27676),
  );
}

/// 间距常量（AppFlowy spacing token）。
class AppflowySpacing {
  const AppflowySpacing._();
  static const double xs = 4;
  static const double s = 6;
  static const double m = 8;
  static const double l = 12;
  static const double xl = 16;
  static const double xxl = 20;
}

/// 圆角常量（AppFlowy radius token）。
class AppflowyRadius {
  const AppflowyRadius._();
  static const double xs = 4;
  static const double s = 6;
  static const double m = 8;
  static const double l = 12;
  static const double xl = 16;
  static const double xxl = 20;
}
