package com.toolbox.framework.navigation

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.toolbox.api.Tool
import com.toolbox.common.theme.ToolBoxColors

/**
 * 内容区域 —— 显示当前选中工具的界面。
 *
 * 如果未选中工具，显示欢迎/占位页面。
 */
@Composable
fun ContentArea(
    tool: Tool?,
    sidebarExpanded: Boolean,
    onToggleSidebar: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(ToolBoxColors.Surface)
    ) {
        // 顶部栏
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // 侧边栏折叠时显示展开按钮
            if (!sidebarExpanded) {
                IconButton(onClick = onToggleSidebar) {
                    Icon(
                        imageVector = Icons.Default.Menu,
                        contentDescription = "展开侧边栏",
                        tint = ToolBoxColors.TextSecondary
                    )
                }
            }
        }

        // 内容区域
        if (tool != null) {
            Box(modifier = Modifier.fillMaxSize().padding(32.dp)) {
                tool.Content()
            }
        } else {
            // 空状态 / 欢迎页
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        text = "ToolBox",
                        style = MaterialTheme.typography.headlineLarge,
                        color = ToolBoxColors.TextPrimary
                    )
                    Text(
                        text = "从侧边栏选择一个工具开始",
                        style = MaterialTheme.typography.bodyLarge,
                        color = ToolBoxColors.TextTertiary
                    )
                }
            }
        }
    }
}
