package djshen.toolbox.framework.navigation

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import djshen.toolbox.api.Tool
import djshen.toolbox.common.theme.Spacing

@Composable
fun ContentArea(
    tool: Tool?,
    allTools: List<Tool>,
    sidebarExpanded: Boolean,
    onToggleSidebar: () -> Unit
) {
    // 只保持最近使用的 2 个工具在组合中，平衡状态保留与内存占用
    val lastTwo = remember { mutableListOf<Tool?>(null, null) }
    if (tool != null && tool != lastTwo[0]) {
        lastTwo[1] = lastTwo[0]
        lastTwo[0] = tool
    }

    Column(
        modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface)
    ) {
        if (!sidebarExpanded) {
            Row(Modifier.fillMaxWidth().padding(horizontal = Spacing.sm, vertical = Spacing.xs),
                verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onToggleSidebar) {
                    Icon(Icons.Default.Menu, "展开侧边栏", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }

        Box(modifier = Modifier.fillMaxSize()) {
            // 只渲染最近使用的 2 个工具（当前 + 上一个），减少内存
            lastTwo.filterNotNull().forEach { t ->
                val active = t == tool
                Box(
                    modifier = if (active) Modifier.fillMaxSize()
                    else Modifier.size(0.dp)
                ) {
                    key(t.id) { t.Content() }
                }
            }
            if (tool == null) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("ToolBox", style = MaterialTheme.typography.headlineLarge, color = MaterialTheme.colorScheme.onSurface)
                        Text("从侧边栏选择一个工具开始", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}
