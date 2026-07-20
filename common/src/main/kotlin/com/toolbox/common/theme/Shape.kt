package com.toolbox.common.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.ui.unit.dp

/**
 * ToolBox 圆角规范 —— 克制、层级分明。
 */
val ToolBoxShapes = Shapes(
    /** 小按钮 / 标签 Chip */
    small = RoundedCornerShape(6.dp),
    /** 标准按钮 / 输入框 */
    medium = RoundedCornerShape(8.dp),
    /** 卡片 */
    large = RoundedCornerShape(12.dp),
    /** 弹窗 / 抽屉 */
    extraLarge = RoundedCornerShape(16.dp)
)
