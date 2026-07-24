package djshen.toolbox.tools.database.core

/**
 * 查询结果数据结构。
 *
 * @property columns 列名列表（按顺序）
 * @property columnTypes 列对应的 JDBC 类型名
 * @property rows 行数据，每行为 [Any?] 列表
 * @property rowCount 总行数（可能大于 rows.size，用于分页）
 * @property executionTimeMs 查询执行耗时（毫秒）
 * @property sql 执行的 SQL 语句
 * @property isError 是否为错误结果
 * @property errorMessage 错误信息（仅 isError 为 true 时有值）
 */
data class QueryResult(
    val columns: List<String>,
    val columnTypes: List<String>,
    val rows: List<List<Any?>>,
    val rowCount: Int,
    val executionTimeMs: Long,
    val sql: String = "",
    val isError: Boolean = false,
    val errorMessage: String? = null
) {
    companion object {
        fun error(message: String, elapsedMs: Long = 0, sql: String = ""): QueryResult = QueryResult(
            columns = emptyList(),
            columnTypes = emptyList(),
            rows = emptyList(),
            rowCount = 0,
            executionTimeMs = elapsedMs,
            sql = sql,
            isError = true,
            errorMessage = message
        )
    }
}
