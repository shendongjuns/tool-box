# ToolBox UI 重构（AppFlowy 风格）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 ToolBox 的 UI 从 macos_ui 风格重构为 AppFlowy 风格：三层布局（图标栏 + 可折叠侧边栏 + 限宽内容区）、AppFlowy 色板、Poppins 字体、纯色系统标题栏窗口。

**Architecture:** 仅改 UI 层。core（模型/引擎/指纹库）、registry 接口、discovery controller 逻辑保持不变。主题系统重写为 AppFlowy 色板（Material ThemeData），Shell 重写为三层布局，页面组件按 AppFlowy 规范（圆角 8、hover/选中态、限宽容器）。

**Tech Stack:** Flutter 3.44.8（Material 组件）、Poppins 字体（OFL）、window_manager（仅尺寸/居中）、flutter_riverpod 3.4.2。

## Global Constraints

- **不执行任何 git 提交**（用户指令）。任务以「测试/构建通过」为完成标准。
- 色板精确值（来自 AppFlowy 源码，不可更改）：背景 `#FFFFFF`；layer01 `#F8FAFF`；layer02 `#E4E8F5`；layer03 `#CED3E6`；文字 primary `#21232A` / secondary `#6F748C` / tertiary `#989EB7`；主色 `#0092D6`、hover `#0078C0`；边框 `#E4E8F5`、hover `#CED3E6`。
- 间距 4/6/8/12/16/20；圆角主用 8；阴影 small offset(0,2) blur16 `#1F000000`。
- 字体：Poppins（400/500/600/700 四个字重打包 `assets/fonts/`），中文系统 fallback，等宽用系统字体。
- UI 文案中文；代码标识符英文。
- 移除依赖：macos_ui、flutter_acrylic（pubspec 删除，代码中所有引用一并清除）。
- 窗口：系统标题栏（`TitleBarStyle.normal`），纯色背景由主题决定。
- 所有命令在项目根目录 `d:\project\ai\tool-box` 执行（PowerShell）。

---

### Task 1: 依赖调整与字体资产

**Files:**
- Modify: `pubspec.yaml`（移除 macos_ui/flutter_acrylic、添加 assets/fonts/ 字体声明）
- Create: `assets/fonts/`（4 个 Poppins ttf）
- Delete: `lib/ui/theme/toolbox_theme.dart`（Task 2 重写，先保留）

**Interfaces:**
- Produces: pubspec 无 macos_ui/flutter_acrylic 依赖；`assets/fonts/Poppins-{Regular,Medium,SemiBold,Bold}.ttf`；字体 family 名 `Poppins`（weight 400/500/600/700）

- [ ] **Step 1: 下载 Poppins 字体**

```powershell
New-Item -ItemType Directory -Force assets\fonts
$base = "https://raw.githubusercontent.com/google/fonts/main/ofl/poppins/"
$files = @("Poppins-Regular.ttf", "Poppins-Medium.ttf", "Poppins-SemiBold.ttf", "Poppins-Bold.ttf")
foreach ($f in $files) {
  Invoke-WebRequest -Uri ($base + $f) -OutFile ("assets\fonts\" + $f)
}
Get-ChildItem assets\fonts | Select-Object Name, Length
```

预期：4 个 ttf 文件存在且非空（各 ~100-200KB）。

- [ ] **Step 2: 修改 pubspec**

`pubspec.yaml` 移除 `macos_ui` 与 `flutter_acrylic` 两行依赖；添加：

```yaml
  fonts:
    - family: Poppins
      fonts:
        - asset: assets/fonts/Poppins-Regular.ttf
          weight: 400
        - asset: assets/fonts/Poppins-Medium.ttf
          weight: 500
        - asset: assets/fonts/Poppins-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Poppins-Bold.ttf
          weight: 700
```

- [ ] **Step 3: 验证**

```powershell
flutter pub get
```

预期：pub get 成功，无 macos_ui/flutter_acrylic 残留依赖（此时代码中仍有引用会编译失败，属预期 —— Task 2-4 逐步清除）。

