package djshen.toolbox.api

import androidx.compose.runtime.Composable

/**
 * 工具接口 —— 每个工具模块需实现此接口并通过 ServiceLoader 注册。
 *
 * 框架层负责窗口、导航、主题，工具只需返回自己的 [Content]。
 *
 * 使用方式：
 * 1. 在工具模块中创建一个类实现 [Tool]
 * 2. 在 src/main/resources/META-INF/services/djshen.toolbox.api.Tool 中写入全限定类名
 * 3. 框架启动时通过 ServiceLoader 自动发现并加载
 */
interface Tool {

    /** 唯一标识，如 "tool-json-formatter" */
    val id: String

    /** 侧边栏显示名称 */
    val name: String

    /** 简介说明，hover 时 tooltip 显示 */
    val description: String

    /** 所属分类 */
    val category: ToolCategory

    /** 工具主界面，由框架嵌入内容区 */
    @Composable
    fun Content()

    /**
     * 工具被选中时调用（可选覆写）。
     * 适合初始化资源、注册快捷键等。
     */
    fun onSelected() {}

    /**
     * 工具被取消选中时调用（可选覆写）。
     * 适合释放资源、注销监听器等。
     */
    fun onDeselected() {}
}
