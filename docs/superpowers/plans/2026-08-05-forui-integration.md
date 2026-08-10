# ToolBox Forui 组件库集成实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 引入 Forui 0.25.0 组件库，替换 Material 默认组件（按钮/输入框/卡片/进度条/侧边栏），解决「组件不够精致」观感问题。

**Architecture:** MaterialApp 保留 + `FTheme` 包裹 Shell（共存过渡）。Appflowy 色板映射到 Forui FColors token（色板值不变）。Shell 侧边栏用 `FSidebar/FSidebarGroup/FSidebarItem` 重做；发现页控件换 Forui 组件。core/controller 逻辑不动。

**Tech Stack:** Flutter 3.44.8、forui 0.25.0（已装）、flutter_riverpod 3.4.2。

## Global Constraints

- **不执行任何 git 提交**（用户指令）。任务以「测试/构建通过」为完成标准。
- FColors 色板映射（精确值，来自设计文档，不可更改）：background 浅`#FFFFFF`/深`#21232A`；foreground 浅`#21232A`/深`#F8FAFF`；primary 浅`#0092D6`/深`#4EC1FF`；primaryForeground `#FFFFFF`；secondary 浅`#E4E8F5`/深`#32343F`；muted 浅`#F8FAFF`/深`#272930`；mutedForeground `#989EB7`；card 同 background；border 浅`#E4E8F5`/深`#3D404F`；destructive 浅`#E85D5D`/深`#F27676`。
- UI 文案中文（现有文案不变）；代码标识符英文。
- Forui 源码位于本地 pub cache：`%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\forui-0.25.0\`（API 以本地源码为准，实现时先读源码确认构造参数）。
- 不动：lib/core/、lib/registry/、discovery controller/domain/data、AppflowyColors 常量、窗口配置。
- 所有命令在项目根目录 `d:\project\ai\tool-box` 执行（PowerShell）。

---

### Task 1: Forui 主题构建（forui_theme.dart）

**Files:**
- Create: `lib/ui/theme/forui_theme.dart`
- Test: `test/ui/theme/forui_theme_test.dart`

**Interfaces:**
- Consumes: `AppflowyColors.light/dark`（lib/ui/theme/appflowy_colors.dart，字段：surface/layer01/layer02/layer03/textPrimary/textSecondary/textTertiary/primary/primaryHover/border/borderHover/success/warning/error）
- Produces: `FThemeData buildForuiTheme(Brightness brightness)` —— 按 Global Constraints 的 FColors 映射构建；typography/样式用 Forui 默认（`FThemeData` 构造缺失项用默认值）

- [ ] **Step 1: 读 Forui 源码确认 FThemeData 构造**

```powershell
$CACHE = "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\forui-0.25.0"
Get-Content "$CACHE\lib\src\theme\theme_data.dart" | Select-Object -First 120
```

确认：`FThemeData` 构造参数（必填/可选）、`FColors` 构造参数、`FTypography`/`FStyle` 构造方式、`FThemeData` 是否有 `FThemeData.light()/dark()` 工厂。

- [ ] **Step 2: 写失败测试**

创建 `test/ui/theme/forui_theme_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:toolbox/ui/theme/forui_theme.dart';

