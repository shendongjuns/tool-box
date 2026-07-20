package com.toolbox

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.toolbox.framework.navigation.ContentArea
import com.toolbox.framework.navigation.NavigationState
import com.toolbox.framework.navigation.Sidebar
import com.toolbox.framework.plugin.ToolLoader
import com.toolbox.common.theme.ToolBoxTheme

/**
 * 应用根 Composable —— 加载工具、管理导航状态、渲染框架布局。
 */
@Composable
fun App() {
    val tools = remember { ToolLoader.load() }
    val navState = remember { NavigationState().apply {
        // 默认选中第一个工具
        selectedTool = tools.values.flatten().firstOrNull()
    } }

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
                sidebarExpanded = navState.sidebarExpanded,
                onToggleSidebar = { navState.toggleSidebar() }
            )
        }
    }
}
