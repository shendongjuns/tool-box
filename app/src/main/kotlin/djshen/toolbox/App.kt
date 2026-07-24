package djshen.toolbox

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import djshen.toolbox.common.ToolBoxSettings
import djshen.toolbox.framework.navigation.ContentArea
import djshen.toolbox.framework.navigation.NavigationState
import djshen.toolbox.framework.navigation.Sidebar
import djshen.toolbox.framework.plugin.ToolLoader
import djshen.toolbox.common.theme.ToolBoxTheme

/**
 * 应用根 Composable —— 加载工具、管理导航状态、渲染框架布局。
 */
@Composable
fun App() {
    // 加载全局设置
    LaunchedEffect(Unit) { ToolBoxSettings.load() }
    val tools = remember { ToolLoader.load() }
    val navState = remember { NavigationState().apply {
        // 默认选中第一个工具
        selectedTool = tools.values.flatten().firstOrNull()
    } }

    // 工具生命周期回调 —— 选中/取消选中时通知工具
    val currentTool = navState.selectedTool
    DisposableEffect(currentTool) {
        currentTool?.onSelected()
        onDispose { currentTool?.onDeselected() }
    }

    ToolBoxTheme {
        Row(modifier = Modifier.fillMaxSize()) {
            Sidebar(
                groupedTools = tools,
                selectedTool = navState.selectedTool,
                onToolSelect = { navState.selectTool(it) },
                expanded = navState.sidebarExpanded,
                onToggle = { navState.toggleSidebar() }
            )
            ContentArea(
                tool = navState.selectedTool,
                allTools = tools.values.flatten(),
                sidebarExpanded = navState.sidebarExpanded,
                onToggleSidebar = { navState.toggleSidebar() }
            )
        }
    }
}
