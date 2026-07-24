package djshen.toolbox.tools.database.core

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import java.sql.Connection
import java.sql.DriverManager
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class MySqlClient : DatabaseClient {
    override val dbType = "mysql"
    private var pool: HikariDataSource? = null
    private var savedConfig: ConnectionConfig? = null

    override fun connect(config: ConnectionConfig) {
        close()
        savedConfig = config
        pool = HikariDataSource(HikariConfig().apply {
            jdbcUrl = config.jdbcUrl(); driverClassName = "com.mysql.cj.jdbc.Driver"
            username = config.username; password = config.password
            maximumPoolSize = 5; minimumIdle = 1
            connectionTimeout = 10_000L; maxLifetime = 1_800_000L
            connectionTestQuery = "SELECT 1"; validationTimeout = 5_000L
        })
    }
    override fun close() { pool?.close(); pool = null }
    override fun isConnected() = pool != null && pool?.isClosed == false
    override fun testConnection(config: ConnectionConfig): String? = try {
        DriverManager.getConnection(config.jdbcUrl(), config.username, config.password).use { conn ->
            if (!conn.isValid(5)) null
            else conn.createStatement().executeQuery("SELECT VERSION()").use { rs -> if (rs.next()) rs.getString(1) else "MySQL" }
        }
    } catch (_: Exception) { null }
    override fun getVersion(): String {
        val r = executeQuery("SELECT VERSION()")
        return if (!r.isError && r.rows.isNotEmpty()) r.rows[0][0]?.toString() ?: "" else ""
    }

    private fun conn(): Connection = pool?.connection ?: throw IllegalStateException("未连接")

    override fun getDatabases(): List<String> {
        val dbs = mutableListOf<String>()
        conn().use { c -> c.metaData.getCatalogs().use { rs -> while (rs.next()) dbs.add(rs.getString("TABLE_CAT")) } }
        return dbs.filter { it !in setOf("information_schema", "performance_schema", "mysql", "sys") && it.isNotBlank() }
    }
    override fun getTables(database: String): List<String> {
        val t = mutableListOf<String>()
        conn().use { c ->
            c.createStatement().executeUpdate("USE `$database`")
            c.metaData.getTables(database, null, "%", arrayOf("TABLE", "VIEW")).use { rs -> while (rs.next()) t.add(rs.getString("TABLE_NAME")) }
        }
        return t
    }
    override fun getColumns(database: String, table: String): List<ColumnInfo> {
        val pks = mutableSetOf<String>()
        conn().use { c -> c.metaData.getPrimaryKeys(database, null, table).use { rs -> while (rs.next()) pks.add(rs.getString("COLUMN_NAME")) } }
        val cols = mutableListOf<ColumnInfo>()
        conn().use { c ->
            c.metaData.getColumns(database, null, table, "%").use { rs ->
                while (rs.next()) cols.add(ColumnInfo(rs.getString("COLUMN_NAME"), rs.getString("TYPE_NAME"), rs.getInt("COLUMN_SIZE"), rs.getInt("NULLABLE") == 1, pks.contains(rs.getString("COLUMN_NAME")), "YES" == rs.getString("IS_AUTOINCREMENT")))
            }
        }
        return cols
    }

    override fun executeQuery(sql: String): QueryResult {
        val start = System.currentTimeMillis()
        return try { conn().use { c -> c.createStatement().use { s -> readResultSet(s.executeQuery(sql), start) } } }
        catch (e: Exception) { QueryResult.error(e.message ?: "错误", System.currentTimeMillis() - start) }
    }
    override fun executeUpdate(sql: String): Int = conn().use { c -> c.createStatement().use { it.executeUpdate(sql) } }

    override fun executeScript(sql: String): List<QueryResult> {
        val ss = splitStatements(sql).filter { it.isNotBlank() }
        if (ss.isEmpty()) return emptyList()
        val results = mutableListOf<QueryResult>()
        conn().use { c -> c.createStatement().use { stmt ->
            ss.forEach { s ->
                val start = System.currentTimeMillis()
                try {
                    val upper = s.trim().uppercase()
                    if (upper.startsWith("SELECT") || upper.startsWith("SHOW") || upper.startsWith("DESCRIBE") || upper.startsWith("EXPLAIN") || upper.startsWith("WITH"))
                        results.add(readResultSet(stmt.executeQuery(s.trim()), start).copy(sql = s))
                    else { val a = stmt.executeUpdate(s.trim()); results.add(QueryResult(listOf("Affected Rows"), listOf("INTEGER"), listOf(listOf(a)), 1, System.currentTimeMillis() - start, s)) }
                } catch (e: Exception) { results.add(QueryResult.error(e.message ?: "错误", System.currentTimeMillis() - start, s)) }
            }
        }}
        return results
    }

    override fun getTableData(table: String, offset: Int, limit: Int, whereClause: String?) =
        if (whereClause.isNullOrBlank()) executeQuery("SELECT * FROM `$table` LIMIT $offset, $limit")
        else executeQuery("SELECT * FROM `$table` WHERE $whereClause LIMIT $offset, $limit")

    override fun getTableRowCount(table: String, whereClause: String?): Long {
        val sql = if (whereClause.isNullOrBlank()) "SELECT COUNT(*) FROM `$table`" else "SELECT COUNT(*) FROM `$table` WHERE $whereClause"
        val r = executeQuery(sql)
        return if (r.isError || r.rows.isEmpty()) 0 else (r.rows[0][0] as? Number)?.toLong() ?: 0
    }


    private fun findMysqldump(): String {
        // 多路径检测
        val paths = listOf(
            djshen.toolbox.common.ToolBoxSettings.mysqldumpPath,
            "${System.getProperty("user.dir")}/tools/mysql/mysqldump.exe",
            "tools/mysql/mysqldump.exe"
        )
        for (p in paths) { val f = java.io.File(p); if (f.exists()) return f.absolutePath }
        throw IllegalStateException("mysqldump 未找到，请在系统设置中配置路径")
    }

    @Volatile var currentProcess: Process? = null

    override fun exportDatabase(database: String, filePath: String, onProgress: (String, Int) -> Unit) {
        val exe = findMysqldump()
        val cfg = savedConfig ?: throw IllegalStateException("not connected")
        if (database == "all") {
            // 整体备份：并行 mysqldump 每个库
            val dbs = getDatabases()
            val tmpDir = java.io.File(java.io.File(filePath).parentFile, ".dump_${System.currentTimeMillis()}"); tmpDir.mkdirs()
            val pool = java.util.concurrent.Executors.newFixedThreadPool(4)
            val futures = dbs.map { db ->
                pool.submit<Pair<String, Boolean>> {
                    if (BackupCancellation.cancelled) return@submit db to false
                    val tmp = java.io.File(tmpDir, "$db.sql")
                    val abs = tmp.absolutePath.replace("\\", "/")
                    val cmd = buildCmd(exe, cfg, abs, listOf("--databases", db))
                    val pb = ProcessBuilder(cmd); pb.directory(java.io.File(exe).parentFile); pb.redirectErrorStream(true)
                    val proc = pb.start(); currentProcess = proc
                    val ok = proc.waitFor() == 0; if (!ok) onProgress(db, -1)
                    db to ok
                }
            }
            pool.shutdown(); pool.awaitTermination(24, java.util.concurrent.TimeUnit.HOURS)
            currentProcess = null
            // 合并
            java.io.File(filePath).bufferedWriter().use { w ->
                for (db in dbs) {
                    val f = java.io.File(tmpDir, "$db.sql")
                    if (f.exists()) { f.forEachLine { w.write(it + "\n") }; w.write("\n"); f.delete() }
                }
            }
            tmpDir.delete()
            onProgress("all", -1)
        } else {
            val absPath = java.io.File(filePath).absolutePath.replace("\\", "/")
            val cmd = buildCmd(exe, cfg, absPath, listOf("--databases", database))
            val pb = ProcessBuilder(cmd); pb.directory(java.io.File(exe).parentFile); pb.redirectErrorStream(true)
            val proc = pb.start(); currentProcess = proc
            val out = proc.inputStream.bufferedReader().readText()
            currentProcess = null
            if (proc.waitFor() != 0) throw RuntimeException("mysqldump failed: $out")
            onProgress(database, -1)
        }
    }

    override fun exportTable(database: String, table: String, filePath: String, onProgress: (Int) -> Unit) {
        val exe = findMysqldump()
        val cfg = savedConfig ?: throw IllegalStateException("not connected")
        val absPath = java.io.File(filePath).absolutePath.replace("\\", "/")
        val cmd = buildCmd(exe, cfg, absPath, listOf(database, table))
        val pb = ProcessBuilder(cmd); pb.directory(java.io.File(exe).parentFile); pb.redirectErrorStream(true)
        val proc = pb.start(); currentProcess = proc; proc.waitFor(); currentProcess = null
        onProgress(-1)
    }

    private fun buildCmd(exe: String, cfg: ConnectionConfig, resultPath: String, targets: List<String>): List<String> {
        val cmd = mutableListOf(exe, "-h", cfg.host, "-P", cfg.port.toString(), "-u", cfg.username,
            "--single-transaction", "--add-drop-table", "--complete-insert",
            "--compression-algorithms=zstd,uncompressed", "--zstd-compression-level=1",
            "--max-allowed-packet=1073741824", "--net-buffer-length=1048576",
            "--result-file=$resultPath")
        if (cfg.password.isNotBlank()) cmd.add("-p${cfg.password}")
        cmd.addAll(targets)
        return cmd
    }

    private fun readResultSet(rs: java.sql.ResultSet, start: Long): QueryResult {
        val meta = rs.metaData; val cc = meta.columnCount
        val cols = (1..cc).map { meta.getColumnName(it) }
        val types = (1..cc).map { meta.getColumnTypeName(it) ?: "UNKNOWN" }
        val rows = mutableListOf<List<Any?>>()
        while (rs.next()) rows.add((1..cc).map { rs.getObject(it) })
        return QueryResult(cols, types, rows, rows.size, System.currentTimeMillis() - start)
    }
    private fun splitStatements(sql: String): List<String> = sql.split(";").map { it.trim() }
}
