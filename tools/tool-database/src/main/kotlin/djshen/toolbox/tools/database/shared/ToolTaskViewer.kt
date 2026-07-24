package djshen.toolbox.tools.database.shared

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
import kotlinx.coroutines.delay

class ToolTaskViewer : Tool {
    override val id = "tool-task-viewer"; override val name = "任务列表"
    override val description = "查看所有后台任务（备份、导入等）"; override val category = ToolCategory.OTHER
    @Composable override fun Content() { TaskViewerScreen() }
}

@Composable
private fun TaskViewerScreen() {
    val tasks = TaskManager.tasks
    var tick by remember { mutableStateOf(0) }
    LaunchedEffect(Unit) { while (true) { delay(1000); tick++ } }
    tick // 订阅状态变化以触发重组
    val grouped = remember(tasks.toList()) { tasks.groupBy { it.tool } }

    Column(Modifier.fillMaxSize().padding(Spacing.page)) {
        Text("任务列表", style = MaterialTheme.typography.headlineLarge, color = MaterialTheme.colorScheme.onSurface)
        Spacer(Modifier.height(Spacing.sm))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("${tasks.size} 个任务", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            TextButton(onClick = { TaskManager.clearCompleted() }) { Text("清除已完成") }
        }
        Spacer(Modifier.height(Spacing.card))

        if (tasks.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("暂无任务", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f))
            }
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                grouped.forEach { (tool, list) ->
                    item(key = "h-$tool") {
                        Text("$tool (${list.size})", style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
                    }
                    items(list, key = { it.id }) { task ->
                        Card(Modifier.fillMaxWidth()) {
                            Column(Modifier.padding(Spacing.inner)) {
                                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Icon(when(task.status.value){TaskStatus.RUNNING->Icons.Default.HourglassTop;TaskStatus.COMPLETED->Icons.Default.CheckCircle;TaskStatus.FAILED->Icons.Default.Error;TaskStatus.CANCELLED->Icons.Default.Cancel},null,Modifier.size(18.dp),
                                            tint=when(task.status.value){TaskStatus.RUNNING->MaterialTheme.colorScheme.primary;TaskStatus.COMPLETED->MaterialTheme.colorScheme.primary;TaskStatus.FAILED->MaterialTheme.colorScheme.error;TaskStatus.CANCELLED->MaterialTheme.colorScheme.onSurfaceVariant})
                                        Spacer(Modifier.width(Spacing.sm))
                                        Text(task.name, style = MaterialTheme.typography.bodyMedium)
                                    }
                                    Text(formatDuration(task), style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Spacer(Modifier.width(Spacing.sm))
                                    Text(task.status.value.name, style = MaterialTheme.typography.labelSmall,
                                        color = when(task.status.value){TaskStatus.RUNNING->MaterialTheme.colorScheme.primary;TaskStatus.COMPLETED->MaterialTheme.colorScheme.onSurfaceVariant;else->MaterialTheme.colorScheme.error})
                                }
                                if (task.progress.value.isNotBlank()) {
                                    Text(task.progress.value, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                if (task.status.value == TaskStatus.RUNNING) {
                                    Spacer(Modifier.height(Spacing.xs))
                                    if (task.total.value > 0) LinearProgressIndicator((task.current.value.toFloat()/task.total.value).coerceIn(0f,1f), Modifier.fillMaxWidth())
                                    else LinearProgressIndicator(Modifier.fillMaxWidth())
                                }
                                if (task.message.value.isNotBlank()) {
                                    Text(task.message.value, style = MaterialTheme.typography.bodySmall, color = if (task.message.value.startsWith("✅")) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error)
                                }
                                if (task.status.value == TaskStatus.RUNNING) {
                                    TextButton(onClick = { TaskManager.stop(task) }, Modifier.align(Alignment.End),
                                        colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text("停止") }
                                } else {
                                    TextButton(onClick = { TaskManager.remove(task) }, Modifier.align(Alignment.End)) { Text("关闭") }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
