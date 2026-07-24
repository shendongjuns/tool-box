package djshen.toolbox.tools.database.shared

import androidx.compose.runtime.mutableStateListOf
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

/** 操作日志条目 */
data class LogEntry(
    val time: String = LocalDateTime.now().format(DateTimeFormatter.ofPattern("HH:mm:ss")),
    val tool: String,
    val action: String,
    val detail: String = "",
    val level: LogLevel = LogLevel.INFO
)

enum class LogLevel { INFO, SUCCESS, WARN, ERROR }

/** 全局操作日志 */
object OperationLog {
    val entries = mutableStateListOf<LogEntry>()
    private const val MAX = 500

    fun info(tool: String, action: String, detail: String = "") {
        entries.add(0, LogEntry(tool = tool, action = action, detail = detail, level = LogLevel.INFO))
        trim()
    }
    fun success(tool: String, action: String, detail: String = "") {
        entries.add(0, LogEntry(tool = tool, action = action, detail = detail, level = LogLevel.SUCCESS))
        trim()
    }
    fun error(tool: String, action: String, detail: String = "") {
        entries.add(0, LogEntry(tool = tool, action = action, detail = detail, level = LogLevel.ERROR))
        trim()
    }
    private fun trim() { if (entries.size > MAX) entries.removeRange(MAX, entries.size) }
}
