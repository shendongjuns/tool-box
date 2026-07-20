package com.toolbox.framework.window

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowPosition
import androidx.compose.ui.window.WindowState
import androidx.compose.ui.window.application

/**
 * 窗口尺寸常量
 */
object WindowConfig {
    val defaultWidth = 1200.dp
    val defaultHeight = 800.dp
    val minWidth = 900.dp
    val minHeight = 600.dp
}

/**
 * 创建 ToolBox 主窗口。
 *
 * @param content 窗口内容 Composable
 */
fun launchToolBoxWindow(content: @Composable () -> Unit) = application {
    Window(
        onCloseRequest = ::exitApplication,
        title = "ToolBox",
        state = WindowState(
            position = WindowPosition.PlatformDefault,
            size = DpSize(WindowConfig.defaultWidth, WindowConfig.defaultHeight)
        )
    ) {
        content()
    }
}
