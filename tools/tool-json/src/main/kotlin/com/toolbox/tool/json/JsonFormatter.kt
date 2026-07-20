package com.toolbox.tool.json

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement

/**
 * JSON 格式化引擎 —— 纯业务逻辑，不依赖 UI。
 *
 * 提供格式化（美化）、压缩、校验三种操作。
 */
object JsonFormatter {

    private val prettyPrinter = Json { prettyPrint = true }
    private val validator = Json { ignoreUnknownKeys = true }

    /**
     * 格式化 JSON 字符串（美化缩进）。
     *
     * @param raw  原始 JSON 字符串
     * @return 格式化后的 JSON，或错误信息（以 "Error: " 开头）
     */
    fun format(raw: String): String {
        return try {
            val element: JsonElement = validator.parseToJsonElement(raw.trim())
            prettyPrinter.encodeToString(JsonElement.serializer(), element)
        } catch (e: Exception) {
            "Error: ${e.message ?: "无效的 JSON"}"
        }
    }

    /**
     * 压缩 JSON（移除空白和换行）。
     */
    fun compress(raw: String): String {
        return try {
            val element: JsonElement = validator.parseToJsonElement(raw.trim())
            Json.encodeToString(JsonElement.serializer(), element)
        } catch (e: Exception) {
            "Error: ${e.message ?: "无效的 JSON"}"
        }
    }

    /**
     * 校验 JSON 是否合法。
     *
     * @return 合法的 JSON 字符串，或错误信息（以 "Error: " 开头）
     */
    fun validate(raw: String): String {
        return try {
            validator.parseToJsonElement(raw.trim())
            "✓ 合法的 JSON"
        } catch (e: Exception) {
            "Error: ${e.message ?: "无效的 JSON"}"
        }
    }
}