**检查点**：Task 1 完成标准 —— pub get 成功、字体文件就位、pubspec.lock 无 macos_ui。

---

### Task 2: 主题系统重写（AppFlowy 色板）

**Files:**
- Create: `lib/ui/theme/appflowy_colors.dart`、`lib/ui/theme/appflowy_theme.dart`
- Delete: `lib/ui/theme/toolbox_theme.dart`（旧 macos_ui 主题）
- Modify: `lib/ui/theme/theme_controller.dart`（保留原样，仅确认无 macos_ui 引用）
- Test: `test/ui/theme/appflowy_theme_test.dart`

**Interfaces:**
- Consumes: Task 1 的 Poppins 字体；`themeControllerProvider`（保留）
- Produces:
  - `class AppflowyColors`（静态色板常量：背景/层/文字/主色/边框/功能色，浅色与深色各一套）
  - `class AppflowyTheme { static ThemeData light(); static ThemeData dark(); }`（Material ThemeData：colorScheme、typography(Poppins)、组件主题）
  - `class AppflowySpacing`（4/6/8/12/16/20 常量）、`class AppflowyRadius`（4/6/8/12/16/20 常量）

- [ ] **Step 1: 写失败测试**

创建 `test/ui/theme/appflowy_theme_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/ui/theme/appflowy_colors.dart';
import 'package:toolbox/ui/theme/appflowy_theme.dart';

void main() {
  test('浅色主题关键色值与 AppFlowy 色板一致', () {
    final theme = AppflowyTheme.light();
    expect(theme.colorScheme.surface, AppflowyColors.light.surface);
    expect(theme.colorScheme.primary, const Color(0xFF0092D6));
    expect(theme.colorScheme.onSurface, const Color(0xFF21232A));
  });

  test('深色主题存在且色板翻转', () {
    final theme = AppflowyTheme.dark();
    expect(theme.colorScheme.surface, AppflowyColors.dark.surface);
    expect(theme.colorScheme.primary, const Color(0xFF0092D6));
    expect(theme.colorScheme.brightness, Brightness.dark);
  });

  test('间距与圆角常量精确', () {
    expect(AppflowySpacing.xs, 4);
    expect(AppflowySpacing.m, 8);
    expect(AppflowySpacing.xxl, 20);
    expect(AppflowyRadius.m, 8);
  });

  test('Typography 使用 Poppins', () {
    final theme = AppflowyTheme.light();
    expect(theme.textTheme.titleLarge?.fontFamily, 'Poppins');
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Poppins');
  });
}
```

- [ ] **Step 2: 运行确认失败**

```powershell
flutter test test/ui/theme/appflowy_theme_test.dart
```

预期：编译失败（类不存在）。

- [ ] **Step 3: 实现色板与主题**

创建 `lib/ui/theme/appflowy_colors.dart`：

