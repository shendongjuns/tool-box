package com.toolbox.framework.theme

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * ToolBox 间距规范 —— 基于 8px 网格。
 *
 * - 组件内边距   16.dp
 * - 卡片间距     16.dp
 * - 区域间距     24.dp
 * - 页面边距     32.dp
 * - 图标大小     20.dp（导航）、16.dp（操作）
 */
object Spacing {

    /** 组件内边距（按钮/输入框内边距） */
    val inner: Dp = 16.dp

    /** 卡片间距 */
    val card: Dp = 16.dp

    /** 区域 / 分组间距 */
    val section: Dp = 24.dp

    /** 页面边距 */
    val page: Dp = 32.dp

    /** 导航图标大小 */
    val navIcon: Dp = 20.dp

    /** 操作图标大小 */
    val actionIcon: Dp = 16.dp

    /** 侧边栏宽度 */
    val sidebarWidth: Dp = 240.dp
}
