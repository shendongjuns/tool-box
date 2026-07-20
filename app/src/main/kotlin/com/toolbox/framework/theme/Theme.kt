package com.toolbox.framework.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

/**
 * ToolBox 浅色主题 —— 基于 Apple 设计语言的极简风格。
 *
 * 使用方式：
 * ```
 * ToolBoxTheme {
 *     // 应用内容
 *     Text("Hello", style = MaterialTheme.typography.headlineLarge)
 * }
 * ```
 */
private val ToolBoxColorScheme = lightColorScheme(
    primary            = ToolBoxColors.Blue,
    onPrimary          = ToolBoxColors.TextOnPrimary,
    primaryContainer   = ToolBoxColors.SidebarSelected,
    onPrimaryContainer = ToolBoxColors.Blue,
    secondary          = ToolBoxColors.Purple,
    tertiary           = ToolBoxColors.Green,
    error              = ToolBoxColors.Red,
    surface            = ToolBoxColors.Surface,
    onSurface          = ToolBoxColors.TextPrimary,
    surfaceVariant     = ToolBoxColors.SurfaceVariant,
    onSurfaceVariant   = ToolBoxColors.TextSecondary,
    outline            = ToolBoxColors.Outline,
    outlineVariant     = ToolBoxColors.Outline,
)

@Composable
fun ToolBoxTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = ToolBoxColorScheme,
        typography  = ToolBoxTypography,
        shapes      = ToolBoxShapes,
        content     = content
    )
}