```dart
import 'package:flutter/material.dart';

/// AppFlowy 色板常量（浅色/深色各一套）。
/// 来源：AppFlowy 主题源码（primitive + semantic token）。
class AppflowyColors {
  const AppflowyColors._({
    required this.surface,
    required this.layer01,
    required this.layer02,
    required this.layer03,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.primary,
    required this.primaryHover,
    required this.border,
    required this.borderHover,
    required this.success,
    required this.warning,
    required this.error,
  });

  final Color surface;
  final Color layer01;
  final Color layer02;
  final Color layer03;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color primary;
  final Color primaryHover;
  final Color border;
  final Color borderHover;
  final Color success;
  final Color warning;
  final Color error;

  static const light = AppflowyColors._(
    surface: Color(0xFFFFFFFF),
    layer01: Color(0xFFF8FAFF),
    layer02: Color(0xFFE4E8F5),
    layer03: Color(0xFFCED3E6),
    textPrimary: Color(0xFF21232A),
    textSecondary: Color(0xFF6F748C),
    textTertiary: Color(0xFF989EB7),
    primary: Color(0xFF0092D6),
    primaryHover: Color(0xFF0078C0),
    border: Color(0xFFE4E8F5),
    borderHover: Color(0xFFCED3E6),
    success: Color(0xFF48A982),
    warning: Color(0xFFE0A046),
    error: Color(0xFFE85D5D),
  );

  static const dark = AppflowyColors._(
    surface: Color(0xFF21232A),
    layer01: Color(0xFF272930),
    layer02: Color(0xFF32343F),
    layer03: Color(0xFF3D404F),
    textPrimary: Color(0xFFF8FAFF),
    textSecondary: Color(0xFFB5BBD3),
    textTertiary: Color(0xFF989EB7),
    primary: Color(0xFF4EC1FF),
    primaryHover: Color(0xFF80D2FF),
    border: Color(0xFF3D404F),
    borderHover: Color(0xFF54596E),
    success: Color(0xFF71BD9F),
    warning: Color(0xFFE8A24E),
    error: Color(0xFFF27676),
  );
}

/// 间距常量（AppFlowy spacing token）。
class AppflowySpacing {
  const AppflowySpacing._();
  static const double xs = 4;
  static const double s = 6;
  static const double m = 8;
  static const double l = 12;
  static const double xl = 16;
  static const double xxl = 20;
}

/// 圆角常量（AppFlowy radius token）。
class AppflowyRadius {
  const AppflowyRadius._();
  static const double xs = 4;
  static const double s = 6;
  static const double m = 8;
  static const double l = 12;
  static const double xl = 16;
  static const double xxl = 20;
}
```

创建 `lib/ui/theme/appflowy_theme.dart`：

```dart
import 'package:flutter/material.dart';
import 'appflowy_colors.dart';

/// AppFlowy 风格主题：Material ThemeData 定制。
class AppflowyTheme {
  AppflowyTheme._();

  static ThemeData light() => _build(Brightness.light, AppflowyColors.light);

  static ThemeData dark() => _build(Brightness.dark, AppflowyColors.dark);

  static ThemeData _build(Brightness brightness, AppflowyColors c) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: Colors.white,
      primaryContainer: c.layer02,
      onPrimaryContainer: c.textPrimary,
      secondary: c.primary,
      onSecondary: Colors.white,
      error: c.error,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.textPrimary,
      outline: c.border,
      outlineVariant: c.layer02,
    );

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: c.surface,
      fontFamily: 'Poppins',
      textTheme: TextTheme(
        headlineLarge: TextStyle(
            fontSize: 28, fontWeight: FontWeight.w700, color: c.textPrimary),
        titleLarge: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w600, color: c.textPrimary),
        titleMedium: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary),
        bodyLarge: TextStyle(fontSize: 15, color: c.textPrimary),
        bodyMedium: TextStyle(fontSize: 14, color: c.textPrimary),
        bodySmall: TextStyle(fontSize: 12, color: c.textSecondary),
        labelMedium: TextStyle(fontSize: 12, color: c.textTertiary),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppflowyRadius.m),
          side: BorderSide(color: c.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppflowyRadius.m),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppflowyRadius.m),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppflowyRadius.m),
          borderSide: BorderSide(color: c.primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppflowyRadius.m),
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: AppflowySpacing.xl, vertical: AppflowySpacing.m),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          side: BorderSide(color: c.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppflowyRadius.m),
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: AppflowySpacing.xl, vertical: AppflowySpacing.m),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 删除旧主题并运行测试**

```powershell
Remove-Item lib\ui\theme\toolbox_theme.dart
flutter test test/ui/theme/appflowy_theme_test.dart
```

预期：4 个测试全部 PASS（此时 shell/discovery 引用旧主题会编译失败，属预期 —— Task 4-5 修复）。

**检查点**：Task 2 完成标准 —— 主题测试全绿、旧主题文件已删、lib/ui/theme 下无 macos_ui import。

---

### Task 3: 窗口简化与主入口 MaterialApp 化

**Files:**
- Modify: `lib/ui/window/app_window.dart`（移除 flutter_acrylic、系统标题栏）
- Modify: `lib/main.dart`（MacosApp → MaterialApp + AppflowyTheme）

**Interfaces:**
- Consumes: Task 2 的 `AppflowyTheme.light()/dark()`、`themeControllerProvider`
- Produces: `initAppWindow()` 保持签名不变（1200×800 居中、最小 900×600、系统标题栏、标题 ToolBox）

- [ ] **Step 1: 重写 app_window.dart**

```dart
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 初始化应用窗口：系统标题栏、1200×800 居中、最小 900×600。
Future<void> initAppWindow() async {
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1200, 800),
    minimumSize: Size(900, 600),
    center: true,
    title: 'ToolBox',
    titleBarStyle: TitleBarStyle.normal,
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
```

- [ ] **Step 2: 重写 main.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/ui/shell/shell_view.dart';
import 'package:toolbox/ui/theme/appflowy_theme.dart';
import 'package:toolbox/ui/theme/theme_controller.dart';
import 'package:toolbox/ui/window/app_window.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initAppWindow();
  runApp(const ProviderScope(child: ToolBoxApp()));
}

class ToolBoxApp extends StatelessWidget {
  const ToolBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final themeMode = ref.watch(themeControllerProvider);
      return MaterialApp(
        title: 'ToolBox',
        theme: AppflowyTheme.light(),
        darkTheme: AppflowyTheme.dark(),
        themeMode: themeMode,
        debugShowCheckedModeBanner: false,
        home: const ShellView(),
      );
    });
  }
}
```

