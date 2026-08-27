import 'package:flutter/material.dart';

/// AppFlowy 色板常量（浅色/深色各一套）。
///
/// 注意：数值已替换为「糯米猫」设计语义色板，作为兼容层保留类名，
/// 使旧页面代码直接获得新配色；新代码应优先使用 MochiCatPalette。
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
    layer01: Color(0xFFF8F7FC),
    layer02: Color(0xFFE8E4EF),
    layer03: Color(0xFFF2EEFB),
    textPrimary: Color(0xFF302D42),
    textSecondary: Color(0xFF88839B),
    textTertiary: Color(0xFF9C97AC),
    primary: Color(0xFF7857C8),
    primaryHover: Color(0xFF6D4BBB),
    border: Color(0xFFE8E4EF),
    error: Color(0xFFDF6D7D),
  );

  static const dark = AppflowyColors._(
    surface: Color(0xFF272634),
    layer01: Color(0xFF2B2A39),
    layer02: Color(0xFF373548),
    layer03: Color(0xFF332E46),
    textPrimary: Color(0xFFE9E6F1),
    textSecondary: Color(0xFF9C97AC),
    textTertiary: Color(0xFF88839B),
    primary: Color(0xFFA889EF),
    primaryHover: Color(0xFFB79BF2),
    border: Color(0xFF373548),
    error: Color(0xFFE8808F),
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
