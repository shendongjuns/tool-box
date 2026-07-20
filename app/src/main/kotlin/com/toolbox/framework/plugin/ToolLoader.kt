package com.toolbox.framework.plugin

import com.toolbox.api.Tool
import com.toolbox.api.ToolCategory
import java.util.ServiceLoader

/**
 * 工具加载器 —— 通过 JDK ServiceLoader 扫描 classpath 中的 [Tool] 实现。
 *
 * 每个工具模块需要在 META-INF/services/com.toolbox.api.Tool 中注册其实现类。
 */
object ToolLoader {

    /**
     * 加载所有已注册的工具，按分类分组排序。
     *
     * @return 按 [ToolCategory] 分组的工具列表，分类按 ordinal 排序
     */
    fun load(): Map<ToolCategory, List<Tool>> {
        val tools = ServiceLoader.load(Tool::class.java).toList()
        return tools
            .sortedBy { it.name }
            .groupBy { it.category }
            .toSortedMap(compareBy { it.ordinal })
    }
}
