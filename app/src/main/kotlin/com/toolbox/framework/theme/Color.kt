package com.toolbox.framework.theme

import androidx.compose.ui.graphics.Color

/**
 * ToolBox 色彩体系 —— 借鉴 Apple 设计语言，克制、清晰。
 *
 * 层级说明：
 * - Primary      → 交互色（按钮、选中态、链接）
 * - Functional   → 功能区分（每个工具分类一个主色）
 * - Surface      → 表面层级（卡片白 → 背景灰 → 分割线）
 * - Text         → 文字层级（标题深 → 正文中 → 辅助浅）
 */
object ToolBoxColors {

    // ═══ 主色调 ═══
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

    // ═══ 表面层级（浅色主题） ═══
    /** 卡片 / 内容区背景 */
    val Surface         = Color(0xFFFFFFFF)
    /** 页面 / 侧边栏背景 */
    val SurfaceVariant  = Color(0xFFF2F2F7)
    /** 分割线 / 边框 */
    val Outline         = Color(0xFFE5E5EA)
    /** 侧边栏选中态高亮 */
    val SidebarSelected = Color(0x1A007AFF)  // 蓝色 10% 透明度
    /** 悬停高亮 */
    val Hover           = Color(0x0D000000)  // 黑色 5% 透明度

    // ═══ 文字层级 ═══
    /** 标题 / 强调文字 */
    val TextPrimary   = Color(0xFF1C1C1E)
    /** 正文 */
    val TextSecondary = Color(0xFF3A3A3C)
    /** 辅助说明 / 占位符 */
    val TextTertiary  = Color(0xFF8E8E93)
    /** 反白文字（深色背景上使用） */
    val TextOnPrimary = Color(0xFFFFFFFF)
}
