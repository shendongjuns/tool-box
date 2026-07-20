package com.toolbox.tool.json

import androidx.compose.runtime.Composable
import com.toolbox.api.Tool
import com.toolbox.api.ToolCategory
import com.toolbox.tool.json.ui.JsonScreen

/**
 * JSON 格式化工具 —— Tool 接口实现。
 *
 * 通过 META-INF/services SPI 注册，框架自动发现。
 */
class JsonTool : Tool {

    override val id: String = "tool-json-formatter"

    override val name: String = "JSON 格式化"

    override val description: String = "格式化、压缩、校验 JSON 数据"

    override val category: ToolCategory = ToolCategory.DATA

    @Composable
    override fun Content() {
        JsonScreen()
    }
}
