package com.toolbox.framework.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * ToolBox 字体层级 —— 使用 Segoe UI Variable（Windows 11 原生，接近 SF Pro 观感）。
 *
 * 层级：
 * - Large Title  28sp  SemiBold  页面主标题
 * - Title 1      22sp  Medium    卡片标题
 * - Title 2      17sp  Medium    分组标题
 * - Body         15sp  Regular   正文内容
 * - Caption      12sp  Regular   辅助说明
 * - Mono         13sp  Regular   等宽代码（JetBrains Mono）
 */
val ToolBoxTypography = Typography(
    headlineLarge = TextStyle(
        fontFamily = FontFamily.Default,    // Segoe UI Variable on Win11
        fontWeight = FontWeight.SemiBold,
        fontSize = 28.sp,
        lineHeight = 34.sp,
        letterSpacing = 0.36.sp,
        color = ToolBoxColors.TextPrimary
    ),
    headlineMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Medium,
        fontSize = 22.sp,
        lineHeight = 28.sp,
        letterSpacing = 0.35.sp,
        color = ToolBoxColors.TextPrimary
    ),
    titleLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Medium,
        fontSize = 17.sp,
        lineHeight = 22.sp,
        letterSpacing = -0.41.sp,
        color = ToolBoxColors.TextPrimary
    ),
    bodyLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 15.sp,
        lineHeight = 20.sp,
        letterSpacing = -0.24.sp,
        color = ToolBoxColors.TextSecondary
    ),
    bodySmall = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.sp,
        color = ToolBoxColors.TextTertiary
    ),
    labelSmall = TextStyle(
        fontFamily = FontFamily.Monospace,   // JetBrains Mono / Cascadia Code
        fontWeight = FontWeight.Normal,
        fontSize = 13.sp,
        lineHeight = 18.sp,
        color = ToolBoxColors.TextSecondary
    )
)

/** 等宽字体（代码区域使用） */
val CodeFontFamily = FontFamily.Monospace
