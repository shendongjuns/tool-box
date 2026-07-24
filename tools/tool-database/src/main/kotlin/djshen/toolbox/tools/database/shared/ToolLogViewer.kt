package djshen.toolbox.tools.database.shared

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import djshen.toolbox.api.Tool
import djshen.toolbox.api.ToolCategory
import djshen.toolbox.common.theme.Spacing

class ToolLogViewer : Tool {
    override val id = "tool-log-viewer"; override val name = "操作日志"
    override val description = "查看系统操作日志"; override val category = ToolCategory.OTHER
    @Composable override fun Content() { LogViewerScreen() }
}

@Composable
private fun LogViewerScreen() {
    val logs = OperationLog.entries
    Column(Modifier.fillMaxSize().padding(Spacing.page)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text("操作日志", style = MaterialTheme.typography.headlineLarge, color = MaterialTheme.colorScheme.onSurface)
            TextButton(onClick = { logs.clear() }) { Text("清空") }
        }
        Spacer(Modifier.height(Spacing.card))
        LazyColumn {
            items(logs.toList()) { entry ->
                Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(entry.time, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f), modifier = Modifier.width(64.dp))
                    Spacer(Modifier.width(Spacing.sm))
                    val icon = when(entry.level){LogLevel.INFO->Icons.Default.Info;LogLevel.SUCCESS->Icons.Default.CheckCircle;LogLevel.WARN->Icons.Default.Warning;LogLevel.ERROR->Icons.Default.Error}
                    val tint = when(entry.level){LogLevel.INFO->MaterialTheme.colorScheme.onSurfaceVariant;LogLevel.SUCCESS->MaterialTheme.colorScheme.primary;LogLevel.WARN->MaterialTheme.colorScheme.tertiary;LogLevel.ERROR->MaterialTheme.colorScheme.error}
                    Icon(icon, null, Modifier.size(14.dp), tint = tint)
                    Spacer(Modifier.width(Spacing.sm))
                    Column(Modifier.weight(1f)) {
                        Text("[${entry.tool}] ${entry.action}", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurface)
                        if (entry.detail.isNotBlank()) Text(entry.detail, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f))
                    }
                }
            }
        }
    }
}
