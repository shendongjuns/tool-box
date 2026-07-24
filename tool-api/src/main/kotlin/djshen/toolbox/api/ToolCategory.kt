package djshen.toolbox.api

/**
 * 工具分类枚举。
 *
 * @property displayName 侧边栏显示的分类名
 */
enum class ToolCategory(
    val displayName: String
) {
    /** 数据处理：JSON、YAML、CSV、XML 等 */
    DATA("数据处理"),

    /** 数据库管理：MySQL、Redis、ClickHouse 等 */
    DATABASE("数据库管理"),

    /** 文本工具：正则、Diff、大小写转换等 */
    TEXT("文本工具"),

    /** 编解码：Base64、URL、Unicode、哈希等 */
    ENCODE("编解码"),

    /** 系统工具：进程、端口、注册表等 */
    SYSTEM("系统工具"),

    /** 其他未分类工具 */
    OTHER("其他工具");
}
