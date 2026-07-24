package djshen.toolbox.tools.database.shared

import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import kotlinx.coroutines.Job

/** 任务状态 */
enum class TaskStatus { RUNNING, COMPLETED, FAILED, CANCELLED }

/** 后台任务 */
class BgTask(
    val id: String = java.util.UUID.randomUUID().toString(),
    val name: String,
    val tool: String,
    val status: MutableState<TaskStatus> = mutableStateOf(TaskStatus.RUNNING),
    val progress: MutableState<String> = mutableStateOf(""),
    val message: MutableState<String> = mutableStateOf(""),
    val current: MutableState<Long> = mutableStateOf(0),
    val total: MutableState<Long> = mutableStateOf(0),
    var job: Job? = null,
    var onCancel: (() -> Unit)? = null,
    val startTime: Long = System.currentTimeMillis(),
    var endTime: MutableState<Long> = mutableStateOf(0),
    val displayDuration: MutableState<String> = mutableStateOf("")
)

/** 全局任务管理器 */
object TaskManager {
    val tasks = mutableStateListOf<BgTask>()

    fun add(name: String, tool: String, job: Job? = null, onCancel: (() -> Unit)? = null): BgTask {
        val t = BgTask(name = name, tool = tool, job = job, onCancel = onCancel)
        tasks.add(t)
        return t
    }

    fun stop(task: BgTask) {
        if (task.status.value == TaskStatus.RUNNING) {
            task.onCancel?.invoke()
            task.endTime.value = System.currentTimeMillis()
            task.status.value = TaskStatus.CANCELLED
            task.message.value = "已取消"
        }
    }

    fun cancelAllRunning(): Int {
        var count = 0
        tasks.filter { it.status.value == TaskStatus.RUNNING }.forEach { stop(it); count++ }
        return count
    }

    fun remove(task: BgTask) {
        if (task.status.value != TaskStatus.RUNNING) {
            val result = when (task.status.value) { TaskStatus.COMPLETED -> "完成"; TaskStatus.FAILED -> "失败"; TaskStatus.CANCELLED -> "已取消"; else -> "" }
            OperationLog.info(task.tool, "任务结束", "$result — ${task.name}")
        }
        tasks.remove(task)
    }
    fun clearCompleted() { tasks.removeAll { it.status.value != TaskStatus.RUNNING } }
}

fun formatDuration(task: BgTask): String {
    val ms = if (task.endTime.value > 0) task.endTime.value - task.startTime else System.currentTimeMillis() - task.startTime
    val sec = ms / 1000
    return when {
        sec < 60 -> "${sec}秒"
        sec < 3600 -> "${sec / 60}分${sec % 60}秒"
        else -> "${sec / 3600}小时${(sec % 3600) / 60}分${sec % 60}秒"
    }
}
