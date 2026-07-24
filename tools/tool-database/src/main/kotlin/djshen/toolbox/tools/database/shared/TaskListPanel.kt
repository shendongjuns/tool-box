package djshen.toolbox.tools.database.shared

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import kotlinx.coroutines.delay
import djshen.toolbox.common.theme.Spacing
import djshen.toolbox.common.theme.ToolBoxShapes

@Composable
fun TaskListPanel(modifier: Modifier = Modifier) {
    val tasks = TaskManager.tasks
    // 每秒更新运行中任务的耗时（必须读取 tick 才会触发重组）
    var tick by remember { mutableStateOf(0) }
    LaunchedEffect(Unit) { while (true) { delay(1000); tick++ } }
    tick  // 读取 tick 以订阅状态变化
    if (tasks.isEmpty()) return

    Column(modifier = modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.2f)).padding(Spacing.sm)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text("任务列表 (${tasks.size})", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            TextButton(onClick = { TaskManager.clearCompleted() }, contentPadding = PaddingValues(horizontal = Spacing.sm, vertical = 0.dp)) {
                Text("清除已完成", style = MaterialTheme.typography.labelSmall)
            }
        }
        Spacer(Modifier.height(Spacing.xs))
        tasks.forEach { task ->
            Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    when (task.status.value) {
                        TaskStatus.RUNNING -> Icons.Default.HourglassTop
                        TaskStatus.COMPLETED -> Icons.Default.CheckCircle
                        TaskStatus.FAILED -> Icons.Default.Error
                        TaskStatus.CANCELLED -> Icons.Default.Cancel
                    }, null, Modifier.size(14.dp),
                    tint = when (task.status.value) {
                        TaskStatus.RUNNING -> MaterialTheme.colorScheme.primary
                        TaskStatus.COMPLETED -> MaterialTheme.colorScheme.primary.copy(alpha = 0.7f)
                        TaskStatus.FAILED -> MaterialTheme.colorScheme.error
                        TaskStatus.CANCELLED -> MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                    }
                )
                Spacer(Modifier.width(Spacing.sm))
                Column(Modifier.weight(1f)) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(task.name, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurface)
                        Text(formatDuration(task), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f))
                    }
                    if (task.progress.value.isNotBlank()) Text(task.progress.value, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f))
                }
                if (task.status.value == TaskStatus.RUNNING) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        TextButton(onClick = { TaskManager.stop(task) }, contentPadding = PaddingValues(horizontal = Spacing.xs, vertical = 0.dp), modifier = Modifier.size(24.dp)) {
                            Icon(Icons.Default.Cancel, "停止", Modifier.size(14.dp), tint = MaterialTheme.colorScheme.error)
                        }
                        Column(Modifier.weight(1f).padding(end = Spacing.sm)) {
                        val fraction = if (task.total.value > 0) (task.current.value.toFloat() / task.total.value).coerceIn(0f, 1f) else -1f
                        if (fraction >= 0) {
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                LinearProgressIndicator(fraction, Modifier.weight(1f))
                                Spacer(Modifier.width(Spacing.sm))
                                Text("${(fraction * 100).toInt()}%", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                            }
                        } else {
                            LinearProgressIndicator(Modifier.fillMaxWidth())
                        }
                    }}
                } else {
                    TextButton(onClick = { TaskManager.remove(task) }, contentPadding = PaddingValues(0.dp), modifier = Modifier.size(20.dp)) {
                        Icon(Icons.Default.Close, "关闭", Modifier.size(12.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f))
                    }
                }
            }
        }
    }
}