（此步编译会因 shell_view 仍引用 macos_ui 失败，属预期 —— Task 4 重写 Shell。）

- [ ] **Step 3: 编译验证（预期失败的引用清单确认）**

```powershell
flutter analyze
```

预期：报错全部集中在 `lib/ui/shell/shell_view.dart` 与 `lib/features/discovery/presentation/discovery_view.dart` 的 macos_ui 引用。确认无其他文件引用 macos_ui（`Grep "macos_ui"` 应只命中这两个文件 + 测试）。

**检查点**：Task 3 完成标准 —— app_window/main 无 macos_ui 引用，analyze 剩余报错仅限待重构文件。

---

### Task 4: Shell 三层布局重构

**Files:**
- Create: `lib/ui/shell/icon_bar.dart`
- Rewrite: `lib/ui/shell/shell_view.dart`
- Modify: `lib/ui/shell/navigation_controller.dart`（保留，确认无 macos_ui 引用）
- Test: `test/ui/shell/shell_view_test.dart`（重写）

**Interfaces:**
- Consumes: Task 2 主题；Task 6 注册表（`toolboxRegistryProvider`、`ToolRegistry.availableTools()`）；`selectedToolProvider`/`sidebarExpandedProvider`（保留）
- Produces:
  - `class IconBar extends StatelessWidget`（宽 48：顶部 logo 图标、折叠开关按钮、底部设置占位）
  - `class ShellView extends ConsumerWidget`（Row：IconBar + 侧边栏(可折叠) + Expanded 内容区）

- [ ] **Step 1: 写失败测试**

创建 `test/ui/shell/shell_view_test.dart`（重写）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/registry/platform_type.dart';
import 'package:toolbox/registry/tool.dart';
import 'package:toolbox/registry/tool_category.dart';
import 'package:toolbox/registry/tool_registry.dart';
import 'package:toolbox/registry/toolbox_registry.dart';
import 'package:toolbox/ui/shell/shell_view.dart';
import 'package:toolbox/ui/theme/appflowy_theme.dart';

class _TestTool extends Tool {
  _TestTool(this._id, this._name, this._category);
  final String _id;
  final String _name;
  final ToolCategory _category;

  @override
  String get id => _id;
  @override
  String get name => _name;
  @override
  String get description => '测试工具';
  @override
  ToolCategory get category => _category;
  @override
  Set<PlatformType> get supportedPlatforms => {PlatformType.windows};
  @override
  Widget buildContent(BuildContext context) => Center(child: Text('内容区:$_name'));
}

class _TestRegistry extends ToolRegistry {
  @override
  List<Tool> registerAll() => [
        _TestTool('t1', '工具一', ToolCategory.database),
        _TestTool('t2', '工具二', ToolCategory.other),
      ];
}

