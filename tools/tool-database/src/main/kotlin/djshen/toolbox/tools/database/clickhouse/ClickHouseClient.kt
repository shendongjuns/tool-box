package djshen.toolbox.tools.database.clickhouse

import djshen.toolbox.tools.database.core.ConnectionConfig
import djshen.toolbox.tools.database.core.QueryResult
import djshen.toolbox.tools.database.core.BackupCancellation
import java.net.HttpURLConnection
import java.net.URI

/**
 * ClickHouse HTTP 客户端（通过 8123 端口 HTTP 接口）。
 * 注意：ClickHouse 不使用反引号 ``，使用无引号或双引号标识符。
 */
class ClickHouseClient {
    private var config: ConnectionConfig? = null
    val isConnected: Boolean get() = config != null

    fun connect(cfg: ConnectionConfig) { this.config = cfg }
    fun close() { config = null }

    fun testConnection(cfg: ConnectionConfig): String? {
        return try {
            val result = execute(cfg, "SELECT 1", "TabSeparated")
            if (!result.isError && result.rows.isNotEmpty()) "ClickHouse" else null
        } catch (_: Exception) { null }
    }

    fun getDatabases(): List<String> {
        val result = execute("SHOW DATABASES", "TabSeparated")
        return result.rows.mapNotNull { it.getOrNull(0)?.toString() }.filter { it !in setOf("system", "INFORMATION_SCHEMA", "information_schema") && it.isNotBlank() }
    }

    fun getTables(database: String): List<String> {
        val result = execute("SHOW TABLES FROM $database", "TabSeparated")
        if (result.isError) return emptyList()
        return result.rows.mapNotNull { it.getOrNull(0)?.toString() }.filter { it.isNotBlank() }
    }

    fun getTableRowCount(database: String, table: String): Long {
        val result = execute("SELECT COUNT(*) FROM $database.$table", "TabSeparated")
        if (result.isError || result.rows.isEmpty()) return 0
        return result.rows[0].getOrNull(0)?.toString()?.toLongOrNull() ?: 0
    }

    fun executeQuery(sql: String): QueryResult = execute(sql, "CSVWithNames")

    /** 导出数据库到 SQL 文件 */
    fun exportDatabase(database: String, filePath: String, onProgress: (String, Int) -> Unit) {
        val file = java.io.File(filePath); file.parentFile?.mkdirs()
        file.bufferedWriter().use { w ->
            w.write("-- ToolBox ClickHouse Dump\n-- Database: $database\n-- ${java.time.LocalDateTime.now()}\n\n")
            w.write("CREATE DATABASE IF NOT EXISTS $database;\n\n"); w.flush()
            val tables = getTables(database)
            for (table in tables) {
                if (BackupCancellation.cancelled) break
                val ddl = execute("SHOW CREATE TABLE $database.$table", "TabSeparated")
                if (!ddl.isError && ddl.rows.isNotEmpty()) {
                    val raw = ddl.rows[0].getOrNull(0)?.toString() ?: ""
                    val sql = raw.replace("\\n", "\n")  // ClickHouse TabSeparated 会转义换行
                    if (sql.isNotBlank()) { w.write("DROP TABLE IF EXISTS $database.$table;\n$sql;\n\n") }
                }; w.flush()
                val total = getTableRowCount(database, table); val fetchBatch = 100000L; var offset = 0L; var rows = 0
                if (total > 0) {
                    val sample = execute("SELECT * FROM $database.$table LIMIT 1", "TabSeparatedWithNames")
                    val colNames = if (!sample.isError && sample.columns.isNotEmpty()) sample.columns.joinToString(", ") else ""
                    while (offset < total && !BackupCancellation.cancelled) {
                        val data = execute("SELECT * FROM $database.$table LIMIT $fetchBatch OFFSET $offset", "TabSeparated")
                        if (!data.isError && data.rows.isNotEmpty()) {
                            data.rows.chunked(1000).forEach { chunk ->
                                val values = chunk.joinToString(", ") { row ->
                                    "(${row.joinToString(", ") { v -> when(v){null->"NULL";is Number->v.toString();else->"'${v.toString().replace("'","\\'")}'"} }})"
                                }
                                w.write("INSERT INTO $database.$table ($colNames) VALUES $values;\n"); rows += chunk.size
                            }
                        }; offset += fetchBatch; w.flush()
                    }
                }
                w.write("\n"); onProgress(table, rows)
            }
        }
    }

    /** 导入 SQL 文件 */
    fun importSql(filePath: String, onProgress: (String, Int) -> Unit) {
        val cfg = config ?: throw IllegalStateException("未连接")
        val content = java.io.File(filePath).readText()
        val cleaned = content.lines().filter { !it.trimStart().startsWith("--") }.joinToString("\n")
        if (cleaned.isBlank()) { onProgress("文件为空", 0); return }
        // 逐条 SQL 发送
        val statements = cleaned.split(";").map { it.trim() }.filter { it.isNotBlank() }
        var total = 0; var errors = 0
        for (sql in statements) {
            val result = try { execute(sql) } catch (e: Exception) { QueryResult.error(e.message ?: "错误") }
            if (result.isError) {
                errors++
                if (errors <= 3) onProgress("${sql.take(40)}... → ${result.errorMessage?.take(60)}", -1)
            } else { total++ }
        }
        onProgress("完成: $total 成功" + if (errors > 0) ", $errors 失败" else "", total)
    }

    private fun execute(sql: String, format: String = "TabSeparated"): QueryResult {
        val cfg = config ?: return QueryResult.error("未连接")
        return try { execute(cfg, sql, format) } catch (e: Exception) { QueryResult.error(e.message ?: "错误") }
    }

    private fun execute(cfg: ConnectionConfig, sql: String, format: String): QueryResult {
        val start = System.currentTimeMillis()
        // 使用 POST 方法将 SQL 放在请求体中，避免 URL 长度限制和编码问题
        val url = "http://${cfg.host}:${cfg.port}/?default_format=$format"
        val conn = URI(url).toURL().openConnection() as HttpURLConnection
        conn.requestMethod = "POST"
        conn.doOutput = true
        conn.connectTimeout = 30_000; conn.readTimeout = 120_000
        if (cfg.username.isNotBlank()) {
            val auth = java.util.Base64.getEncoder().encodeToString("${cfg.username}:${cfg.password}".toByteArray())
            conn.setRequestProperty("Authorization", "Basic $auth")
        }
        conn.outputStream.write(sql.toByteArray(Charsets.UTF_8))
        conn.outputStream.flush()
        val code = conn.responseCode
        val text = if (code in 200..299) conn.inputStream.bufferedReader().readText()
        else { conn.disconnect(); return QueryResult.error("HTTP $code: ${conn.errorStream?.bufferedReader()?.readText() ?: ""}") }
        conn.disconnect()
        val lines = text.trim().lines()
        if (lines.isEmpty()) return QueryResult(emptyList(), emptyList(), emptyList(), 0, System.currentTimeMillis() - start)

        val isTab = format.startsWith("Tab")
        val separator = if (isTab) "\t" else ","
        val hasHeader = format.contains("WithNames")
        val columns = if (hasHeader) lines[0].split(separator).map { it.trim() } else emptyList()
        val dataLines = if (hasHeader) lines.drop(1) else lines
        val rows: List<List<Any?>> = dataLines.map { line -> line.split(separator).map { v -> v.trim() as Any? } }
        return QueryResult(columns = columns, columnTypes = List(columns.size) { "String" }, rows = rows, rowCount = rows.size, executionTimeMs = System.currentTimeMillis() - start)
    }
}
