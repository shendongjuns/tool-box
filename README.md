# ToolBox

**现代 Windows 桌面工具集，界面由 [ForUI](https://forui.dev) 构建，基于 Flutter。**

> **命名约定**：产品名统一写作 **ToolBox**（窗口标题、托盘提示、exe 名 `ToolBox.exe`、
> 安装包与快捷方式、文件属性都是它）。唯一的例外是 Dart 包名 `toolbox` ——
> 包名必须是合法的小写标识符，改它要动全仓库的 `package:toolbox/...` 导入，不值得。
> 因此看到 `package:toolbox/...` 或 `toolbox.iss` 这类**内部标识符**时不必纠正。

内置可插拔的工具框架：左侧栏按分类列出工具，打开过的页面全部保活，切换不丢状态。

[![Flutter](https://img.shields.io/badge/Flutter-3.47.4-02569B.svg)](https://github.com/shendongjuns/tool-box)
[![ForUI](https://img.shields.io/badge/ForUI-0.26-4f46e5.svg)](https://forui.dev)
[![Platform](https://img.shields.io/badge/Platform-Windows-0078D6.svg)](https://github.com/shendongjuns/tool-box)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](https://github.com/shendongjuns/tool-box/blob/main/LICENSE)

## 特性

- **ForUI 统一界面** —— 所有图标、组件、弹窗、提示都来自 ForUI；项目内不再有自研 UI 组件与自定义配色（色板用 ForUI 内置 neutral，字体族按中文字形配置）。
- **左侧栏导航，可收缩** —— 一级是工具分类（展开列出工具），收缩后只剩图标（64px）；底部为「设置 / 主题切换 / 版本号 / 收起」。
- **页面全部保活** —— 已打开的页面用 `IndexedStack` 承载，切换只改显隐、不重建，终端缓冲、表单输入、滚动位置都不会丢。
- **数据可靠** —— 写入采用「临时文件 + 原子替换 + 保留上一版」，进程被杀也不会写坏文件；读取时损坏会自动回退上一版，单条坏数据只跳过该条。
- **可扩展工具框架** —— 实现 `Tool` 接口并登记即可，自动出现在侧栏对应分类下。
- **明暗主题** —— 跟随系统 / 浅色 / 深色三态循环，选择持久化；Windows 原生标题栏同步跟随。
- **桌面端细节** —— 窗口位置与大小记忆、快捷键、Esc 关弹窗、全局错误兜底与落盘日志。

## 快速开始

### 环境要求

- [Flutter](https://docs.flutter.dev/get-started/install) **3.47+**（stable 通道，Dart 3.13+）
- **Windows 10/11**（应用目标平台为 Windows 桌面）

### 源码运行

```bash
flutter pub get
flutter run -d windows
```

### 构建与打包

```bash
flutter build windows --release
```

再用 [Inno Setup 6](https://jrsoftware.org/isinfo.php) 生成安装包（确保 `iscc` 已在 `PATH` 中）：

```bash
iscc /DAppVersion=1.5.0 .github/installer/toolbox.iss
```

安装脚本位于 `.github/installer/toolbox.iss`，输出在仓库根目录。推送 `v*` 标签时 GitHub Actions 自动构建并发布安装包（exe）与便携版（zip）。

> 安装包默认装到 **`%LOCALAPPDATA%\Programs\ToolBox`**（`PrivilegesRequired=lowest`，免管理员）。
> 这是刻意的选择：应用把数据写在程序目录旁的 `user/`，而 `C:\Program Files` 对普通用户不可写，
> 装在那里会导致保存静默失败。

## 技术栈

| 组件 | 选型 |
| ---- | ---- |
| UI 框架 | [ForUI](https://forui.dev) 0.26（含 `FLucideIcons` 图标） |
| 运行环境 | Flutter 3.47.4 / Dart 3.13.3（Windows 桌面） |
| 窗口管理 | [window_manager](https://pub.dev/packages/window_manager)（尺寸/位置记忆、标题栏明暗同步） |
| 系统托盘 | [tray_manager](https://pub.dev/packages/tray_manager)（托盘常驻、关窗最小化到托盘） |
| 状态管理 | [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) 3（`NotifierProvider`） |
| 文件选择 | [file_picker](https://pub.dev/packages/file_picker)（系统对话框） |
| SSH / SFTP | 内置 vendored [dartssh2](https://pub.dev/packages/dartssh2)（`lib/third_party/`） |
| 终端模拟 | 内置 vendored [xterm](https://pub.dev/packages/xterm)（`lib/third_party/`） |
| 打包 | Inno Setup 6 + GitHub Actions |

## 项目结构

```
lib/
├── main.dart                    # 入口：错误兜底 → 数据目录 → 日志 → 单实例 → 窗口 → 壳层
├── common/                      # 基础设施
│   ├── app_data.dart            # 数据目录（可写性探测 + 回退用户目录）
│   ├── app_log.dart             # 落盘日志（user/logs/app.log，1MB 轮转保留 3 份）
│   ├── app_meta.dart            # 应用名与版本号
│   ├── json_store_io.dart       # JSON 原子读写（tmp → prev → rename）
│   ├── json_file_recovery.dart  # 损坏文件留底（带时间戳的 .corrupt-bak）
│   ├── backup_service.dart      # 数据备份：导出 zip / 导入覆盖（含清单校验与留底）
│   ├── settings_store.dart      # settings.json
│   └── single_instance.dart     # 单实例检测 + 启动告警收集（含重启前主动释放锁）
├── features/
│   ├── monitor/                 # 系统监控采集（/proc + 标准命令，无需服务端代理）
│   ├── remote/                  # 远程管理：连接、SSH 会话、终端、SFTP、传输、监控
│   └── repository/              # 代码仓库管理：分组、Git/SVN、本地与远程拉取
├── registry/                    # 工具接口 / 分类 / 注册表（新增工具改这里）
└── ui/
    ├── shell/                   # 壳层：侧栏导航 + 页面宿主（IndexedStack）
    ├── theme/                   # ForUI 主题与布局常量
    ├── widgets/                 # 通用件：弹窗、轻提示、悬停提示、表单行、空状态、磁贴图标按钮
    └── window/                  # 窗口初始化、尺寸记忆、标题栏明暗同步、系统托盘、全局 Navigator
```

`assets/tray_icon.ico` 是系统托盘图标（内容同 `windows/runner/resources/app_icon.ico`，
`tray_manager` 按 `<exe>/data/flutter_assets/` 解析，故必须声明为资源）。

## 如何添加新工具

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

2. **在 `ToolboxRegistry.registerAll()` 中登记**（`lib/registry/toolbox_registry.dart`）：

   ```dart
   @override
   List<Tool> registerAll() => [
     MyTool(), // 加入此列表即可
   ];
   ```

3. **声明 `supportedPlatforms`** —— 注册表按当前平台过滤，未声明支持的工具自动隐藏。

登记后工具会自动出现在侧栏对应分类下；图标按 `toolIcon(tool.id)` 取（见 `shell_view.dart`）。

## 功能说明

### 代码仓库管理

- SVN / Git 仓库分组管理：地址复制、批量导入（自动识别类型与版本号）、排序与搜索。
- 分组可绑定本地文件夹并**本地拉取**：检出到「绑定文件夹/仓库名」，已有代码时执行 `svn update`（Git 跳过）。
- **远程拉取**：分组绑定 SSH 连接 + 远程目录后，一键在服务器上执行 `svn checkout/update`；SVN 需要认证时弹框输入账号密码，**多个仓库共用一次输入**。
- 依赖 **svn 命令行客户端**（SlikSVN，或 TortoiseSVN 勾选 command line client tools）；未安装时提示引导。

### 远程管理

- 保存 SSH 连接（名称/主机/端口/用户名/密码/私钥），支持一键**测试连接**；表单校验前移，必填项未填时「保存」置灰。
- 内置终端（支持中文输入法、鼠标悬停聚焦、窗口缩放自动重排），**同一连接可开多个会话**。
- 会话内三视图并存：**终端 / 文件 / 监控**，可拖拽调宽、各自可隐藏。
- 文件视图：SFTP 浏览目录，支持上传、下载、新建目录、删除、排序、**打开**（下载到临时目录后用系统程序打开）；上传下载为流式传输，支持并发、进度、取消与**任务持久化**。
- 监控视图：每秒采集 CPU / 内存 / 磁盘 / 负载 / 网络速率 / TOP 进程；装有 `npu-smi` 时展示昇腾 NPU 使用率。切到后台的会话会**自动暂停采集**，不打断前台。

### 窗口、侧栏与托盘

- **窗口默认 1200×800，每次打开都居中显示**。只记住**尺寸**（与最大化状态），
  不记住位置 —— 换显示器 / 拔掉外接屏后，旧坐标会把窗口开到看不见的地方。
- **侧栏宽度可拖拽**：把鼠标移到导航右缘（会出现一条细线），左右拖动即可，
  范围 180–420px，宽度会记住；底部按钮可一键收起为 64px 图标栏。
- **点右上角 × 时的行为默认是「每次询问」**：弹框让你选「最小化到托盘」还是
  「彻底退出」，可勾选「记住我的选择」把结果固定下来。「设置 → 关闭窗口时」
  里也能直接改成固定行为。
- 托盘交互：**单击图标**显示主窗口；**右键菜单**提供「显示主窗口 / 退出 ToolBox」。
- 若托盘初始化失败（例如图标资源缺失），会自动退化为「关闭即退出」，不会出现「点了 × 关不掉程序」。
- **退出是「秒退」**：选择「彻底退出」时先隐藏窗口（界面立刻消失），再清理托盘图标并结束进程；
  万一引擎拆除卡住，800ms 后强制结束，不会出现「界面卡住一会儿才退出」或关不掉的情况。

### 数据备份

「设置 → 数据备份」提供导出、导入与格式化，操作单位就是**整个数据目录**：

- **导出备份**：把数据目录里的全部内容（连接、设置、仓库分组、传输任务、日志）
  打包成一个 zip。文件名形如 `ToolBox-backup-20260918-1423.zip`，
  用任何解压工具都能打开查看。
- **导入备份**：用 zip 里的内容**覆盖**当前数据（是恢复，不是合并：
  备份里没有的数据会被清掉）。覆盖前会自动把当前数据留底到数据目录的
  `.pre-import/<时间戳>/`（保留最近 3 份），选错文件还能取回。
- **格式化数据**：清空全部数据（连接、设置、仓库分组、传输任务、日志），回到刚装好的状态。
  格式化**先强制备份**：会先导出一份 `ToolBox-backup-before-format-<时间戳>.zip`
  放到数据目录旁边，**备份没写成功就一个字节都不删**（这是硬约束，没有「跳过备份」的选项）。
  后悔时用「从 zip 恢复」选中那份备份即可还原。
- 导入 / 格式化完成后应用会**停止写盘并要求重启**（重启由程序自动完成），
  这是为了避免运行中的界面把刚变更的数据又覆盖回去。
- 压缩包里带一份 `backup-manifest.json` 清单，导入前先校验它：
  没有清单的 zip、损坏的 zip、来自更高版本格式的备份都会被拒绝，
  且**在校验通过之前不会碰任何数据**。条目里的目录穿越路径（`..`、绝对路径）会被丢弃。

### 快捷键

| 快捷键 | 作用 |
| --- | --- |
| `Ctrl + N` | 新建 SSH 连接 |
| `Ctrl + W` | 关闭当前会话 |
| `Ctrl + Tab` / `Ctrl + Shift + Tab` | 切换会话 |
| `Esc` | 关闭当前弹窗 |

终端获得焦点时，上述组合键会让给终端（例如 `Ctrl+W` 在 bash 里是删除前一个词）。

## 数据存储

数据**优先**放在 **exe 同级的 `user/`**（便携、便于整体备份）。
如果该位置不可写（例如程序被放进受保护目录），启动时会自动回退到 **`%APPDATA%\ToolBox\user`**，并弹窗明确告知——不会出现「保存了、下次启动却没了」的静默丢失。

| 文件 | 内容 |
| --- | --- |
| `user/settings.json` | 应用设置（主题模式、界面布局偏好、**窗口尺寸**、侧栏宽度、关闭行为） |
| `user/ssh_connections.json` | SSH 连接信息 |
| `user/repo_groups.json` | 仓库分组与仓库清单 |
| `user/transfer_tasks.json` | 传输任务历史 |
| `user/logs/app.log` | 运行日志（超过 1MB 轮转，保留 3 份历史） |
| `user/.pre-import/<时间戳>/` | 导入备份前自动留的数据副本（保留最近 3 份，可手工拷回） |
| `<数据目录的上一级>/ToolBox-backup-before-format-<时间戳>.zip` | 格式化前强制留下的备份 |

写入采用**原子替换**：先写 `*.tmp`，再把现有文件转存为 `*.prev`，最后 `rename` 覆盖——
任何时刻主文件都是完整的。读取时若主文件损坏，会自动回退 `*.prev`；确实无法恢复的坏文件
会改名留底为 `<原名>_<时间戳>.corrupt-bak`（时间戳精确到毫秒，同一毫秒内仍撞名时追加序号），
不会被覆盖或删除。

> **想整份带走？** 用「设置 → 数据备份 → 导出备份」生成 zip 即可；
> 换机后在新机器上「从 zip 恢复」并重启，连接、设置、仓库分组一并还原。

> ⚠️ **开发时注意**：便携模式下数据目录就在程序旁边，而调试构建的程序在
> `build/windows/x64/runner/Debug/` 下 —— 也就是说 **`flutter clean`（或删除 `build/`）
> 会把这批数据一起删掉**。需要清理构建产物时要么先「导出备份」，要么单独保留该 `user/` 目录。

> **关于连接密码**：按设计**明文**保存在 `user/ssh_connections.json`（不做加密，也不上云），
> 与「整份数据目录可整体备份」的定位一致；请妥善保管备份文件。
> 认证方式支持密码与私钥（OpenSSH / RSA / EC PEM）。
> 注：安装包会把数据放在用户可写目录（见「数据存储」），不会因权限问题静默写失败。

## 已知限制

- 不提供应用内更新：新版本直接下载安装包覆盖安装，**更新判断交给安装程序**，
  程序本身不再联网查版本（设置里也没有「检查更新」入口）。
- 连接密码明文存储（按设计，见「数据存储」）。
- 同时运行多个实例时会弹窗提醒（写入会互相覆盖），但不会强制单开。
- 中文界面，暂未做多语言。

## 许可证

[MIT](LICENSE) © shendongjuns
