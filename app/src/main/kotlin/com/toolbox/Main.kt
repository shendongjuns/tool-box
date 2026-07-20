package com.toolbox

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowState
import androidx.compose.ui.window.application
import com.toolbox.framework.theme.*

fun main() = application {
    Window(
        onCloseRequest = ::exitApplication,
        title = "ToolBox",
        state = WindowState(width = 1200.dp, height = 800.dp)
    ) {
        ToolBoxTheme {
            // Phase 2 验证：展示设计系统各元素
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(MaterialTheme.colorScheme.surfaceVariant),
                contentAlignment = Alignment.Center
            ) {
                Column(
                    modifier = Modifier
                        .width(400.dp)
                        .shadow(2.dp, CardShape)
                        .background(
                            MaterialTheme.colorScheme.surface,
                            CardShape
                        )
                        .padding(Spacing.inner),
                    verticalArrangement = Arrangement.spacedBy(Spacing.inner)
                ) {
                    // 大标题
                    Text(
                        text = "Large Title",
                        style = MaterialTheme.typography.headlineLarge
                    )
                    // 卡片标题
                    Text(
                        text = "Title 1",
                        style = MaterialTheme.typography.headlineMedium
                    )
                    // 分组标题
                    Text(
                        text = "Title 2",
                        style = MaterialTheme.typography.titleLarge
                    )
                    // 正文
                    Text(
                        text = "Body — 正文内容使用 15sp Regular，颜色为 TextSecondary。",
                        style = MaterialTheme.typography.bodyLarge
                    )
                    // 辅助说明
                    Text(
                        text = "Caption — 辅助说明文字 12sp",
                        style = MaterialTheme.typography.bodySmall
                    )
                    // 等宽代码
                    Text(
                        text = "monospace 13sp {\"key\": \"value\"}",
                        style = MaterialTheme.typography.labelSmall
                    )
                }
            }
        }
    }
}
