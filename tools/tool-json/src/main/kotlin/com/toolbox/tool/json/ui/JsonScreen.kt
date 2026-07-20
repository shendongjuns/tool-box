package com.toolbox.tool.json.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.toolbox.common.theme.*
import com.toolbox.tool.json.JsonFormatter
import java.awt.Toolkit
import java.awt.datatransfer.StringSelection

/**
 * JSON 格式化工具主界面 —— 左右分栏（输入 → 输出）。
 */
@Composable
fun JsonScreen() {
    var input by remember { mutableStateOf("") }
    var output by remember { mutableStateOf("") }

    Column(
        modifier = Modifier.fillMaxSize()
    ) {
        // 页面标题
        Text(
            text = "JSON Formatter",
            style = MaterialTheme.typography.headlineLarge,
            color = ToolBoxColors.TextPrimary
        )

        Spacer(Modifier.height(Spacing.section))

        // 工具栏
        Row(
            horizontalArrangement = Arrangement.spacedBy(Spacing.card)
        ) {
            ToolButton("格式化", onClick = {
                output = JsonFormatter.format(input)
            })
            ToolButton("压缩", onClick = {
                output = JsonFormatter.compress(input)
            })
            ToolButton("校验", onClick = {
                output = JsonFormatter.validate(input)
            })
            ToolButton("复制", icon = {
                Icon(
                    Icons.Default.ContentCopy,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp)
                )
            }, onClick = {
                if (output.isNotBlank()) {
                    val clipboard = Toolkit.getDefaultToolkit().systemClipboard
                    clipboard.setContents(StringSelection(output), null)
                }
            })
        }

        Spacer(Modifier.height(Spacing.card))

        // 输入 / 输出 分栏
        Row(
            modifier = Modifier.fillMaxSize(),
            horizontalArrangement = Arrangement.spacedBy(Spacing.card)
        ) {
            // 输入区
            CodePanel(
                title = "Input",
                value = input,
                onValueChange = { input = it },
                placeholder = "{ \"example\": \"paste your JSON here\" }",
                modifier = Modifier.weight(1f)
            )
            // 输出区
            CodePanel(
                title = "Output",
                value = output,
                onValueChange = {},
                placeholder = "结果将显示在这里...",
                readOnly = true,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

/**
 * 工具栏按钮 —— 蓝色主题，8dp 圆角。
 */
@Composable
private fun ToolButton(
    label: String,
    icon: @Composable (() -> Unit)? = null,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        shape = ButtonShape,
        colors = ButtonDefaults.buttonColors(
            containerColor = ToolBoxColors.Blue,
            contentColor = ToolBoxColors.TextOnPrimary
        ),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 8.dp)
    ) {
        if (icon != null) {
            icon()
            Spacer(Modifier.width(6.dp))
        }
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge
        )
    }
}

/**
 * 代码面板 —— 带标题的等宽文本区域。
 */
@Composable
private fun CodePanel(
    title: String,
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    readOnly: Boolean = false,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier.fillMaxHeight()) {
        // 面板标题
        Text(
            text = title,
            style = MaterialTheme.typography.titleLarge,
            color = ToolBoxColors.TextSecondary,
            modifier = Modifier.padding(bottom = 8.dp)
        )

        // 文本框
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            readOnly = readOnly,
            placeholder = {
                Text(
                    text = placeholder,
                    color = ToolBoxColors.TextTertiary
                )
            },
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(),
            textStyle = MaterialTheme.typography.labelSmall,
            shape = CardShape,
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = ToolBoxColors.Outline,
                unfocusedBorderColor = ToolBoxColors.Outline,
                focusedContainerColor = ToolBoxColors.Surface,
                unfocusedContainerColor = ToolBoxColors.Surface
            )
        )
    }
}
