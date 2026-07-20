package com.toolbox.common.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val LightColorScheme = lightColorScheme(
    primary             = ToolBoxColors.Blue,
    onPrimary           = ToolBoxColors.LightTextOnPrimary,
    primaryContainer    = ToolBoxColors.LightSidebarSelected,
    onPrimaryContainer  = ToolBoxColors.Blue,
    secondary           = ToolBoxColors.Purple,
    onSecondary         = ToolBoxColors.LightTextOnPrimary,
    secondaryContainer  = ToolBoxColors.Purple.copy(alpha = 0.15f),
    onSecondaryContainer = ToolBoxColors.Purple,
    tertiary            = ToolBoxColors.Green,
    onTertiary          = ToolBoxColors.LightTextOnPrimary,
    tertiaryContainer   = ToolBoxColors.Green.copy(alpha = 0.15f),
    onTertiaryContainer = ToolBoxColors.Green,
    error               = ToolBoxColors.Red,
    onError             = ToolBoxColors.LightTextOnPrimary,
    errorContainer      = ToolBoxColors.LightErrorContainer,
    onErrorContainer    = ToolBoxColors.Red,
    background          = ToolBoxColors.LightBackground,
    onBackground        = ToolBoxColors.LightTextPrimary,
    surface             = ToolBoxColors.LightSurface,
    onSurface           = ToolBoxColors.LightTextPrimary,
    surfaceVariant      = ToolBoxColors.LightSurfaceVariant,
    onSurfaceVariant    = ToolBoxColors.LightTextTertiary,
    outline             = ToolBoxColors.LightOutline,
    outlineVariant      = ToolBoxColors.LightOutlineVariant,
    inverseSurface      = ToolBoxColors.DarkSurface,
    inverseOnSurface    = ToolBoxColors.DarkTextPrimary,
    inversePrimary      = ToolBoxColors.Blue.copy(alpha = 0.7f),
    scrim               = ToolBoxColors.LightScrim,
)

private val DarkColorScheme = darkColorScheme(
    primary             = ToolBoxColors.Blue,
    onPrimary           = ToolBoxColors.DarkTextOnPrimary,
    primaryContainer    = ToolBoxColors.DarkSidebarSelected,
    onPrimaryContainer  = ToolBoxColors.Blue,
    secondary           = ToolBoxColors.Purple,
    onSecondary         = ToolBoxColors.DarkTextOnPrimary,
    secondaryContainer  = ToolBoxColors.Purple.copy(alpha = 0.25f),
    onSecondaryContainer = ToolBoxColors.Purple,
    tertiary            = ToolBoxColors.Green,
    onTertiary          = ToolBoxColors.DarkTextOnPrimary,
    tertiaryContainer   = ToolBoxColors.Green.copy(alpha = 0.25f),
    onTertiaryContainer = ToolBoxColors.Green,
    error               = ToolBoxColors.Red,
    onError             = ToolBoxColors.DarkTextOnPrimary,
    errorContainer      = ToolBoxColors.DarkErrorContainer,
    onErrorContainer    = ToolBoxColors.Red.copy(alpha = 0.9f),
    background          = ToolBoxColors.DarkBackground,
    onBackground        = ToolBoxColors.DarkTextPrimary,
    surface             = ToolBoxColors.DarkSurface,
    onSurface           = ToolBoxColors.DarkTextPrimary,
    surfaceVariant      = ToolBoxColors.DarkSurfaceVariant,
    onSurfaceVariant    = ToolBoxColors.DarkTextTertiary,
    outline             = ToolBoxColors.DarkOutline,
    outlineVariant      = ToolBoxColors.DarkOutlineVariant,
    inverseSurface      = ToolBoxColors.LightSurface,
    inverseOnSurface    = ToolBoxColors.LightTextPrimary,
    inversePrimary      = ToolBoxColors.Blue,
    scrim               = ToolBoxColors.DarkScrim,
)

/**
 * ToolBox 主题 —— 自动跟随系统深浅色模式。
 */
@Composable
fun ToolBoxTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme

    MaterialTheme(
        colorScheme = colorScheme,
        typography  = ToolBoxTypography,
        shapes      = ToolBoxShapes,
        content     = content
    )
}
