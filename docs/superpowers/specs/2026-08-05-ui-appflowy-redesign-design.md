# ToolBox UI 重构设计文档 — AppFlowy 风格

> 日期：2026-08-05
> 状态：已确认（待用户审阅）
> 目标：将 ToolBox v1.2.0 的 UI 全面重构为 AppFlowy 风格（参考 [AppFlowy](https://github.com/AppFlowy-IO/AppFlowy) 的视觉设计），解决现有界面「导航栏问题、字体粗细不一」等体验问题。

---

## 一、背景与决策

用户反馈当前界面（macos_ui 风格）不好看：导航栏存在问题、页面字体粗细不一。经调研确认参考方向为 **AppFlowy 前端设计风格**（模仿设计，代码自行实现 —— AppFlowy 为 AGPLv3，不可复制代码）。

已确认决策：
1. **移除 macos_ui 依赖**，全面使用 Material 组件 + 自研 AppFlowy 风格主题
2. **纯色窗口**（白/深灰背景），关闭亚克力毛玻璃，恢复系统标题栏
3. 字体用 **Poppins**（OFL 开源许可，AppFlowy 同款）+ 系统等宽字体

## 二、设计系统（来自 AppFlowy 源码提取）

### 2.1 布局结构（三层）

```
┌──┬───────┬──────────────────────────┐
│图│ 侧边栏 │        内容区             │
│标│ 分类标题│   ┌──────────────────┐   │
│栏│ ▸ 工具1 │   │  页面容器（限宽居中）│   │
│  │   工具2 │   │  大标题           │   │
│  │ 分类标题│   │  卡片/表格        │   │
│  │ ▸ 工具3 │   │                  │   │
│  │        │   └──────────────────┘   │
└──┴───────┴──────────────────────────┘
```

- **图标栏**（~48px）：顶部应用 logo/图标、侧边栏折叠开关、底部设置入口
- **侧边栏**（~250px）：分类 → 工具两级列表（分组标题 + 工具项），选中/悬浮高亮；可折叠 —— 折叠后侧边栏整条隐藏，内容区占满剩余宽度（图标栏常驻），与 AppFlowy 行为一致
- **内容区**：白色背景，页面容器居中限宽（最大 ~880px），顶部大标题 + 说明文字

### 2.2 配色（浅色模式，AppFlowy 源码精确值）

| 用途 | 色值 | 来源 token |
|------|------|-----------|
| 背景 primary | `#FFFFFF` | neutralWhite |
| 表面容器 layer01 | `#F8FAFF` | neutral100 |
| 表面容器 layer02 | `#E4E8F5` | neutral200 |
| 表面容器 layer03 | `#CED3E6` | neutral300 |
| 文字 primary | `#21232A` | neutral1000 |
| 文字 secondary | `#6F748C` | neutral600 |
| 文字 tertiary | `#989EB7` | neutral500 |
| 主色 action/info | `#0092D6` | blue600 |
| 主色 hover | `#0078C0` | blue700 |
| 边框 primary | `#E4E8F5` | neutral200 |
| 边框 hover | `#CED3E6` | neutral300 |
| 成功 | `#48A982` 系（green500+） | green 系列 |
| 警告 | orange 系列 | orange |
| 错误 | red 系列 | red |
| 特色 | `#5856D6` 系（purple500） | purple |

深色模式：以 neutral 深色阶（#21232A 起）构建对应层级，色相映射保持一致。

### 2.3 间距 / 圆角 / 阴影

- 间距：4 / 6 / 8 / 12 / 16 / 20
- 圆角：4 / 6 / 8 / 12 / 16 / 20（组件主用 8）
- 阴影 small：offset(0, 2)、blur 16、`#1F000000`

### 2.4 字体

- **Poppins**（400 Regular / 500 Medium / 600 SemiBold / 700 Bold 四个字重打包进 assets）
- 中文通过系统字体自动 fallback（Poppins 无中文字形）
- 等宽（端口/版本数据）：系统等宽字体（Consolas/Roboto Mono 不打包，保持精简）

### 2.5 组件规范

| 组件 | 规范 |
|------|------|
| 侧边栏工具项 | 圆角 8；hover 背景 `#F8FAFF`（layer01）；选中背景 `#E4E8F5`（layer02）+ 主色文字；左侧可选指示条 |
| 分类标题 | labelMedium，tertiary 色，上下留白 |
| 主按钮 | 主色 `#0092D6` 背景、白字、圆角 8；hover `#0078C0`；disabled 降透明度 |
| 次级按钮 | 白底、`#E4E8F5` 边框、primary 文字 |
| 输入框 | 白底 `#E4E8F5` 边框、圆角 8；聚焦主色边框 |
| 卡片/列表 | 白底、圆角 8、`#E4E8F5` 边框；hover 提亮 |
| 页面容器 | 居中限宽 ~880px；标题 ~28px bold；说明文字 tertiary 色 |

## 三、窗口调整

- `app_window.dart`：移除 flutter_acrylic 配置，恢复系统标题栏（`TitleBarStyle.normal`），窗口背景由应用主题决定
- 保留 window_manager 的最小尺寸/居中设置
- 删除无边框自绘标题栏相关逻辑

## 四、实施范围

| 改动 | 文件 | 说明 |
|------|------|------|
| 移除 macos_ui 依赖 | pubspec.yaml | 保留 flutter_acrylic？——不再使用，一并移除 |
| Poppins 字体资产 | assets/fonts/、pubspec.yaml | 4 个 ttf 文件 + fonts 声明 |
| 主题重写 | lib/ui/theme/* | AppFlowy 色板 light/dark、TextTheme（Poppins）、组件主题 |
| 窗口简化 | lib/ui/window/app_window.dart | 纯色 + 系统标题栏 |
| Shell 重构 | lib/ui/shell/*、lib/main.dart | 图标栏 + 可折叠侧边栏 + 内容区；MacosApp → MaterialApp |
| 发现工具页面重构 | lib/features/discovery/presentation/* | AppFlowy 页面风格（容器限宽、标题区、卡片分组） |
| 测试更新 | test/ui/*、test/features/* | MacosApp → MaterialApp + 新主题；补充新布局测试 |
| 文档 | README.md | 技术栈表移除 macos_ui、更新 UI 描述 |

**不动**：core 层（模型/引擎/指纹库）、registry 接口、controller 逻辑（discovery 状态管理不变）。

## 五、测试策略

- 主题测试：色板值断言（light/dark 关键色）
- Shell widget 测试：图标栏渲染、侧边栏分类/工具渲染、折叠切换、内容区切换
- Discovery 页面测试：现有 controller/view 测试更新主题环境后保持通过；补充页面容器/标题渲染断言
- 全量：flutter analyze + flutter test + flutter build windows --release

## 六、非目标

- 不模仿 AppFlowy 的编辑器/文档功能（仅视觉风格）
- 不实现动态主题编辑器（AppFlowy 高级功能）
- 不改变窗口行为语义（仅外观）