void main() {
  Widget buildApp() => ProviderScope(
        overrides: [
          toolboxRegistryProvider.overrideWith((ref) => _TestRegistry()),
        ],
        child: MaterialApp(
          theme: AppflowyTheme.light(),
          home: const ShellView(),
        ),
      );

  testWidgets('图标栏常驻，侧边栏渲染分类与工具项', (tester) async {
    await tester.pumpWidget(buildApp());
    expect(find.text('数据库管理'), findsOneWidget);
    expect(find.text('工具一'), findsOneWidget);
    expect(find.text('工具二'), findsOneWidget);
  });

  testWidgets('点击工具项切换内容区', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.tap(find.text('工具一'));
    await tester.pumpAndSettle();
    expect(find.text('内容区:工具一'), findsOneWidget);
  });

  testWidgets('折叠按钮隐藏侧边栏、内容区占满', (tester) async {
    await tester.pumpWidget(buildApp());
    expect(find.text('工具一'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.menu_open));
    await tester.pumpAndSettle();
    expect(find.text('工具一'), findsNothing);
    // 再点一次展开
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('工具一'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行确认失败**

```powershell
flutter test test/ui/shell/shell_view_test.dart
```

预期：编译失败（ShellView 仍有 macos_ui 引用或类不存在）。

- [ ] **Step 3: 实现 IconBar**

创建 `lib/ui/shell/icon_bar.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'navigation_controller.dart';

/// 左侧图标栏（48px 常驻）：顶部 logo、折叠开关、底部设置。
class IconBar extends ConsumerWidget {
  const IconBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expanded = ref.watch(sidebarExpandedProvider);
    final toggle = ref.read(sidebarExpandedProvider.notifier);
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: 48,
      color: colors.surface,
      child: Column(
        children: [
          const SizedBox(height: 12),
          // 应用图标
          Icon(Icons.construction, size: 24, color: colors.primary),
          const SizedBox(height: 16),
          // 折叠开关
          IconButton(
            icon: Icon(
              expanded ? Icons.menu_open : Icons.menu,
              size: 20,
              color: colors.onSurfaceVariant,
            ),
            tooltip: expanded ? '收起侧边栏' : '展开侧边栏',
            onPressed: () => toggle.state = !expanded,
          ),
          const Spacer(),
          // 设置入口（占位）
          IconButton(
            icon: Icon(Icons.settings_outlined,
                size: 20, color: colors.onSurfaceVariant),
            tooltip: '设置',
            onPressed: () {},
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 重写 ShellView**

重写 `lib/ui/shell/shell_view.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/registry/tool.dart';
import 'package:toolbox/registry/tool_category.dart';
import 'package:toolbox/registry/tool_registry.dart';
import 'package:toolbox/registry/toolbox_registry.dart';
import 'package:toolbox/ui/theme/appflowy_colors.dart';
import 'icon_bar.dart';
import 'navigation_controller.dart';

/// AppFlowy 风格三层布局：图标栏 + 可折叠侧边栏 + 内容区。
class ShellView extends ConsumerWidget {
  const ShellView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(toolboxRegistryProvider);
    final tools = registry.availableTools();
    final selected = ref.watch(selectedToolProvider);
    final expanded = ref.watch(sidebarExpandedProvider);

    final grouped = <ToolCategory, List<Tool>>{};
    for (final t in tools) {
      grouped.putIfAbsent(t.category, () => []).add(t);
    }

    return Row(
      children: [
        const IconBar(),
        if (expanded) SidebarPanel(grouped: grouped, selected: selected),
        Expanded(
          child: Container(
            color: Theme.of(context).colorScheme.surface,
            child: selected?.buildContent(context) ??
                const Center(child: Text('未选择工具')),
          ),
        ),
      ],
    );
  }
}

/// 侧边栏面板：分类 → 工具两级列表。
class SidebarPanel extends ConsumerWidget {
  const SidebarPanel({super.key, required this.grouped, required this.selected});

  final Map<ToolCategory, List<Tool>> grouped;
  final Tool? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: 250,
      color: scheme.surface,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppflowySpacing.l),
        children: [
          for (final entry in grouped.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(AppflowySpacing.xl,
                  AppflowySpacing.m, AppflowySpacing.xl, AppflowySpacing.s),
              child: Text(
                entry.key.displayName,
                style: textTheme.labelMedium,
              ),
            ),
            for (final tool in entry.value)
              _ToolItem(
                tool: tool,
                selected: tool.id == selected?.id,
                onTap: () =>
                    ref.read(selectedToolProvider.notifier).select(tool),
              ),
            const SizedBox(height: AppflowySpacing.m),
          ],
        ],
      ),
    );
  }
}

