package com.toolbox.common.theme

import androidx.compose.ui.graphics.Color

/**
 * ToolBox 色彩体系 —— 借鉴 Apple 设计语言，克制、清晰。
 *
 * 层级说明：
 * - Primary      → 交互色（按钮、选中态、链接）
 * - Functional   → 功能区分（每个工具分类一个主色）
 * - Surface      → 表面层级（卡片白 → 背景灰 → 分割线）
 * - Text         → 文字层级（标题深 → 正文中 → 辅助浅）
 *
 * 所有颜色均提供浅色 / 深色两种值。
 */
object ToolBoxColors {

    // ═══ 主色调（深浅通用） ═══
    val Blue   = Color(0xFF007AFF)
    val Purple = Color(0xFF5856D6)
    val Green  = Color(0xFF34C759)
    val Orange = Color(0xFFFF9500)
    val Red    = Color(0xFFFF3B30)

    // ═══ 功能色（对应 ToolCategory） ═══
    val CategoryData   = Blue
    val CategoryText   = Green
    val CategoryEncode = Purple
    val CategorySystem = Orange
    val CategoryOther  = Color(0xFF8E8E93)

    // ═══ 浅色主题 ═══
    val LightSurface            = Color(0xFFFFFFFF)
    val LightSurfaceVariant     = Color(0xFFF2F2F7)
    val LightOutline            = Color(0xFFE5E5EA)
    val LightOutlineVariant     = Color(0xFFD1D1D6)
    val LightSidebarSelected    = Color(0x1A007AFF)
    val LightHover              = Color(0x0D000000)
    val LightTextPrimary        = Color(0xFF1C1C1E)
    val LightTextSecondary      = Color(0xFF3A3A3C)
    val LightTextTertiary       = Color(0xFF8E8E93)
    val LightTextOnPrimary      = Color(0xFFFFFFFF)
    val LightBackground         = Color(0xFFFFFFFF)
    val LightErrorContainer      = Color(0xFFFFD7D7)
    val LightScrim              = Color(0x33000000)

    // ═══ 深色主题 ═══
    val DarkSurface             = Color(0xFF1C1C1E)
    val DarkSurfaceVariant      = Color(0xFF2C2C2E)
    val DarkOutline             = Color(0xFF48484A)
    val DarkOutlineVariant      = Color(0xFF3A3A3C)
    val DarkSidebarSelected     = Color(0x33007AFF)
    val DarkHover               = Color(0x1AFFFFFF)
    val DarkTextPrimary         = Color(0xFFFFFFFF)
    val DarkTextSecondary       = Color(0xFFAEAEB2)
    val DarkTextTertiary        = Color(0xFF636366)
    val DarkTextOnPrimary       = Color(0xFFFFFFFF)
    val DarkBackground          = Color(0xFF000000)
    val DarkErrorContainer      = Color(0xFF4A1C1C)
    val DarkScrim              = Color(0x55000000)

    // ═══ 向后兼容别名（指向浅色主题，渐进迁移到 MaterialTheme） ═══
    @Deprecated("使用 MaterialTheme.colorScheme.surface 替代", ReplaceWith("MaterialTheme.colorScheme.surface"))
    val Surface         = LightSurface
    @Deprecated("使用 MaterialTheme.colorScheme.surfaceVariant 替代")
    val SurfaceVariant  = LightSurfaceVariant
    @Deprecated("使用 MaterialTheme.colorScheme.outline 替代")
    val Outline         = LightOutline
    @Deprecated("使用 MaterialTheme.colorScheme.outlineVariant 替代")
    val OutlineVariant  = LightOutlineVariant
    @Deprecated("使用 MaterialTheme.colorScheme.primary.copy(alpha=0.1f) 替代")
    val SidebarSelected = LightSidebarSelected
    @Deprecated("使用 MaterialTheme.colorScheme.onSurface.copy(alpha=0.05f) 替代")
    val Hover           = LightHover
    @Deprecated("使用 MaterialTheme.colorScheme.onSurface 替代")
    val TextPrimary   = LightTextPrimary
    @Deprecated("使用 MaterialTheme.colorScheme.onSurfaceVariant 替代")
    val TextSecondary = LightTextSecondary
    @Deprecated("使用 MaterialTheme.colorScheme.outlineVariant 替代")
    val TextTertiary  = LightTextTertiary
    @Deprecated("使用 MaterialTheme.colorScheme.onPrimary 替代")
    val TextOnPrimary = LightTextOnPrimary
}
