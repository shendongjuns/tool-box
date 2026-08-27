import 'package:flutter/material.dart';

/// 糯米猫（Mochi Cat）设计 Token。
///
/// 浅色为已审核基准，深色按相同语义 Token 扩展。
abstract final class MochiCatColors {
  // —— 浅色 ——
  static const primary = Color(0xFF7857C8);
  static const primaryHover = Color(0xFF6D4BBB);
  static const primaryPressed = Color(0xFF553493);
  static const primarySoft = Color(0xFFF2EEFB);
  static const creamSoft = Color(0xFFFFF3ED);
  static const mint = Color(0xFF43AA8B);
  static const mintSoft = Color(0xFFEAF8F3);
  static const orange = Color(0xFFEE9660);
  static const danger = Color(0xFFDF6D7D);
  static const dangerSoft = Color(0xFFFFF3F5);
  static const background = Color(0xFFF8F7FC);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFFBFAFF);
  static const textPrimary = Color(0xFF302D42);
  static const textSecondary = Color(0xFF88839B);
  static const border = Color(0xFFE8E4EF);
  static const terminal = Color(0xFF272634);
  static const terminalText = Color(0xFFE9E6F1);

  // 趋势图专用色。
  static const cpu = Color(0xFF3F6AD8);
  static const memory = Color(0xFF2E7D32);
  static const download = Color(0xFF1E88E5);
  static const upload = Color(0xFFF05033);

  // —— 深色扩展 ——
  static const darkPrimary = Color(0xFFA889EF);
  static const darkPrimaryHover = Color(0xFFB79BF2);
  static const darkPrimaryPressed = Color(0xFF9370D9);
  static const darkPrimarySoft = Color(0xFF332E46);
  static const darkCreamSoft = Color(0xFF3D3130);
  static const darkMint = Color(0xFF5FC6A8);
  static const darkMintSoft = Color(0xFF1F3B33);
  static const darkOrange = Color(0xFFEEA67A);
  static const darkDanger = Color(0xFFE8808F);
  static const darkDangerSoft = Color(0xFF3E2A30);
  static const darkBackground = Color(0xFF201F2A);
  static const darkSurface = Color(0xFF272634);
  static const darkSurfaceMuted = Color(0xFF2B2A39);
  static const darkTextPrimary = Color(0xFFE9E6F1);
  static const darkTextSecondary = Color(0xFF9C97AC);
  static const darkBorder = Color(0xFF373548);
  static const darkTerminal = Color(0xFF1B1A25);
  static const darkTerminalText = Color(0xFFE9E6F1);
}

abstract final class MochiCatSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;
}

abstract final class MochiCatRadius {
  static const xs = 6.0;
  static const sm = 9.0;
  static const md = 11.0;
  static const lg = 13.0;
  static const xl = 15.0;
  static const xxl = 18.0;
  static const hero = 20.0;
  static const pill = 999.0;
}

abstract final class MochiCatSize {
  static const topBarHeight = 52.0;
  static const buttonHeight = 36.0;
  static const inputHeight = 36.0;
  static const iconButton = 32.0;
  static const connectionPanelWidth = 205.0;
  static const dialogWidth = 460.0;
}

abstract final class MochiCatShadow {
  static const hover = BoxShadow(
    color: Color(0x386847B7),
    blurRadius: 12,
    offset: Offset(0, 4),
  );
}

/// 当前明暗色板便捷访问：`MochiCatColors.of(context)`。
class MochiCatPalette {
  const MochiCatPalette({
    required this.primary,
    required this.primaryHover,
    required this.primaryPressed,
    required this.primarySoft,
    required this.creamSoft,
    required this.mint,
    required this.mintSoft,
    required this.orange,
    required this.danger,
    required this.dangerSoft,
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.terminal,
    required this.terminalText,
  });

  final Color primary;
  final Color primaryHover;
  final Color primaryPressed;
  final Color primarySoft;
  final Color creamSoft;
  final Color mint;
  final Color mintSoft;
  final Color orange;
  final Color danger;
  final Color dangerSoft;
  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color terminal;
  final Color terminalText;

  static const light = MochiCatPalette(
    primary: MochiCatColors.primary,
    primaryHover: MochiCatColors.primaryHover,
    primaryPressed: MochiCatColors.primaryPressed,
    primarySoft: MochiCatColors.primarySoft,
    creamSoft: MochiCatColors.creamSoft,
    mint: MochiCatColors.mint,
    mintSoft: MochiCatColors.mintSoft,
    orange: MochiCatColors.orange,
    danger: MochiCatColors.danger,
    dangerSoft: MochiCatColors.dangerSoft,
    background: MochiCatColors.background,
    surface: MochiCatColors.surface,
    surfaceMuted: MochiCatColors.surfaceMuted,
    textPrimary: MochiCatColors.textPrimary,
    textSecondary: MochiCatColors.textSecondary,
    border: MochiCatColors.border,
    terminal: MochiCatColors.terminal,
    terminalText: MochiCatColors.terminalText,
  );

  static const dark = MochiCatPalette(
    primary: MochiCatColors.darkPrimary,
    primaryHover: MochiCatColors.darkPrimaryHover,
    primaryPressed: MochiCatColors.darkPrimaryPressed,
    primarySoft: MochiCatColors.darkPrimarySoft,
    creamSoft: MochiCatColors.darkCreamSoft,
    mint: MochiCatColors.darkMint,
    mintSoft: MochiCatColors.darkMintSoft,
    orange: MochiCatColors.darkOrange,
    danger: MochiCatColors.darkDanger,
    dangerSoft: MochiCatColors.darkDangerSoft,
    background: MochiCatColors.darkBackground,
    surface: MochiCatColors.darkSurface,
    surfaceMuted: MochiCatColors.darkSurfaceMuted,
    textPrimary: MochiCatColors.darkTextPrimary,
    textSecondary: MochiCatColors.darkTextSecondary,
    border: MochiCatColors.darkBorder,
    terminal: MochiCatColors.darkTerminal,
    terminalText: MochiCatColors.darkTerminalText,
  );

  static MochiCatPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