/// 侧边栏工具项：圆角 8，hover layer01，选中 layer02 + 主色文字。
class _ToolItem extends StatefulWidget {
  const _ToolItem({
    required this.tool,
    required this.selected,
    required this.onTap,
  });

  final Tool tool;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ToolItem> createState() => _ToolItemState();
}

class _ToolItemState extends State<_ToolItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // 深浅色模式取对应色板的 layer 值
    final palette = Theme.of(context).brightness == Brightness.dark
        ? AppflowyColors.dark
        : AppflowyColors.light;
    final bg = widget.selected
        ? scheme.primaryContainer
        : _hovered
            ? palette.layer01
            : Colors.transparent;
    final fg = widget.selected
        ? scheme.primary
        : scheme.onSurfaceVariant;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(AppflowyRadius.m),
        child: Container(
          margin: const EdgeInsets.symmetric(
              horizontal: AppflowySpacing.m, vertical: 2),
          padding: const EdgeInsets.symmetric(
              horizontal: AppflowySpacing.m, vertical: AppflowySpacing.s),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppflowyRadius.m),
          ),
          child: Row(
            children: [
              Icon(_iconFor(widget.tool.category), size: 16, color: fg),
              const SizedBox(width: AppflowySpacing.m),
              Expanded(
                child: Text(
                  widget.tool.name,
                  style: textTheme.bodyMedium?.copyWith(
                    color: fg,
                    fontWeight:
                        widget.selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(ToolCategory category) => switch (category) {
        ToolCategory.data => Icons.data_object_outlined,
        ToolCategory.database => Icons.storage_outlined,
        ToolCategory.text => Icons.text_fields,
        ToolCategory.encode => Icons.code,
        ToolCategory.system => Icons.settings_outlined,
        ToolCategory.other => Icons.widgets_outlined,
      };
}
```

- [ ] **Step 5: 运行测试确认通过**

```powershell
flutter test test/ui/shell/shell_view_test.dart
```

预期：3 个测试全部 PASS。

- [ ] **Step 6: 编译验证**

```powershell
flutter analyze
```

预期：剩余报错仅限 discovery_view.dart 的 macos_ui 引用（Task 5 修复）。

**检查点**：Task 4 完成标准 —— shell 测试全绿、lib/ui/shell 无 macos_ui 引用、analyze 仅剩 discovery 报错。

---

### Task 5: 发现工具页面重构

**Files:**
- Rewrite: `lib/features/discovery/presentation/discovery_view.dart`
- Modify: `test/features/discovery/discovery_view_test.dart`（MacosApp → MaterialApp + AppflowyTheme）

**Interfaces:**
- Consumes: Task 2 主题；`discoveryControllerProvider`（保留，状态机不变）
- Produces: `DiscoveryView extends ConsumerWidget`（AppFlowy 页面风格：限宽容器、标题区、输入区、结果卡片分组）

- [ ] **Step 1: 更新 View 测试**

`test/features/discovery/discovery_view_test.dart`：将两处 `MacosApp(theme: ToolboxTheme.light(), ...)` 替换为 `MaterialApp(theme: AppflowyTheme.light(), ...)`，import 相应替换（删除 macos_ui import，添加 appflowy_theme）。其余断言不变（输入错误提示、分组渲染 `192.168.1.1`/`MySQL`/`8.0.41`）。

- [ ] **Step 2: 运行确认失败**

```powershell
flutter test test/features/discovery/discovery_view_test.dart
```

预期：编译失败（DiscoveryView 仍有 macos_ui 引用）。

- [ ] **Step 3: 重写 DiscoveryView**

重写 `lib/features/discovery/presentation/discovery_view.dart`，按 AppFlowy 页面规范：

- 外层：`Center` + `ConstrainedBox(maxWidth: 880)` + `SingleChildScrollView`（页面容器限宽居中）
- 标题区：`Text('数据库发现', style: headlineLarge)` + 说明文字（bodySmall tertiary 色）
- 输入区：`TextField`（目标，AppflowyTheme 已定制边框）+ 超时 `DropdownButton` + 扫描/停止按钮（`ElevatedButton`/`OutlinedButton` 换用主题自带样式，删除 PushButton）
- 进度区：`LinearProgressIndicator(value: done/total)` + 计数文字
- 结果区：主机分组卡片（`Card` 主题已定制）+ 每行端口/服务图标/类型/版本/复制按钮（`IconButton`）
- 空状态/错误状态保持原语义（文案不变）
- 删除 macos_ui import 与 `_iconFor` 中的组件依赖，全部 Material 组件

- [ ] **Step 4: 运行测试确认通过**

```powershell
flutter test test/features/discovery/discovery_view_test.dart
```

预期：全部 PASS。

**检查点**：Task 5 完成标准 —— view 测试全绿、lib/ 下无 macos_ui 残留引用。

---

### Task 6: 全量验证与收尾

**Files:**
- Modify: `README.md`（技术栈表移除 macos_ui，UI 描述更新为 AppFlowy 风格）
- Modify: `pubspec.yaml`（确认最终状态）

- [ ] **Step 1: 全量静态检查与测试**

```powershell
Grep "macos_ui" lib test pubspec.yaml   # 应为空
flutter analyze
flutter test
```

预期：无 macos_ui 残留；analyze 0 issues；全部测试通过。

- [ ] **Step 2: Release 构建**

```powershell
flutter build windows --release
```

预期：构建成功，产出 `build\windows\x64\runner\Release\toolbox.exe`。

- [ ] **Step 3: 启动冒烟**

```powershell
flutter run -d windows
```

预期：应用启动无崩溃（系统标题栏、纯色背景、三层布局）。视觉效果清单写入任务报告留用户验收：
① 系统标题栏 + 纯色背景 ② 图标栏/侧边栏/内容区三层布局 ③ 侧边栏折叠切换 ④ 深色模式 ⑤ 发现页标题/输入框/卡片观感 ⑥ 字体统一为 Poppins。

- [ ] **Step 4: README 更新**

README 技术栈表格：移除 macos_ui 行，UI 描述改为「AppFlowy 风格界面（Material 定制主题 + Poppins 字体）」，特性列表同步更新（亚克力窗口 → 纯色系统窗口）。

**检查点**：Task 6 完成标准 —— 全量验证通过、README 一致、无残留引用。

---

## Self-Review 记录

- **Spec 覆盖**：设计文档各节均有对应任务 —— 依赖/字体(Task 1)、主题(Task 2)、窗口/入口(Task 3)、Shell 三层布局(Task 4)、发现页(Task 5)、验证/README(Task 6)。
- **占位符检查**：无 TBD；关键代码块完整（色板全量、主题实现全量、Shell 结构全量、测试全量）。
- **类型一致性**：`AppflowyColors.light/dark`、`AppflowyTheme.light()/dark()`、`AppflowySpacing`、`AppflowyRadius` 在任务间签名一致；`initAppWindow`/`themeControllerProvider`/`selectedToolProvider`/`sidebarExpandedProvider`/`toolboxRegistryProvider` 签名不变。
- **已知风险**：深色模式下 hover 色（Task 4 已标注按 brightness 分支）；CardThemeData 在 Flutter 3.44 的 API 名（CardTheme vs CardThemeData）——若编译报错按版本调整。
