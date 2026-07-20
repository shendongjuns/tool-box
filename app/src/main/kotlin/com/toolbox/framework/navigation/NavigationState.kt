package com.toolbox.framework.navigation

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.toolbox.api.Tool

/**
 * 导航状态 —— 管理侧边栏选中项、展开/折叠状态。
 */
class NavigationState {

    /** 当前选中的工具（null 表示无工具/占位状态） */
    var selectedTool: Tool? by mutableStateOf(null)

    /** 侧边栏是否展开 */
    var sidebarExpanded: Boolean by mutableStateOf(true)

    /** 选中工具，同时自动展开侧边栏 */
    fun selectTool(tool: Tool) {
        selectedTool = tool
        sidebarExpanded = true
    }

    /** 切换侧边栏展开/折叠 */
    fun toggleSidebar() {
        sidebarExpanded = !sidebarExpanded
    }
}
