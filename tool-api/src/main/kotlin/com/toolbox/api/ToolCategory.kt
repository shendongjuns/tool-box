package com.toolbox.api

/**
 * 工具分类枚举
 *
 * @property displayName 侧边栏显示的分类名
 * @property colorHex     分类主题色（0xAARRGGBB）
 */
enum class ToolCategory(
    val displayName: String,
    val colorHex: Long
) {
    /** 数据处理：JSON、YAML、CSV、XML 等 */
    DATA("数据处理", 0xFF007AFF),

    /** 文本工具：正则、Diff、大小写转换等 */
    TEXT("文本工具", 0xFF34C759),

    /** 编解码：Base64、URL、Unicode、哈希等 */
    ENCODE("编解码", 0xFF5856D6),

    /** 系统工具：进程、端口、注册表等 */
    SYSTEM("系统工具", 0xFFFF9500),

    /** 其他未分类工具 */
    OTHER("其他工具", 0xFF8E8E93);
}
