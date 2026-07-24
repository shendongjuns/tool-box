package djshen.toolbox.common

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths

object ToolBoxSettings {
    private val defaultDir: String = Paths.get(System.getProperty("user.dir"), "data").toString()
    var dataDir: String = defaultDir; private set
    var mysqldumpPath: String = Paths.get(System.getProperty("user.dir"), "tools", "mysql", "mysqldump.exe").toString(); private set

    private val configFile: Path get() = Paths.get(dataDir, "settings.json")

    fun load() {
        // 先尝试从 dataDir 读取（用户可能已修改路径）
        val primary = configFile
        // 如果 dataDir 还没变过，primary 就是 defaultDir/settings.json
        try { Files.createDirectories(Paths.get(dataDir)) } catch (_: Exception) {}
        try {
            if (Files.exists(primary)) {
                val map = Files.readString(primary).trim().split("\n").associate { line ->
                    val parts = line.split("=", limit = 2)
                    parts[0].trim() to parts.getOrElse(1) { "" }.trim()
                }
                map["dataDir"]?.let { dataDir = it }
                map["mysqldump"]?.let { mysqldumpPath = it }
            }
        } catch (_: Exception) {}
    }

    fun saveDataDir(dir: String) { dataDir = dir; persist() }
    fun saveMysqldumpPath(path: String) { mysqldumpPath = path; persist() }

    private fun persist() {
        try {
            Files.createDirectories(Paths.get(dataDir))
            Files.writeString(configFile, "dataDir=$dataDir\nmysqldump=$mysqldumpPath\n")
        } catch (_: Exception) {}
    }

    fun databaseConnectionsFile(): Path = Paths.get(dataDir, "database_connections.json")
    fun savedQueriesFile(): Path = Paths.get(dataDir, "saved_queries.json")
}
