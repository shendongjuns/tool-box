package djshen.toolbox.common.theme

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * ToolBox 间距规范 —— 基于 8px 网格。
 */
object Spacing {

    /** 微间距（图标间隙等） */
    val xs: Dp = 4.dp

    /** 小间距（紧凑内容内边距） */
    val sm: Dp = 8.dp

    /** 内边距（组件/按钮内边距） */
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
