import 'package:flutter/material.dart';

import 'mochi_cat_tokens.dart';

/// 糯米猫主题构建器：基于设计 Token 定制的 Material ThemeData。
///
/// 浅色为已审核基准；深色按相同语义 Token 扩展。
abstract final class MochiCatTheme {
  static ThemeData light() => _build(Brightness.light, MochiCatPalette.light);

  static ThemeData dark() => _build(Brightness.dark, MochiCatPalette.dark);

  static ThemeData _build(Brightness brightness, MochiCatPalette p) {
    // 反向色板用于 inverse* 语义色（浅色主题的 inverse 取深色色板）。
    final inverse = brightness == Brightness.light
        ? MochiCatPalette.dark
        : MochiCatPalette.light;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.primary,
      onPrimary: Colors.white,
      primaryContainer: p.primarySoft,
      onPrimaryContainer: p.textPrimary,
      secondary: p.mint,
      onSecondary: Colors.white,
      secondaryContainer: p.mintSoft,
      onSecondaryContainer: p.textPrimary,
      tertiary: p.orange,
      onTertiary: Colors.white,
      error: p.danger,
      onError: Colors.white,
      surface: p.surface,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      surfaceContainerLowest: p.surface,
      surfaceContainerLow: p.surfaceMuted,
      surfaceContainer: p.primarySoft.withValues(alpha: .55),
      surfaceContainerHigh: p.border.withValues(alpha: .55),
      surfaceContainerHighest: p.border,
      inverseSurface: inverse.surface,
      onInverseSurface: inverse.textPrimary,
      inversePrimary: inverse.primary,
      surfaceTint: Colors.transparent,
      outline: p.border,
      outlineVariant: p.border,
    );

    final roundedSm = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(MochiCatRadius.sm),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      fontFamily: 'Microsoft YaHei UI',
      dividerColor: p.border,
      splashFactory: InkSparkle.splashFactory,
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: p.textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: p.textPrimary,
        ),
        headlineSmall: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: p.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: p.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: p.textPrimary,
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: p.textPrimary,
        ),
        bodyLarge: TextStyle(fontSize: 15, color: p.textPrimary),
        bodyMedium: TextStyle(fontSize: 14, color: p.textPrimary),
        bodySmall: TextStyle(fontSize: 12, color: p.textSecondary),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: p.textPrimary,
        ),
        labelMedium: TextStyle(fontSize: 12, color: p.textSecondary),
        labelSmall: TextStyle(fontSize: 11, color: p.textSecondary),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MochiCatRadius.lg),
          side: BorderSide(color: p.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceMuted,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: MochiCatSpacing.md,
          vertical: MochiCatSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MochiCatRadius.sm),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MochiCatRadius.sm),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MochiCatRadius.sm),
          borderSide: BorderSide(color: p.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MochiCatRadius.sm),
          borderSide: BorderSide(color: p.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MochiCatRadius.sm),
          borderSide: BorderSide(color: p.danger, width: 1.5),
        ),
        hintStyle: TextStyle(fontSize: 13, color: p.textSecondary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, MochiCatSize.buttonHeight),
          backgroundColor: p.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(horizontal: MochiCatSpacing.lg),
          shape: roundedSm,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, MochiCatSize.buttonHeight),
          foregroundColor: p.textPrimary,
          side: BorderSide(color: p.border),
          backgroundColor: p.surface,
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(horizontal: MochiCatSpacing.lg),
          shape: roundedSm,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 32),
          foregroundColor: p.textSecondary,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          shape: roundedSm,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        elevation: 8,
        shadowColor: Colors.black38,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MochiCatRadius.xxl),
          side: BorderSide(color: p.border.withValues(alpha: .6)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.terminal,
        contentTextStyle: const TextStyle(
          fontSize: 13,
          color: MochiCatColors.terminalText,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MochiCatRadius.lg),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MochiCatRadius.md),
          side: BorderSide(color: p.border),
        ),
        textStyle: TextStyle(fontSize: 13, color: p.textPrimary),
      ),
      listTileTheme: const ListTileThemeData(dense: true),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.terminal,
          borderRadius: BorderRadius.circular(MochiCatRadius.sm),
        ),
        textStyle: const TextStyle(
          fontSize: 12,
          color: MochiCatColors.terminalText,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : p.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? p.primary
              : p.border,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? p.surface
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? p.primary
                : p.textSecondary,
          ),
          side: WidgetStateProperty.all(BorderSide(color: p.border)),
          textStyle: WidgetStatePropertyAll(
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
