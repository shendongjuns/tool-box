package djshen.toolbox.framework.navigation

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import djshen.toolbox.api.Tool
import djshen.toolbox.api.ToolCategory
import djshen.toolbox.common.theme.Spacing
import djshen.toolbox.common.theme.ToolBoxShapes

/**
 * 侧边栏组件 —— 分类 → 工具两级导航，Apple 风格。
 *
 * @param groupedTools 按分类分组的工具
 * @param selectedTool 当前选中工具
 * @param onToolSelect 选中回调
 * @param expanded     是否展开（动画控制）
 * @param onToggle     折叠/展开切换
 */
@Composable
fun Sidebar(
    groupedTools: Map<ToolCategory, List<Tool>>,
    selectedTool: Tool?,
    onToolSelect: (Tool) -> Unit,
    expanded: Boolean,
    onToggle: () -> Unit
) {
    // spring 弹簧动画，比 tween 更流畅自然
    val offsetX by animateDpAsState(
        targetValue = if (expanded) 0.dp else (-Spacing.sidebarWidth),
        animationSpec = spring(dampingRatio = 0.8f, stiffness = 300f),
        label = "sidebarOffset"
    )

    Column(
        modifier = Modifier
            .offset(x = offsetX)
            .width(Spacing.sidebarWidth)
            .fillMaxHeight()
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(top = Spacing.section)
    ) {
            // 顶部区域：折叠按钮
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = Spacing.sm),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onToggle) {
                    Icon(
                        imageVector = Icons.Default.ChevronLeft,
                        contentDescription = "收起侧边栏",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            Spacer(Modifier.height(Spacing.card))

            // 工具列表（滚动区域）
            if (groupedTools.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = Spacing.inner),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "暂无工具",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(bottom = Spacing.page)
                ) {
                    // 列表顶部间距
                    item { Spacer(Modifier.height(Spacing.card)) }

                    groupedTools.forEach { (category, tools) ->
                        // 分类标题
                        item(key = "cat-${category.name}") {
                            CategoryHeader(category)
                        }
                        // 工具列表
                        items(tools, key = { it.id }) { tool ->
                            ToolItem(
                                tool = tool,
                                isSelected = tool == selectedTool,
                                onClick = { onToolSelect(tool) }
                            )
                        }
                        // 分类间距
                        item(key = "gap-${category.name}") {
                            Spacer(Modifier.height(Spacing.card))
                        }
                    }
                }
            }

            // 底部：版本信息
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(Spacing.inner),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "v1.0.0",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }

/** 分类标题 */
@Composable
private fun CategoryHeader(category: ToolCategory) {
    Text(
        text = category.displayName,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(
            start = Spacing.inner,
            top = Spacing.sm,
            bottom = Spacing.xs
        )
    )
}

/** 单个工具项 */
@Composable
private fun ToolItem(
    tool: Tool,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isHovered by interactionSource.collectIsHoveredAsState()

    val bgColor = when {
        isSelected -> MaterialTheme.colorScheme.primary.copy(alpha = 0.10f)
        isHovered  -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.05f)
        else       -> MaterialTheme.colorScheme.surfaceVariant
    }

    val textColor = when {
        isSelected -> MaterialTheme.colorScheme.primary
        else       -> MaterialTheme.colorScheme.onSurfaceVariant
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = Spacing.sm)
            .clip(ToolBoxShapes.medium)
            .background(bgColor)
            .hoverable(interactionSource)
            .clickable(onClick = onClick)
            .padding(horizontal = Spacing.sm, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // 左侧颜色指示条
        Box(
            modifier = Modifier
                .width(3.dp)
                .height(16.dp)
                .background(
                    if (isSelected) MaterialTheme.colorScheme.primary
                    else bgColor,
                    ToolBoxShapes.small
                )
        )

        Spacer(Modifier.width(Spacing.sm))

        Text(
            text = tool.name,
            style = MaterialTheme.typography.bodyLarge,
            color = textColor,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}
