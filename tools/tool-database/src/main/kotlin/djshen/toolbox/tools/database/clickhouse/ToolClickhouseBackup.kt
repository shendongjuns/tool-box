package djshen.toolbox.tools.database.clickhouse

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
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
import djshen.toolbox.tools.database.core.*
import djshen.toolbox.tools.database.core.BackupCancellation
import djshen.toolbox.tools.database.shared.*
import kotlinx.coroutines.*
import java.io.File

class ToolClickhouseBackup : Tool {
    override val id = "tool-ck-backup"; override val name = "ClickHouse 备份"
    override val description = "ClickHouse 数据库整体/库备份与恢复"; override val category = ToolCategory.DATABASE
    @Composable override fun Content() { CkBackupScreen() }
}

@Composable
private fun CkBackupScreen() {
    val mgr = remember { ConnectionManager() }; val client = remember { ClickHouseClient() }; val scope = rememberCoroutineScope()
    var configs by remember { mutableStateOf(mgr.loadConfigs().filter { it.dbType == "clickhouse" }) }
    var activeId by remember { mutableStateOf<String?>(null) }
    var connected by remember { mutableStateOf(false) }; var connecting by remember { mutableStateOf(false) }
    var connError by remember { mutableStateOf("") }
    var databases by remember { mutableStateOf<List<String>>(emptyList()) }
    var tablesMap by remember { mutableStateOf<Map<String, List<String>>>(emptyMap()) }
    var mode by remember { mutableStateOf(0) }; var selDb by remember { mutableStateOf("") }
    var showConnDialog by remember { mutableStateOf(false) }; var editing by remember { mutableStateOf<ConnectionConfig?>(null) }
    var host by remember { mutableStateOf("127.0.0.1") }; var port by remember { mutableStateOf("8123") }
    var user by remember { mutableStateOf("default") }; var password by remember { mutableStateOf("") }; var connName by remember { mutableStateOf("") }
    var savePath by remember { mutableStateOf(File(System.getProperty("user.home"), "Desktop/clickhouse_dump.sql").absolutePath) }
    var taskCreated by remember { mutableStateOf(false) }
    var restoreFile by remember { mutableStateOf("") }

    fun connect(cfg: ConnectionConfig) {
        activeId = cfg.id; connecting = true; connError = ""
        AppScope.launch {
            try {
                client.connect(cfg)
                val ok = withContext(Dispatchers.IO) { client.testConnection(cfg) }
                if (ok == null) { connError = "连接失败"; connecting = false; return@launch }
                connected = true; OperationLog.success("ClickHouse", "连接成功", "${cfg.host}:${cfg.port}")
                databases = withContext(Dispatchers.IO) { try { client.getDatabases() } catch (_: Exception) { emptyList() } }
                tablesMap = databases.associateWith { db -> withContext(Dispatchers.IO) { try { client.getTables(db) } catch (_: Exception) { emptyList() } } }
            } catch (e: Exception) { connError = "连接失败: ${e.message}"; OperationLog.error("ClickHouse", "连接失败", e.message ?: "") }
            connecting = false
        }
    }

    Column(Modifier.fillMaxSize().padding(Spacing.page)) {
        Text("ClickHouse 备份/恢复", style = MaterialTheme.typography.headlineLarge, color = MaterialTheme.colorScheme.onSurface)
        Spacer(Modifier.height(Spacing.card))

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
            Box {
                var show by remember { mutableStateOf(false) }
                OutlinedButton({ show = true }, Modifier.height(36.dp)) {
                    Icon(Icons.Default.Storage, null, Modifier.size(16.dp)); Spacer(Modifier.width(Spacing.sm))
                    Text(configs.find { it.id == activeId }?.name ?: "选择连接", maxLines = 1); Icon(Icons.Default.ArrowDropDown, null, Modifier.size(16.dp))
                }
                DropdownMenu(show, { show = false }) {
                    configs.forEach { c ->
                        DropdownMenuItem(text = {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(c.name); Spacer(Modifier.weight(1f))
                                TextButton(onClick = { show = false; editing = c; host = c.host; port = c.port.toString(); user = c.username; password = c.password; connName = c.name; showConnDialog = true }) { Icon(Icons.Default.Edit, null, Modifier.size(14.dp)) }
                                TextButton(onClick = { show = false; mgr.saveConfigsByType(configs.filter { it.id != c.id }, "clickhouse"); configs = mgr.loadConfigs().filter { it.dbType == "clickhouse" } }) { Icon(Icons.Default.Delete, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.error) }
                            }
                        }, onClick = { show = false; connect(c) })
                    }; HorizontalDivider()
                    DropdownMenuItem(text = { Text("新建连接") }, onClick = { show = false; editing = null; host = "127.0.0.1"; port = "8123"; user = "default"; password = ""; connName = ""; showConnDialog = true }, leadingIcon = { Icon(Icons.Default.Add, null, Modifier.size(16.dp)) })
                }
            }
            if (connected) {
                Button({ client.close(); connected = false; databases = emptyList(); activeId = null }, modifier = Modifier.height(36.dp), colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)) { Text("断开") }
            }
            if (connError.isNotBlank()) Text(connError, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.error)
            if (connected) Text("已连接", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
        }

        if (connected) {
            Spacer(Modifier.height(Spacing.section))
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                FilterChip(selected = mode == 0, onClick = { mode = 0; selDb = "" }, label = { Text("整体备份") })
                FilterChip(selected = mode == 1, onClick = { mode = 1 }, label = { Text("指定库") })
            }
            Spacer(Modifier.height(Spacing.card))

            Row(Modifier.weight(1f).fillMaxHeight()) {
                Column(Modifier.width(260.dp).fillMaxHeight().background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)).padding(top = Spacing.sm)) {
                    when (mode) {
                        0 -> { Text("全部 ${databases.size} 个库", Modifier.padding(horizontal = Spacing.inner, vertical = Spacing.sm), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant); LazyColumn { items(databases) { db -> Text(db, Modifier.padding(horizontal = Spacing.inner + 16.dp, vertical = 2.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface) } } }
                        1 -> {
                            Text("选择数据库 (将备份全部内容)", Modifier.padding(horizontal = Spacing.inner, vertical = Spacing.sm), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            LazyColumn { items(databases) { db -> Row(Modifier.fillMaxWidth().clickable { selDb = db }.padding(horizontal = Spacing.inner, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) { RadioButton(db == selDb, { selDb = db }, Modifier.size(18.dp)); Spacer(Modifier.width(Spacing.sm)); Text(db, style = MaterialTheme.typography.bodyMedium, color = if (db == selDb) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface) } } }
                        }
                    }
                }
                VerticalDivider(Modifier.fillMaxHeight(), color = MaterialTheme.colorScheme.outlineVariant)
                Column(Modifier.weight(1f).padding(start = Spacing.inner)) {
                    OutlinedTextField(savePath, { savePath = it }, Modifier.fillMaxWidth(), singleLine = true, label = { Text("保存路径") })
                    Spacer(Modifier.height(Spacing.sm))

                    Button({
                        BackupCancellation.reset()
                        val task = TaskManager.add("CK 备份: ${if (mode == 0) "全部" else selDb}", "ClickHouse 备份", onCancel = { BackupCancellation.cancel() })
                        OperationLog.info("ClickHouse", "开始备份", "${if (mode == 0) "全部数据库" else selDb}")
                        AppScope.launch {
                            try {
                                withContext(Dispatchers.IO) {
                                    when {
                                        mode == 0 -> databases.forEach { db -> client.exportDatabase(db, savePath.replace(".sql", "_$db.sql")) { t, r -> task.progress.value = "$db.$t ($r 行)" } }
                                        mode == 1 && selDb.isNotBlank() -> client.exportDatabase(selDb, savePath) { t, r -> task.progress.value = "$t ($r 行)" }
                                    }
                                }
                                task.status.value = TaskStatus.COMPLETED; task.message.value = "导出完成"
                                OperationLog.success("ClickHouse", "备份完成", "${if (mode == 0) "全部数据库" else selDb}")
                            } catch (e: Exception) { task.status.value = TaskStatus.FAILED; task.message.value = e.message ?: ""; OperationLog.error("ClickHouse", "备份失败", e.message ?: "") }
                        }
                        taskCreated = true
                    }, enabled = (mode == 0 || selDb.isNotBlank())) {
                        Icon(Icons.Default.FileDownload, null, Modifier.size(16.dp)); Spacer(Modifier.width(Spacing.sm)); Text("备份")
                    }
                    if (taskCreated) { Spacer(Modifier.height(Spacing.sm)); Text("任务已生成，请在「任务列表」中查看进度或停止", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary) }

                    Spacer(Modifier.height(Spacing.section)); HorizontalDivider(); Spacer(Modifier.height(Spacing.section))
                    Text("从 SQL 文件恢复", style = MaterialTheme.typography.titleMedium); Spacer(Modifier.height(Spacing.sm))
                    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
                        OutlinedButton({ val d = java.awt.FileDialog(java.awt.Frame(), "SQL文件", java.awt.FileDialog.LOAD); d.isVisible = true; if (d.file != null) restoreFile = File(d.directory, d.file).absolutePath }) { Text("选择 SQL 文件") }
                        if (restoreFile.isNotBlank()) Text(File(restoreFile).name, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    if (restoreFile.isNotBlank()) {
                        Spacer(Modifier.height(Spacing.sm))
                        var importCreated by remember { mutableStateOf(false) }
                        Button({
                            val task = TaskManager.add("CK 导入: ${File(restoreFile).name}", "ClickHouse 备份")
                            OperationLog.info("ClickHouse", "开始导入", File(restoreFile).name)
                            AppScope.launch {
                                try { withContext(Dispatchers.IO) { client.importSql(restoreFile) { _, c -> task.progress.value = "已执行 $c 条" } }; task.status.value = TaskStatus.COMPLETED; task.message.value = "恢复完成"; OperationLog.success("ClickHouse", "导入完成", File(restoreFile).name) }
                                catch (e: Exception) { task.status.value = TaskStatus.FAILED; task.message.value = e.message ?: ""; OperationLog.error("ClickHouse", "导入失败", e.message ?: "") }
                            }
                            importCreated = true
                        }) { Text("执行恢复") }
                        if (importCreated) { Spacer(Modifier.height(Spacing.sm)); Text("任务已生成，请在「任务列表」中查看进度", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary) }
                    }
                }
            }
        }
    }

    if (showConnDialog) {
        AlertDialog(onDismissRequest = { showConnDialog = false }, title = { Text(if (editing != null) "编辑连接" else "新建连接") },
            text = {
                Column(Modifier.width(400.dp), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    OutlinedTextField(connName, { connName = it }, Modifier.fillMaxWidth(), singleLine = true, label = { Text("名称") })
                    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) { OutlinedTextField(host, { host = it }, Modifier.weight(2f), singleLine = true, label = { Text("主机") }); OutlinedTextField(port, { port = it }, Modifier.weight(1f), singleLine = true, label = { Text("端口") }) }
                    OutlinedTextField(user, { user = it }, Modifier.fillMaxWidth(), singleLine = true, label = { Text("用户名") })
                    OutlinedTextField(password, { password = it }, Modifier.fillMaxWidth(), singleLine = true, label = { Text("密码") })
                }
            },
            confirmButton = {
                Button({
                    val cfg = ConnectionConfig(id = editing?.id ?: java.util.UUID.randomUUID().toString(), name = connName.ifBlank { "$host:$port" }, dbType = "clickhouse", group = "ClickHouse", host = host, port = port.toIntOrNull() ?: 8123, username = user, password = password)
                    configs = if (editing != null) configs.map { if (it.id == cfg.id) cfg else it } else configs + cfg
                    mgr.saveConfigsByType(configs, "clickhouse"); showConnDialog = false; editing = null; connect(cfg)
                }) { Text("保存") }
            },
            dismissButton = { TextButton({ showConnDialog = false }) { Text("取消") } })
    }
}
