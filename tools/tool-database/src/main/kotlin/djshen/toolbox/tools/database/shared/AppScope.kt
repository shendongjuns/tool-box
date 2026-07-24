package djshen.toolbox.tools.database.shared

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/** 全局协程作用域，不受 Composable 生命周期影响 */
val AppScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
