# ToolBox

**现代桌面工具箱，AppFlowy 风格界面，基于 Flutter 构建。**

ToolBox 是一款 Windows 桌面应用，采用 AppFlowy 风格的简洁界面与 VSCode 式顶部菜单导航。内置可插拔的工具框架，通过顶部「设置」菜单进入各功能页面，便于持续扩展。

[![Flutter](https://img.shields.io/badge/Flutter-3.44.8-02569B.svg)](https://github.com/shendongjuns/tool-box)
[![Platform](https://img.shields.io/badge/Platform-Windows-0078D6.svg)](https://github.com/shendongjuns/tool-box)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](https://github.com/shendongjuns/tool-box/blob/main/LICENSE)

## 特性

- **AppFlowy 风格界面** —— 系统标题栏 + 纯色窗口，顶部 VSCode 式菜单导航（hover 提亮、下拉面板），明暗主题，基于 Material 定制主题、微软雅黑字体与 [Forui](https://pub.dev/packages/forui) 组件库构建。
- **首页 + 设置菜单导航** —— 顶部「首页」常驻，点「设置」弹出下拉菜单进入各功能页面；多标签页架构预留。
- **可扩展工具框架** —— 每个工具实现统一的 `Tool` 接口并在集中注册表中登记，新增工具只需几行代码即可接入，自动出现在设置下拉菜单中。
- **数据存储于安装目录** —— 所有应用数据（配置/文件）存放于 exe 所在目录，无需配置。
- **明暗主题** —— 默认跟随系统深浅色，支持手动切换。

## 快速开始

### 环境要求

- [Flutter](https://docs.flutter.dev/get-started/install) **3.44+**（stable 通道）
- **Windows 10/11**（应用目标平台为 Windows 桌面）

### 源码运行

```bash
flutter pub get
flutter run -d windows
```

### 构建安装包

先构建 release 产物：

```bash
flutter build windows --release
```

再使用 [Inno Setup 6](https://jrsoftware.org/isinfo.php) 生成安装包（确保 `iscc` 已在 `PATH` 中）：

```bash
iscc /DAppVersion=1.2.0 .github/installer/toolbox.iss
```

安装脚本位于 `.github/installer/toolbox.iss`，安装包输出在 `output/` 目录下。推送 `v*` 标签时 GitHub Actions 自动构建并发布安装包（exe）与便携版（zip）。

## 技术栈

| 组件 | 选型 |
| ---- | ---- |
| UI 框架 | Flutter 3.44.8（Windows 桌面） |
| UI 组件库 | [Forui](https://pub.dev/packages/forui) 0.25.0（shadcn 风格组件库） |
| 主题 / 组件 | AppFlowy 风格界面（Material 定制主题 + 微软雅黑字体） |
| 窗口管理 | [window_manager](https://pub.dev/packages/window_manager) |
| 状态管理 | [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) 3.4.2（Riverpod） |
| 打包工具 | Inno Setup 6 + GitHub Actions |

## 项目结构

```
lib/
├── main.dart               # 入口（主题联动、首次启动引导）
├── registry/               # 工具接口、分类与集中注册表
│   ├── tool.dart           # Tool 接口，所有工具实现该接口
│   ├── tool_category.dart  # 工具分类枚举
│   └── toolbox_registry.dart  # 集中注册表 —— 在此登记工具
├── ui/                     # 框架壳
│   ├── shell/              # 顶部菜单导航（首页/设置下拉）+ 内容区
│   ├── theme/              # AppFlowy 风格明暗主题（色板 + Forui 主题）
│   └── window/             # 窗口初始化（系统标题栏、纯色窗口）
└── features/               # 各业务工具
    └── settings/           # 设置工具（存储目录配置）
```

## 如何添加新工具

每个功能都是一个注册进注册表的工具，共三步：

1. **实现 `Tool` 接口**（`lib/registry/tool.dart`）：

   ```dart
   class MyTool extends Tool {
     @override
     String get id => 'tool-my-feature';

     @override
     String get name => '我的工具';

     @override
     String get description => '该工具的功能说明';

     @override
     ToolCategory get category => ToolCategory.system;

     @override
     Set<PlatformType> get supportedPlatforms => {PlatformType.windows};

     @override
     Widget buildContent(BuildContext context) => const MyView();
   }
   ```

2. **在 `ToolboxRegistry.registerAll()` 中注册**（`lib/registry/toolbox_registry.dart`）—— 一行即可：

   ```dart
   @override
   List<Tool> registerAll() => _tools; // 将你的工具实例加入 _tools 列表
   ```

3. **声明 `supportedPlatforms`** —— 注册表按当前平台过滤工具，未声明支持的工具会在不支持的平台上自动隐藏。

注册后工具自动出现在顶部「设置」下拉菜单中，点击进入对应页面，无需其他接线。

## 数据存储

所有应用数据（配置/文件）存放于 **exe 所在目录**（安装目录），无需额外配置。

## 许可证

[MIT](LICENSE) © shendongjuns
