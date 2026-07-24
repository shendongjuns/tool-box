package djshen.toolbox.tools.database.discovery

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
import djshen.toolbox.common.theme.ToolBoxShapes
import djshen.toolbox.tools.database.shared.OperationLog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class ToolDatabaseDiscovery : Tool {
    override val id = "tool-db-discovery"
    override val name = "数据库发现"
    override val description = "扫描 IP 地址，发现已暴露的数据库端口和服务"
    override val category = ToolCategory.DATABASE
    @Composable override fun Content() { DiscoveryScreen() }
}

@Composable
private fun DiscoveryScreen() {
    var host by remember { mutableStateOf("127.0.0.1") }
    var timeout by remember { mutableStateOf("1000") }
    var scanning by remember { mutableStateOf(false) }
    var progress by remember { mutableStateOf(0 to 0) }
    var results by remember { mutableStateOf<List<ScanResult>>(emptyList()) }
    val scope = rememberCoroutineScope()

    Column(Modifier.fillMaxSize().padding(Spacing.page)) {
        Text("数据库发现扫描器", style = MaterialTheme.typography.headlineLarge, color = MaterialTheme.colorScheme.onSurface)
        Spacer(Modifier.height(Spacing.sm))
        Text("扫描目标 IP 的常见数据库端口，识别服务类型和版本", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(Spacing.section))

        // 输入区
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(host, { host = it }, Modifier.weight(2f), singleLine = true, label = { Text("IP 地址") })
            OutlinedTextField(timeout, { timeout = it.filter { it.isDigit() } }, Modifier.weight(1f), singleLine = true, label = { Text("超时(ms)") })
            Button({
                scope.launch {
                    scanning = true; results = emptyList()
                    OperationLog.info("发现扫描", "开始扫描", host)
                    results = withContext(Dispatchers.IO) {
                        PortScanner.scan(host, timeout.toIntOrNull() ?: 2000) { cur, total -> progress = cur to total }
                    }
                    scanning = false
                    val open = results.count { it.open }
                    OperationLog.success("发现扫描", "扫描完成", "$host → $open/${results.size} 端口开放")
                }
            }, enabled = host.isNotBlank() && !scanning, modifier = Modifier.height(56.dp)) {
                if (scanning) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
                else { Icon(Icons.Default.Search, null, Modifier.size(18.dp)); Spacer(Modifier.width(Spacing.sm)) }
                Text(if (scanning) "扫描中…" else "扫描")
            }
        }

        if (scanning) {
            Spacer(Modifier.height(Spacing.sm))
            LinearProgressIndicator(Modifier.fillMaxWidth())
            Text("扫描中 ${progress.first}/${progress.second}…", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }

        Spacer(Modifier.height(Spacing.section))

        // 扫描结果表格
        if (results.isNotEmpty()) {
            Text("扫描结果 (${results.filter { it.open }.size} 个开放)", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurface)
            Spacer(Modifier.height(Spacing.sm))

            // 表头
            Row(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)).padding(horizontal = Spacing.inner, vertical = Spacing.sm)) {
                Text("端口", Modifier.width(70.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("数据库类型", Modifier.weight(1f), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("版本", Modifier.weight(1.5f), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("状态", Modifier.width(60.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("延迟", Modifier.width(60.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

            LazyColumn {
                items(results) { r ->
                    Row(Modifier.fillMaxWidth()
                        .background(if (r.open) MaterialTheme.colorScheme.surface else MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.3f))
                        .padding(horizontal = Spacing.inner, vertical = Spacing.sm)) {
                        Text(r.port.toString(), Modifier.width(70.dp), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface)
                        Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                            // 数据库类型图标
                            val icon = when { r.dbType.contains("MySQL") -> Icons.Default.Storage; r.dbType.contains("ClickHouse") -> Icons.Default.TableChart; r.dbType.contains("Redis") -> Icons.Default.Memory; r.dbType.contains("Mongo") -> Icons.Default.Layers; r.dbType.contains("PostgreSQL") -> Icons.Default.Dns; r.dbType.contains("Elastic") -> Icons.Default.Search; r.dbType.contains("Oracle") -> Icons.Default.AccountTree; else -> Icons.Default.Lan }
                            Icon(icon, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                            Spacer(Modifier.width(Spacing.sm))
                            Text(r.dbType, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface)
                        }
                        Text(if (r.version.isNotBlank()) r.version else "-", Modifier.weight(1.5f), style = MaterialTheme.typography.bodySmall.copy(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Surface(shape = ToolBoxShapes.small, color = if (r.open) MaterialTheme.colorScheme.primary.copy(alpha = 0.1f) else MaterialTheme.colorScheme.error.copy(alpha = 0.1f)) {
                            Text(if (r.open) "开放" else "超时", Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                                style = MaterialTheme.typography.labelSmall,
                                color = if (r.open) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error)
                        }
                        Spacer(Modifier.width(Spacing.sm))
                        Text(if (r.open) "${r.latencyMs}ms" else "-", Modifier.width(60.dp), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}