void main() {
  test('浅色主题 FColors 映射精确', () {
    final theme = buildForuiTheme(Brightness.light);
    expect(theme.colors.background, const Color(0xFFFFFFFF));
    expect(theme.colors.foreground, const Color(0xFF21232A));
    expect(theme.colors.primary, const Color(0xFF0092D6));
    expect(theme.colors.secondary, const Color(0xFFE4E8F5));
    expect(theme.colors.muted, const Color(0xFFF8FAFF));
    expect(theme.colors.mutedForeground, const Color(0xFF989EB7));
    expect(theme.colors.border, const Color(0xFFE4E8F5));
  });

  test('深色主题 FColors 映射精确', () {
    final theme = buildForuiTheme(Brightness.dark);
    expect(theme.colors.background, const Color(0xFF21232A));
    expect(theme.colors.foreground, const Color(0xFFF8FAFF));
    expect(theme.colors.primary, const Color(0xFF4EC1FF));
    expect(theme.colors.secondary, const Color(0xFF32343F));
    expect(theme.colors.muted, const Color(0xFF272930));
    expect(theme.colors.border, const Color(0xFF3D404F));
  });

  test('深浅主题 primaryForeground 为白', () {
    expect(buildForuiTheme(Brightness.light).colors.primaryForeground,
        const Color(0xFFFFFFFF));
    expect(buildForuiTheme(Brightness.dark).colors.primaryForeground,
        const Color(0xFFFFFFFF));
  });
}
```

- [ ] **Step 3: 运行确认失败**

```powershell
flutter test test/ui/theme/forui_theme_test.dart
```

预期：编译失败（buildForuiTheme 不存在）。

- [ ] **Step 4: 实现 forui_theme.dart**

创建 `lib/ui/theme/forui_theme.dart`（按 Step 1 确认的 FThemeData API 构建）：

```dart
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'appflowy_colors.dart';

/// 构建 Forui 主题：Appflowy 色板映射到 FColors token。
/// 样式（typography/style）用 Forui 默认值，仅定制色板。
FThemeData buildForuiTheme(Brightness brightness) {
  final c = brightness == Brightness.dark
      ? AppflowyColors.dark
      : AppflowyColors.light;

  final colors = FColors(
    brightness: brightness,
    barrier: Colors.black54,
    background: c.surface,
    foreground: c.textPrimary,
    primary: c.primary,
    primaryForeground: Colors.white,
    secondary: c.layer02,
    secondaryForeground: c.textPrimary,
    muted: c.layer01,
    mutedForeground: c.textTertiary,
    destructive: c.error,
    destructiveForeground: Colors.white,
    error: c.error,
    errorForeground: Colors.white,
    card: c.surface,
    border: c.border,
  );

  // FThemeData 的其余构造参数（typography/style/hapticFeedback 等）按
  // forui 0.25.0 实际构造签名补全，样式用默认值（参考 FThemeData.dark()/
  // light() 工厂或 FBasicTheme 的默认构建）。
  return FThemeData(
    colors: colors,
    // 其余参数按本地源码确认后补全
  );
}
```

注意：FThemeData 构造若有必填参数（typography 等），从 `FThemeData.dark()/light()` 工厂或 FBasicTheme 的默认构建获取（`FBasicTheme.dark()` 等），或按源码抄写默认 FTypography/FStyle 构建。若 FThemeData 工厂已可用（如 `FThemeData.dark()` 拷贝），以 `FThemeData` 拷贝工厂 + colors 覆盖方式实现更稳。

- [ ] **Step 5: 运行测试确认通过**

```powershell
flutter test test/ui/theme/forui_theme_test.dart
```

预期：3 个测试全部 PASS。

**检查点**：Task 1 完成标准 —— 主题测试全绿、buildForuiTheme 可构造 FThemeData（编译通过）、色板映射精确。

---

### Task 2: 主题包裹（main.dart）

**Files:**
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: Task 1 的 `buildForuiTheme(Brightness)`；`themeControllerProvider`（ThemeMode）
- Produces: `ToolBoxApp` 中 ShellView 被 `FTheme(data: ..., child: ...)` 包裹（深浅色随 themeController 的 ThemeMode 解析 Brightness）

- [ ] **Step 1: 修改 main.dart**

在 `ToolBoxApp` 的 build 中：读取 `themeMode`，将 `home: const ShellView()` 改为：

```dart
home: FTheme(
  data: buildForuiTheme(themeMode == ThemeMode.dark
      ? Brightness.dark
      : Brightness.light),
  child: const ShellView(),
),
```

（ThemeMode.system 时按 `MediaQuery.platformBrightnessOf(context)` 解析。）

- [ ] **Step 2: 编译验证**

```powershell
flutter analyze
flutter test test/ui/theme/
```

预期：analyze 通过；主题测试通过。

**检查点**：Task 2 完成标准 —— main.dart 编译通过、主题测试无回归。

---

### Task 3: Shell 侧边栏 FSidebar 重做

**Files:**
- Modify: `lib/ui/shell/shell_view.dart`（SidebarPanel/_ToolItem → FSidebar 组件）
- Modify: `test/ui/shell/shell_view_test.dart`（渲染断言适配 FSidebar 组件树）

**Interfaces:**
- Consumes: Task 1 主题；`selectedToolProvider`/`sidebarExpandedProvider`/`toolboxRegistryProvider` 不变
- Produces: 侧边栏渲染为 `FSidebar(children: [FSidebarGroup(title: 分类名, items: [FSidebarItem(icon, label, selected, onSelect)])])`；折叠逻辑不变（`sidebarExpandedProvider` 控制 FSidebar 是否渲染）

- [ ] **Step 1: 读 Forui sidebar 源码确认 API**

```powershell
$CACHE = "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\forui-0.25.0"
Get-Content "$CACHE\lib\src\widgets\sidebar\sidebar.dart" | Select-Object -First 60
Get-Content "$CACHE\lib\src\widgets\sidebar\sidebar_group.dart" | Select-Object -First 50
Get-Content "$CACHE\lib\src\widgets\sidebar\sidebar_item.dart" | Select-Object -First 50
```

确认：`FSidebar` 构造（child/children?）、`FSidebarGroup`（title/items）、`FSidebarItem`（icon/label/selected/onSelect?）的参数名。

- [ ] **Step 2: 修改 shell_view.dart**

- 删除 `SidebarPanel` 与 `_ToolItem`（自绘实现）
- 侧边栏区域替换为：

```dart
if (expanded)
  SizedBox(
    width: 250,
    child: FSidebar(
      children: [
        for (final entry in grouped.entries)
          FSidebarGroup(
            title: Text(entry.key.displayName),
            items: [
              for (final tool in entry.value)
                FSidebarItem(
                  icon: Icon(_iconFor(tool.category), size: 16),
                  label: Text(tool.name),
                  selected: tool.id == selected?.id,
                  onSelect: () =>
                      ref.read(selectedToolProvider.notifier).select(tool),
                ),
            ],
          ),
      ],
    ),
  ),
