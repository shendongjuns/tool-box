package djshen.toolbox.tools.database.core

import djshen.toolbox.common.ToolBoxSettings
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.nio.file.Files
import java.nio.file.Paths

/**
 * 连接配置的持久化管理器。
 * 存储目录由 ToolBoxSettings.dataDir 控制。
 */
class ConnectionManager {

    private val json = Json { prettyPrint = true; ignoreUnknownKeys = true }

    private val storageFile get() = ToolBoxSettings.databaseConnectionsFile()

    fun loadConfigs(): List<ConnectionConfig> {
        if (!Files.exists(storageFile)) return emptyList()
        return try { json.decodeFromString<ConnectionConfigsWrapper>(Files.readString(storageFile)).connections } catch (_: Exception) { emptyList() }
    }

    fun saveConfigs(configs: List<ConnectionConfig>) {
        try {
            Files.createDirectories(storageFile.parent)
            Files.writeString(storageFile, json.encodeToString(ConnectionConfigsWrapper(configs)))
        } catch (_: Exception) {}
    }

    /** 合并保存：将指定类型的连接替换，保留其他类型的连接 */
    fun saveConfigsByType(configs: List<ConnectionConfig>, dbType: String) {
        val existing = loadConfigs().filter { it.dbType != dbType }
        saveConfigs(existing + configs)
    }
}

/** JSON 序列化包装类 */
@Serializable
private data class ConnectionConfigsWrapper(
    val connections: List<ConnectionConfig>
)
