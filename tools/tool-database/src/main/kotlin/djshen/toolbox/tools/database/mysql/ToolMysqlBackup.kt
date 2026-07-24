package djshen.toolbox.tools.database.mysql

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
import djshen.toolbox.common.ToolBoxSettings
import djshen.toolbox.common.theme.Spacing
import djshen.toolbox.tools.database.core.*
import djshen.toolbox.tools.database.core.BackupCancellation
import djshen.toolbox.tools.database.shared.*
import djshen.toolbox.tools.database.ui.ConnectionDialog
import kotlinx.coroutines.*
import java.io.File

class ToolMysqlBackup : Tool {
    override val id = "tool-mysql-backup"; override val name = "MySQL 备份"
    override val description = "MySQL 数据库整体/库/表备份与恢复"; override val category = ToolCategory.DATABASE
    @Composable override fun Content() { MysqlBackupScreen() }
}

@Composable
private fun MysqlBackupScreen() {
    val mgr = remember { ConnectionManager() }; val client = remember { MySqlClient() }; val scope = rememberCoroutineScope()
    var configs by remember { mutableStateOf(mgr.loadConfigs().filter { it.dbType == "mysql" }) }
    var activeId by remember { mutableStateOf<String?>(null) }
    var connected by remember { mutableStateOf(false) }; var connecting by remember { mutableStateOf(false) }; var connError by remember { mutableStateOf("") }
    var showConnDialog by remember { mutableStateOf(false) }; var editing by remember { mutableStateOf<ConnectionConfig?>(null) }
    var databases by remember { mutableStateOf<List<String>>(emptyList()) }
    var tablesMap by remember { mutableStateOf<Map<String, List<String>>>(emptyMap()) }
    var mode by remember { mutableStateOf(0) }; var selDb by remember { mutableStateOf("") }
    var selTables by remember { mutableStateOf<Set<String>>(emptySet()) }
    var savePath by remember { mutableStateOf(File(System.getProperty("user.home"), "Desktop/mysql_dump.sql").absolutePath) }
    var taskCreated by remember { mutableStateOf(false) }
    var restoreFile by remember { mutableStateOf("") }

    fun connectTo(id: String) {
        val c = configs.find { it.id == id } ?: return
        activeId = id; connecting = true; connError = ""
        AppScope.launch {
            try {
                withContext(Dispatchers.IO) { client.connect(c) }
                connected = true; OperationLog.success("MySQL", "连接成功", "${c.host}:${c.port}")
                databases = withContext(Dispatchers.IO) { try { client.getDatabases() } catch (e: Exception) { emptyList<String>().also { connError = "获取数据库失败: ${e.message}" } } }
                tablesMap = databases.associateWith { db -> withContext(Dispatchers.IO) { try { client.getTables(db) } catch (_: Exception) { emptyList() } } }
            } catch (e: Exception) { connError = "连接失败: ${e.message}"; OperationLog.error("MySQL", "连接失败", e.message ?: "") }
            connecting = false
        }
    }

    Column(Modifier.fillMaxSize().padding(Spacing.page)) {
        Text("MySQL 备份/恢复", style = MaterialTheme.typography.headlineLarge, color = MaterialTheme.colorScheme.onSurface)
        Spacer(Modifier.height(Spacing.card))

        // 连接区
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
                                TextButton(onClick = { show = false; editing = c; showConnDialog = true }) { Icon(Icons.Default.Edit, null, Modifier.size(14.dp)) }
                                TextButton(onClick = { show = false; mgr.saveConfigsByType(configs.filter { it.id != c.id }, "mysql"); configs = mgr.loadConfigs().filter { it.dbType == "mysql" } }) { Icon(Icons.Default.Delete, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.error) }
                            }
                        }, onClick = { show = false; connectTo(c.id) })
                    }
                    HorizontalDivider(); DropdownMenuItem(text = { Text("新建连接") }, onClick = { show = false; editing = null; showConnDialog = true }, leadingIcon = { Icon(Icons.Default.Add, null, Modifier.size(16.dp)) })
                }
            }
            Button({ activeId?.let { connectTo(it) } }, enabled = !connecting && activeId != null && !connected, modifier = Modifier.height(36.dp)) {
                if (connecting) { CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary); Spacer(Modifier.width(Spacing.sm)) }
                Text(if (connected) "已连接" else "连接")
            }
            if (connError.isNotBlank()) Text(connError, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.error)
            if (connected) {
                Text(client.getVersion(), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                TextButton({ scope.launch(Dispatchers.IO) { client.close() }; connected = false; databases = emptyList() }) { Text("断开", color = MaterialTheme.colorScheme.error) }
            }
        }

        if (connected) {
            Spacer(Modifier.height(Spacing.section))
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                FilterChip(selected = mode == 0, onClick = { mode = 0; selDb = ""; selTables = emptySet() }, label = { Text("整体备份") })
                FilterChip(selected = mode == 1, onClick = { mode = 1; selTables = emptySet() }, label = { Text("指定库") })
                FilterChip(selected = mode == 2, onClick = { mode = 2; selTables = emptySet() }, label = { Text("指定表") })
            }
            Spacer(Modifier.height(Spacing.card))

            Row(Modifier.weight(1f).fillMaxHeight()) {
                Column(Modifier.width(260.dp).fillMaxHeight().background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)).padding(top = Spacing.sm)) {
                    when (mode) {
                        0 -> { Text("全部 ${databases.size} 个库", Modifier.padding(horizontal = Spacing.inner, vertical = Spacing.sm), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant); LazyColumn { items(databases) { db -> Text(db, Modifier.padding(horizontal = Spacing.inner + 16.dp, vertical = 2.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface) } } }
                        1, 2 -> {
                            val label = if (mode == 1) "选择数据库 (将备份全部表/视图/函数/存储过程)" else "选择数据库和表 (仅备份表结构和数据)"
                            Text(label, Modifier.padding(horizontal = Spacing.inner, vertical = Spacing.sm), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            LazyColumn {
                                items(databases) { db ->
                                    var expanded by remember { mutableStateOf(false) }
                                    Column {
                                        Row(Modifier.fillMaxWidth().clickable { selDb = db; expanded = !expanded; if (mode == 1) selTables = emptySet() }.padding(horizontal = Spacing.inner, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                                            RadioButton(db == selDb, { selDb = db; if (mode == 1) selTables = emptySet() }, Modifier.size(18.dp)); Spacer(Modifier.width(Spacing.sm))
                                            Text(db, style = MaterialTheme.typography.bodyMedium, color = if (db == selDb) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f))
                                        }
                                        if (expanded && db == selDb && mode == 2) {
                                            val tbls = tablesMap[db] ?: emptyList()
                                            Row(Modifier.clickable { selTables = if (selTables.size == tbls.size) emptySet() else tbls.toSet() }.padding(start = 48.dp, end = Spacing.inner, top = 2.dp, bottom = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                                                Checkbox(selTables.size == tbls.size && tbls.isNotEmpty(), { if (selTables.size == tbls.size) selTables = emptySet() else selTables = tbls.toSet() }, Modifier.size(18.dp)); Spacer(Modifier.width(Spacing.xs)); Text("全选 (${tbls.size})", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                            }
                                            tbls.forEach { t -> Row(Modifier.clickable { selTables = if (t in selTables) selTables - t else selTables + t }.padding(start = 48.dp, end = Spacing.inner, top = 1.dp, bottom = 1.dp), verticalAlignment = Alignment.CenterVertically) { Checkbox(t in selTables, { if (t in selTables) selTables = selTables - t else selTables = selTables + t }, Modifier.size(18.dp)); Spacer(Modifier.width(Spacing.xs)); Text(t, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface) } }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                VerticalDivider(Modifier.fillMaxHeight(), color = MaterialTheme.colorScheme.outlineVariant)

                Column(Modifier.weight(1f).padding(start = Spacing.inner)) {
                    OutlinedTextField(savePath, { savePath = it }, Modifier.fillMaxWidth(), singleLine = true, label = { Text("保存路径") })
                    Spacer(Modifier.height(Spacing.sm))

                    Button({
                        taskCreated = true
                        AppScope.launch {
                            BackupCancellation.reset()
                            val task = TaskManager.add("MySQL 备份: ${if (mode == 0) "全部" else selDb}", "MySQL 备份", coroutineContext[Job], onCancel = {
                                BackupCancellation.cancel(); client.currentProcess?.destroy()
                            })
                            OperationLog.info("MySQL", "开始备份", "${if (mode == 0) "全部数据库" else selDb}")
                            try {
                                withContext(Dispatchers.IO) {
                                    when {
                                        mode == 0 -> databases.forEach { db -> client.exportDatabase(db, savePath.replace(".sql", "_$db.sql")) { t, r -> task.progress.value = "$db.$t ($r 行)" } }
                                        mode == 1 && selDb.isNotBlank() -> client.exportDatabase(selDb, savePath) { t, r -> task.progress.value = "$t ($r 行)" }
                                        mode == 2 && selDb.isNotBlank() && selTables.isNotEmpty() -> exportTablesDirect(client, selDb, selTables, savePath) { task.progress.value = it }
                                    }
                                }
                                if (task.status.value != TaskStatus.CANCELLED) { task.status.value = TaskStatus.COMPLETED; task.message.value = "导出完成 (mysqldump)"; task.endTime.value = System.currentTimeMillis() }
                            } catch (e: Exception) {
                                if (task.status.value == TaskStatus.CANCELLED) return@launch
                                task.status.value = TaskStatus.FAILED; task.message.value = e.message ?: ""
                            } finally { task.endTime.value = System.currentTimeMillis() }
                        }
                    }, enabled = (mode == 0 || (mode == 1 && selDb.isNotBlank()) || (mode == 2 && selDb.isNotBlank() && selTables.isNotEmpty()))) {
                        Icon(Icons.Default.FileDownload, null, Modifier.size(16.dp)); Spacer(Modifier.width(Spacing.sm)); Text("备份")
                    }
                    if (taskCreated) {
                        Spacer(Modifier.height(Spacing.sm))
                        Text("任务已生成，请在「任务列表」中查看进度或停止", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                    }

                    Spacer(Modifier.height(Spacing.section)); HorizontalDivider(); Spacer(Modifier.height(Spacing.section))
                    Text("从 SQL 文件恢复", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(Spacing.sm))
                    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
                        OutlinedButton({ val d = java.awt.FileDialog(java.awt.Frame(), "SQL 文件", java.awt.FileDialog.LOAD); d.isVisible = true; if (d.file != null) restoreFile = File(d.directory, d.file).absolutePath }) { Text("选择 SQL 文件") }
                        if (restoreFile.isNotBlank()) Text(File(restoreFile).name, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    if (restoreFile.isNotBlank()) {
                        Spacer(Modifier.height(Spacing.sm))
                        var importCreated by remember { mutableStateOf(false) }
                        Button({
                            val task = TaskManager.add("MySQL 导入: ${File(restoreFile).name}", "MySQL 备份")
                            OperationLog.info("MySQL", "开始导入", File(restoreFile).name)
                            AppScope.launch {
                                try { withContext(Dispatchers.IO) { client.executeScript(File(restoreFile).readText()) }; task.status.value = TaskStatus.COMPLETED; task.message.value = "恢复完成"; OperationLog.success("MySQL", "导入完成", File(restoreFile).name) }
                                catch (e: Exception) { task.status.value = TaskStatus.FAILED; task.message.value = e.message ?: ""; OperationLog.error("MySQL", "导入失败", e.message ?: "") }
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
        ConnectionDialog(editing, client,
            onSave = { c ->
                val u = c.copy(dbType = "mysql", group = "MySQL")
                configs = if (editing != null) configs.map { if (it.id == u.id) u else it } else configs + u
                mgr.saveConfigsByType(configs, "mysql"); showConnDialog = false; editing = null
                if (!connected) connectTo(u.id)
            }, onDismiss = { showConnDialog = false; editing = null })
    }
}

private fun exportTablesDirect(client: MySqlClient, db: String, tables: Set<String>, path: String, onProgress: (String) -> Unit) {
    val file = File(path); file.parentFile?.mkdirs()
    file.bufferedWriter().use { w ->
        w.write("-- MySQL Dump - Tables\n-- Database: `$db`\n-- Tables: ${tables.joinToString()}\n-- ${java.time.LocalDateTime.now()}\n\n")
        w.write("CREATE DATABASE IF NOT EXISTS `$db`;\nUSE `$db`;\n\n")
        tables.forEach { table ->
            client.executeQuery("SHOW CREATE TABLE `$db`.`$table`").let { r -> if (!r.isError && r.rows.isNotEmpty()) { w.write("DROP TABLE IF EXISTS `$table`;\n${r.rows[0][1]};\n\n") } }
            val cntResult = client.executeQuery("SELECT COUNT(*) FROM `$db`.`$table`")
            val realTotal = if (!cntResult.isError && cntResult.rows.isNotEmpty()) (cntResult.rows[0][0] as? Number)?.toLong() ?: 0 else 0
            if (realTotal > 0) {
                val colsResult = client.executeQuery("SELECT * FROM `$db`.`$table` LIMIT 1")
                val cols = if (!colsResult.isError) colsResult.columns.joinToString(", ") { "`$it`" } else ""
                val b = 20000; var o = 0L; var rows = 0
                while (o < realTotal) {
                    val d = client.executeQuery("SELECT * FROM `$db`.`$table` LIMIT $o, $b")
                    if (!d.isError && d.rows.isNotEmpty()) { d.rows.forEach { row -> val vals = row.joinToString(", ") { v -> when(v){null->"NULL";is Number->v.toString();else->"'${v.toString().replace("'","''")}'"}}; w.write("INSERT INTO `$table` ($cols) VALUES ($vals);\n"); rows++ } }
                    o += b; w.flush()
                }
                onProgress("$table ($rows 行)")
            } else { w.write("-- Table `$table` is empty\n"); onProgress("$table (0 行)") }
            w.write("\n")
        }
    }
}