```

- `_iconFor` 保留（图标映射），外层布局（IconBar + 侧边栏 + 内容区）不变
- 若 FSidebar 需要 `FScaffold`/`FSidebarData` 包裹或样式参数，按源码 API 调整（如 `FSidebar.raw` 或 `FTheme` 已提供默认样式则直接用 FSidebar 构造）

- [ ] **Step 3: 更新测试**

`test/ui/shell/shell_view_test.dart`：现有 3 用例的断言（find.text('数据库管理')/('工具一')/('工具二')、点击切换、折叠）在 FSidebar 组件树中应仍然成立 —— 先运行，若 FSidebar 渲染文本方式不同（如 label 是 Widget），按实际渲染调整断言（用 find.text 目标保持一致）。

- [ ] **Step 4: 运行测试确认通过**

```powershell
flutter test test/ui/shell/shell_view_test.dart
```

预期：3 用例全部 PASS（必要时断言已按 FSidebar 渲染调整）。

**检查点**：Task 3 完成标准 —— shell 测试全绿、lib/ui/shell 无自绘 _ToolItem 残留。

---

### Task 4: 发现页组件替换

**Files:**
- Modify: `lib/features/discovery/presentation/discovery_view.dart`
- Modify: `test/features/discovery/discovery_view_test.dart`（如有必要适配 Forui 组件渲染）

**Interfaces:**
- Consumes: `discoveryControllerProvider`（不变）；Forui 主题
- Produces: DiscoveryView 组件替换 —— 扫描/停止按钮 `FButton.primary`/`FButton.outline`（或 FButton.secondary），目标输入框 `FTextField`，主机分组 `FCard`，进度 `FLinearProgressIndicator`，复制按钮 `FButton.icon` 或 IconButton 保留

- [ ] **Step 1: 读 Forui 按钮/输入框/卡片/进度条源码确认 API**

```powershell
$CACHE = "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\forui-0.25.0"
# button: lib/src/widgets/button/button.dart（FButton.primary/.outline 工厂）
# text_field: lib/src/widgets/text_field/text_field.dart（FTextField 构造：controller/label/hint）
# card: lib/src/widgets/card/card.dart（FCard 构造）
# progresses: lib/src/widgets/progresses/（FLinearProgressIndicator）
Get-ChildItem "$CACHE\lib\src\widgets\progresses" | Select-Object Name
```

确认各组件构造参数后实施替换。

- [ ] **Step 2: 修改 discovery_view.dart**

按确认的 API 替换组件（保持现有布局与中文文案不变）：
- `ElevatedButton`（扫描）→ `FButton.primary(onPress: ..., child: Text('扫描'))`
- `OutlinedButton`（停止）→ `FButton.outline(onPress: ..., child: Text('停止'))`
- `TextField` → `FTextField(controller: ..., label: Text('扫描目标'), hint: Text('例如 192.168.1.0/24'))`（error 提示语义保留：FTextField 若有 error 参数则用，否则保留外层错误文案 Text）
- `Card` → `FCard`
- `LinearProgressIndicator` → `FLinearProgressIndicator`（进度值参数按源码确认，如 `progress: double`）
- 复制 `IconButton` → 保留 IconButton 或 FButton.icon（按源码可用性）
- TextField 的 `onChanged` → FTextField 的 onChanged（或 controller + listener，按源码）

- [ ] **Step 3: 更新测试并运行**

```powershell
flutter test test/features/discovery/discovery_view_test.dart
```

预期：2 用例（错误提示、分组渲染 192.168.1.1/MySQL/8.0.41）PASS；若 FTextField 的输入交互测试（enterText）需要 controller 或不同挂载方式，按源码调整测试写法，断言目标（find.textContaining('无效') 等）不变。

- [ ] **Step 4: 全量回归**

```powershell
flutter test
```

预期：全部测试通过（含 core/controller/shell/主题）。

**检查点**：Task 4 完成标准 —— 发现页测试通过、全量测试无回归、lib/features 无 Material 默认按钮/输入框残留（除保留的 IconButton）。

---

### Task 5: 全量验证与收尾

**Files:**
- Modify: `README.md`（技术栈表 +Forui）

- [ ] **Step 1: 全量验证**

```powershell
flutter analyze
flutter test
flutter build windows --release
```

预期：analyze 0 issues、全部测试通过、release 构建成功（若遇 C1083 SDK bug：先 `Remove-Item .dart_tool\flutter_build -Recurse -Force`）。

- [ ] **Step 2: 启动冒烟**

```powershell
flutter run -d windows
```

预期：启动无崩溃。视觉验收清单写入报告：①侧边栏 FSidebar 观感（分组/选中/hover）②扫描按钮/输入框/卡片新观感 ③深浅色 ④整体「组件精致度」提升效果。

- [ ] **Step 3: README 更新**

README 技术栈表格添加 Forui 行（如 `| Forui | 0.25.0 | shadcn 风格组件库 |`），UI 描述补一句 Forui 组件库。README 保持中文。

**检查点**：Task 5 完成标准 —— 全量验证通过、README 一致。

---

## Self-Review 记录

- **Spec 覆盖**：Forui 主题(Task 1)、主题包裹(Task 2)、侧边栏重做(Task 3)、组件替换(Task 4)、验证/README(Task 5)。
- **占位符检查**：无 TBD；FColors 映射测试全量给出。
- **类型一致性**：`buildForuiTheme(Brightness) → FThemeData` 跨任务一致；`themeControllerProvider`/`sidebarExpandedProvider`/`selectedToolProvider`/`discoveryControllerProvider` 签名不变。
- **已知风险**：Forui 0.25.0 的组件构造参数（FThemeData/FButton/FTextField/FCard/FSidebar 等）以本地源码为准 —— 各任务 Step 1 均要求先读源码确认 API，再按确认结果实现（计划中已有明确指示）。
