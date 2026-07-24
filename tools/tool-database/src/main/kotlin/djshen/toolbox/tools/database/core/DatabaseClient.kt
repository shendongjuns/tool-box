package djshen.toolbox.tools.database.core

import java.io.Closeable

interface DatabaseClient : Closeable {
    val dbType: String
    fun connect(config: ConnectionConfig)
    override fun close()
    fun isConnected(): Boolean
    fun testConnection(config: ConnectionConfig): String?
    fun getVersion(): String
    fun getDatabases(): List<String>
    fun getTables(database: String): List<String>
    fun getColumns(database: String, table: String): List<ColumnInfo>
    fun executeQuery(sql: String): QueryResult
    fun executeUpdate(sql: String): Int
    fun executeScript(sql: String): List<QueryResult>
    fun getTableData(table: String, offset: Int, limit: Int, whereClause: String? = null): QueryResult
    fun getTableRowCount(table: String, whereClause: String? = null): Long
    fun exportDatabase(database: String, filePath: String, onProgress: (table: String, rows: Int) -> Unit)
    fun exportTable(database: String, table: String, filePath: String, onProgress: (rows: Int) -> Unit)
}

data class ColumnInfo(
    val name: String, val typeName: String, val typeSize: Int,
    val nullable: Boolean, val isPrimaryKey: Boolean, val isAutoIncrement: Boolean
)
data class IndexInfo(
    val name: String, val columns: List<String>, val unique: Boolean, val type: String
)
