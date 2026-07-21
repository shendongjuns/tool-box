package djshen.toolbox.framework.window

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.graphics.toComposeImageBitmap
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
 * 创建主窗口，居中弹出，加载应用图标。
 *
 * @param content 窗口内容 Composable
 */
fun launchToolBoxWindow(content: @Composable () -> Unit) = application {
    val icon = remember {
        val bytes = {}::class.java.classLoader
            .getResourceAsStream("icon.ico")!!
            .readBytes()
        BitmapPainter(
            org.jetbrains.skia.Image
                .makeFromEncoded(bytes)
                .toComposeImageBitmap()
        )
    }

    Window(
        onCloseRequest = ::exitApplication,
        title = "ToolBox",
        icon = icon,
        state = WindowState(
            position = WindowPosition(Alignment.Center),
            size = DpSize(WindowConfig.defaultWidth, WindowConfig.defaultHeight)
        )
    ) {
        content()
    }
}
