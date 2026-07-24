package djshen.toolbox.tools.database.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import djshen.toolbox.common.theme.Spacing
import djshen.toolbox.common.theme.ToolBoxShapes
import djshen.toolbox.tools.database.core.ConnectionConfig
import djshen.toolbox.tools.database.core.DatabaseClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * 添加/编辑数据库连接的对话框。
 *
 * @param existing 已有配置（编辑模式），为 null 则为新增模式
 * @param client 用于测试连接的客户端
 * @param onSave 保存回调
 * @param onDismiss 关闭回调
 */
@Composable
fun ConnectionDialog(
    existing: ConnectionConfig?,
    client: DatabaseClient,
    onSave: (ConnectionConfig) -> Unit,
    onDismiss: () -> Unit
) {
    val isEdit = existing != null

    // 表单状态
    var name by remember { mutableStateOf(existing?.name ?: "") }
    var host by remember { mutableStateOf(existing?.host ?: "127.0.0.1") }
    var port by remember { mutableStateOf((existing?.port ?: 3306).toString()) }
    var username by remember { mutableStateOf(existing?.username ?: "root") }
    var password by remember { mutableStateOf(existing?.password ?: "") }
    var database by remember { mutableStateOf(existing?.database ?: "") }
    var passwordVisible by remember { mutableStateOf(false) }

    // 测试连接状态
    var testing by remember { mutableStateOf(false) }
    var testResult by remember { mutableStateOf<String?>(null) }

    val scope = rememberCoroutineScope()

    AlertDialog(
        onDismissRequest = onDismiss,
        shape = ToolBoxShapes.extraLarge,
        title = {
            Text(
                text = if (isEdit) "编辑连接" else "新建连接",
                style = MaterialTheme.typography.headlineMedium
            )
        },
        text = {
            Column(
                modifier = Modifier.width(420.dp),
                verticalArrangement = Arrangement.spacedBy(Spacing.sm)
            ) {
                // 连接名称
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("连接名称") },
                    placeholder = { Text("例如：本地 MySQL") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )

                // 主机 + 端口
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
                ) {
                    OutlinedTextField(
                        value = host,
                        onValueChange = { host = it },
                        label = { Text("主机") },
                        singleLine = true,
                        modifier = Modifier.weight(2f)
                    )
                    OutlinedTextField(
                        value = port,
                        onValueChange = { port = it.filter { c -> c.isDigit() } },
                        label = { Text("端口") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.weight(1f)
                    )
                }

                // 用户名
                OutlinedTextField(
                    value = username,
                    onValueChange = { username = it },
                    label = { Text("用户名") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )

                // 密码（带显示/隐藏切换）
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    label = { Text("密码") },
                    singleLine = true,
                    visualTransformation = if (passwordVisible) VisualTransformation.None
                        else PasswordVisualTransformation(),
                    trailingIcon = {
                        IconButton(onClick = { passwordVisible = !passwordVisible }) {
                            Icon(
                                imageVector = if (passwordVisible) Icons.Default.VisibilityOff
                                    else Icons.Default.Visibility,
                                contentDescription = if (passwordVisible) "隐藏密码" else "显示密码"
                            )
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                )

                // 数据库名（可选）
                OutlinedTextField(
                    value = database,
                    onValueChange = { database = it },
                    label = { Text("数据库（可选）") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )

                // 测试结果提示
                if (testResult != null) {
                    val isSuccess = testResult!!.startsWith("✅")
                    Text(
                        text = testResult!!,
                        style = MaterialTheme.typography.bodySmall,
                        color = if (isSuccess) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.error
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val config = ConnectionConfig(
                        id = existing?.id ?: java.util.UUID.randomUUID().toString(),
                        name = name.ifBlank { "$host:$port" },
                        host = host.ifBlank { "127.0.0.1" },
                        port = port.toIntOrNull() ?: 3306,
                        username = username.ifBlank { "root" },
                        password = password,
                        database = database
                    )
                    onSave(config)
                },
                enabled = host.isNotBlank() && username.isNotBlank()
            ) {
                Text(if (isEdit) "保存" else "添加")
            }
        },
        dismissButton = {
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                // 测试连接按钮
                OutlinedButton(
                    onClick = {
                        testing = true
                        testResult = null
                        val config = ConnectionConfig(
                            host = host.ifBlank { "127.0.0.1" },
                            port = port.toIntOrNull() ?: 3306,
                            username = username.ifBlank { "root" },
                            password = password,
                            database = database,
                            name = ""
                        )
                        scope.launch {
                            val version = withContext(Dispatchers.IO) { client.testConnection(config) }
                            testResult = if (version != null) "✅ 连接成功 — MySQL $version" else "❌ 连接失败，请检查参数"
                            testing = false
                        }
                    },
                    enabled = host.isNotBlank() && username.isNotBlank() && !testing
                ) {
                    if (testing) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            strokeWidth = 2.dp
                        )
                        Spacer(Modifier.width(Spacing.sm))
                    }
                    Text("测试连接")
                }
                TextButton(onClick = onDismiss) {
                    Text("取消")
                }
            }
        }
    )
}
