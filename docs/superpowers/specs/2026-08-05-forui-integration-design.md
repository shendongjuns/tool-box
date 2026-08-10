# ToolBox Forui 组件库集成设计文档

> 日期：2026-08-05
> 状态：已确认（待用户审阅）
> 目标：引入 Forui 组件库（[forui.dev](https://forui.dev/docs)，shadcn/ui 风格极简 Flutter 组件库），替换当前 Material 默认组件，解决「组件不够精致」的观感问题。

---

## 一、背景与决策

用户反馈 UI「不够简洁美观」，定位为**组件不够精致**（按钮/输入框/列表等控件样式像默认控件）。经调研对比 Forui 与 shadcn_flutter，选定 **Forui 0.25.0**（成熟稳定 51 版、极简美学、Windows 桌面适配好、自包含）。

已确认决策：
1. 引入 forui 依赖（已安装 0.25.0）
2. Appflowy 色板映射到 Forui 的 FColors token（色板值不变）
3. MaterialApp 保留 + FTheme 包裹，两套组件共存过渡
4. 侧边栏用 Forui 自带 `FSidebar/FSidebarGroup/FSidebarItem` 重做
5. 核心控件替换：按钮/输入框/卡片/进度条/列表

## 二、Forui 主题集成

### 2.1 FColors 色板映射（Appflowy 色板 → Forui token）

| FColors token | 浅色 | 深色 | 来源 |
|---------------|------|------|------|
| background | `#FFFFFF` | `#21232A` | Appflowy surface |
| foreground | `#21232A` | `#F8FAFF` | textPrimary |
| primary | `#0092D6` | `#4EC1FF` | 主色 |
| primaryForeground | `#FFFFFF` | `#FFFFFF` | — |
| secondary | `#E4E8F5` | `#32343F` | layer02 |
| muted | `#F8FAFF` | `#272930` | layer01 |
| mutedForeground | `#989EB7` | `#989EB7` | textTertiary |
| card | `#FFFFFF` | `#21232A` | surface |
| border | `#E4E8F5` | `#3D404F` | 边框 |
| destructive | `#E85D5D` | `#F27676` | error |

### 2.2 集成方式

- `main.dart`：MaterialApp 保持（路由/对话框基础），`home` 的 ShellView 外层用 `FTheme(data: buildForuiTheme(brightness), child: ...)` 包裹，随 `themeControllerProvider` 深浅色切换
- 新建 `lib/ui/theme/forui_theme.dart`：`FThemeData buildForuiTheme(Brightness brightness)`（含 FColors 映射 + typography/样式基础）
- `AppflowyTheme`（Material ThemeData）保留：FTheme 未覆盖的场景（对话框、tooltip 等 Material 组件）兜底；不重复维护色值（两处色板指向同一 AppflowyColors 常量）

## 三、组件替换清单

| 现有（Material） | 替换为（Forui） | 使用位置 |
|-----------------|----------------|---------|
| ElevatedButton / OutlinedButton | `FButton.primary` / `FButton.outline` | 发现页扫描/停止按钮 |
| TextField | `FTextField` | 发现页目标输入框 |
| Card | `FCard` | 发现页主机分组卡片 |
| LinearProgressIndicator | `FProgress`（不确定进度）/ `FDeterminateProgress`（确定进度） | 发现页进度区 |
| IconButton | `FButton.icon`（或保留 IconButton） | 复制按钮、图标栏 |
| 自绘 SidebarPanel/_ToolItem | `FSidebar` + `FSidebarGroup` + `FSidebarItem` | Shell 侧边栏 |
| ListTile（若用） | `FTile` | 结果行 |

## 四、Shell 侧边栏重做

- 用 Forui 侧边栏组件：`FSidebar(children: [FSidebarGroup(title: 分类名, items: [FSidebarItem(icon, label, selected, onSelect)])])`
- 交互细节（hover/选中/圆角）由库提供，替换自绘 `_ToolItem`
- 布局结构不变：48px 图标栏 + 250px 可折叠侧边栏 + 限宽内容区
- 折叠逻辑保留 `sidebarExpandedProvider`，隐藏侧边栏时 FSidebar 整条不渲染

## 五、实施范围

| 改动 | 文件 |
|------|------|
| 依赖 | pubspec.yaml（+forui 0.25.0，已装） |
| Forui 主题 | 新建 `lib/ui/theme/forui_theme.dart` |
| 主题包裹 | `lib/main.dart`（FTheme 包裹 ShellView） |
| Shell 侧边栏 | `lib/ui/shell/shell_view.dart`（FSidebar 重做）、`lib/ui/shell/icon_bar.dart`（图标按钮微调） |
| 发现页组件 | `lib/features/discovery/presentation/discovery_view.dart`（FButton/FTextField/FCard/FLinearProgressIndicator） |
| 测试 | `test/ui/theme/`（FColors 映射断言）、`test/ui/shell/shell_view_test.dart`、`test/features/discovery/discovery_view_test.dart`（组件替换后渲染断言更新） |
| 文档 | README 技术栈表（+Forui） |

**不动**：core 层、controller/domain/data 逻辑、AppflowyColors 色板常量、窗口配置。

## 六、测试策略

- Forui 主题测试：FColors 映射断言（浅/深关键 token）
- Shell widget 测试：侧边栏渲染（FSidebar 组件树）、折叠、切换内容区
- 发现页测试：现有断言（错误提示、分组渲染 192.168.1.1/MySQL/8.0.41）在 Forui 组件下保持
- 全量：flutter analyze + flutter test + flutter build windows --release

## 七、非目标

- 不引入 Forui 的 CLI/theme 生成流程（主题手工构建，保持简单）
- 不替换 MaterialApp 根（共存过渡，避免路由/对话框重写）
- 不重做图标栏布局（结构已定，仅按钮样式微调）
