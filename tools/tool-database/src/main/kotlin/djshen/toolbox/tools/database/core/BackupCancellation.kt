package djshen.toolbox.tools.database.core

/** 全局备份取消标志 */
object BackupCancellation {
    @Volatile var cancelled = false
    fun cancel() { cancelled = true }
    fun reset() { cancelled = false }
}
