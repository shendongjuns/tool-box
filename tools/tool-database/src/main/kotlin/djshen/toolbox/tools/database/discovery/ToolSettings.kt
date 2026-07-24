package djshen.toolbox.tools.database.discovery

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import djshen.toolbox.api.Tool
import djshen.toolbox.api.ToolCategory
import djshen.toolbox.common.ToolBoxSettings
import djshen.toolbox.common.theme.Spacing
import java.io.File

class ToolSettings : Tool {
    override val id = "tool-settings"; override val name = "系统设置"
    override val description = "配置数据存储、mysqldump、备份性能"; override val category = ToolCategory.OTHER
    @Composable override fun Content() { SettingsScreen() }
}

@Composable
private fun SettingsScreen() {
    var dataDir by remember { mutableStateOf(ToolBoxSettings.dataDir) }
    var dumpPath by remember { mutableStateOf(ToolBoxSettings.mysqldumpPath) }
    var saved by remember { mutableStateOf(false) }
    // 加载持久化值
    LaunchedEffect(Unit) {
        ToolBoxSettings.load()
        dataDir = ToolBoxSettings.dataDir
        dumpPath = ToolBoxSettings.mysqldumpPath
    }

    Column(Modifier.fillMaxSize().padding(Spacing.page)) {
        Text("系统设置", style = MaterialTheme.typography.headlineLarge, color = MaterialTheme.colorScheme.onSurface)
        Spacer(Modifier.height(Spacing.section))

        Text("数据存储", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(Spacing.sm))
        OutlinedTextField(dataDir, { dataDir = it }, Modifier.fillMaxWidth(0.5f), singleLine = true, label = { Text("存储目录") })
        Text("连接配置等数据保存位置 · 可用 ${File(ToolBoxSettings.dataDir).freeSpace / 1024 / 1024 / 1024} GB", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

        Spacer(Modifier.height(Spacing.section))

        Text("mysqldump", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(Spacing.sm))
        OutlinedTextField(dumpPath, { dumpPath = it }, Modifier.fillMaxWidth(0.5f), singleLine = true, label = { Text("mysqldump.exe 路径") })
        val found = File(dumpPath).exists()
        Text(if (found) "✅ 文件存在" else "❌ 文件不存在", style = MaterialTheme.typography.bodySmall,
            color = if (found) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error)

        Spacer(Modifier.height(Spacing.section))

        Button({
            ToolBoxSettings.saveDataDir(dataDir)
            ToolBoxSettings.saveMysqldumpPath(dumpPath)
            saved = true
        }) { Text("保存设置") }

        if (saved) {
            Spacer(Modifier.height(Spacing.sm))
            Text("✅ 设置已保存", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary)
        }
    }
}
