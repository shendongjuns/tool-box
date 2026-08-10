# ToolBox v1.2.0 设计文档 — Flutter 架构重构

> 日期：2026-08-04
> 状态：已确认（待用户审阅）
> 目标：将 ToolBox 从 Kotlin + Compose Desktop 迁移到 Flutter，面向长期可维护与多平台预留。

---

## 一、背景与目标

原 ToolBox v1.1.0（Kotlin 2.3.0 + Compose Multiplatform Desktop）是 Windows 桌面工具箱，技术架构不再满足需求，整体迁移到 Flutter 重建。

**核心目标**：

1. **长远可维护** —— 分层清晰、职责单一、易于测试
2. **解耦** —— 工具与框架解耦，核心逻辑与 UI 解耦，平台能力抽象
3. **多平台预留** —— Flutter 全平台框架，本次仅实现 Windows，工具支持按平台声明，其他平台工具未来按需实现
4. **全新设计** —— 所有迁移功能重新设计，不参考原实现逻辑

## 二、范围决策（用户已确认）

| 原功能 | 决策 |
|--------|------|
| MySQL 备份 | **删除，不迁移** |
| ClickHouse 备份 | **删除，不迁移** |
| 数据库发现 | **保留并重构**（网段扫描，新逻辑） |
| 任务列表 | **删除** |
| 操作日志 | **删除** |
| 系统设置 | **删除** |

原框架代码（Gradle 结构、app/common/platform/tool-api/tools/test 模块、旧文档）**全部删除**。README.md 重写为开源项目风格。GitHub Actions 重建，仅 Windows 安装包流水线。

## 三、技术栈

| 层 | 选型 | 说明 |
|----|------|------|
| 框架 | Flutter 最新稳定版 | 目标：Windows 桌面 |
| UI | macos_ui + 官方 Cupertino 兜底 | 苹果设计语言 |
| 窗口 | window_manager + flutter_acrylic | 无边框、圆角、亚克力毛玻璃 |
| 状态/DI | flutter_riverpod（Riverpod 2.x） | 编译期安全 + 依赖注入 |
| 持久化 | shared_preferences（JSON） | 轻量配置，路径由平台层解析 |
| 网络 | dart:io（Socket/InternetAddress） | 扫描引擎，零第三方依赖 |
| 测试 | flutter_test + 纯 Dart test | core 层独立测试 |
| 打包 | Inno Setup（Setup.exe） | 无需签名证书、向导安装体验 |

## 四、项目结构

```
tool-box/                      # Flutter 工程根（原 Gradle 文件全部删除）
├── lib/
│   ├── main.dart              # 应用入口（窗口初始化、注册表装载）
│   ├── core/                  # 纯 Dart 内核（零 Flutter 依赖）
│   │   ├── models/            # 扫描模型（ScanTarget/ScanResult/ServiceInfo…）
│   │   ├── scanner/           # 扫描引擎（CIDR 展开、并发调度、超时控制）
│   │   └── protocols/         # 协议指纹库（可扩展 ServiceProbe 接口）
│   ├── ui/                    # 框架壳（macos_ui 定制主题、侧边栏、窗口）
│   ├── features/
│   │   └── discovery/         # 数据库发现工具
│   │       ├── domain/        # 工具声明 + 状态
│   │       ├── data/          # 引擎调用适配（平台网络能力检测）
│   │       └── presentation/  # 扫描界面（流式结果）
│   └── registry/              # Tool 接口 + 集中注册表（平台过滤）
├── test/                      # core 单测 + widget 测试
├── windows/                   # Flutter Windows 平台目录
├── pubspec.yaml
├── README.md                  # 重写（开源风格）
├── .github/workflows/release.yml  # 重建（Windows 安装包）
└── .gitignore                 # 重写（Flutter 标准）
```

## 五、框架层设计

### 5.1 窗口

- `window_manager`：无边框窗口，启动居中，最小尺寸 900×600
- `flutter_acrylic`：亚克力毛玻璃背景（Windows 11 Mica/Acrylic，Win10 自动降级）
- `MUIWindow` 提供标题栏与拖拽区

### 5.2 主题

macos_ui 主题定制，沿用验证过的 Apple 设计语言：`#F5F5F7` 暖灰白背景、`#007AFF` 主色，明暗双主题跟随系统。主题独立文件，UI 组件统一走 `MacosTheme`。预留手动切换深浅色。

### 5.3 工具接口与注册表

```dart
abstract class Tool {
  String get id;
  String get name;
  String get description;
  ToolCategory get category;
  Set<PlatformType> get supportedPlatforms;  // 平台声明
  Widget buildContent(BuildContext context);
}
```

- 注册表：`List<Tool> registerTools()` 集中注册，按当前平台过滤（`defaultTargetPlatform` + Web 检测），侧边栏只展示可用工具
- 平台检测：桌面平台可运行 Socket 工具；Web 不支持时对应工具自动隐藏
- `ToolCategory` 六分类（数据处理/数据库管理/文本/编解码/系统/其他）作为导航分类枚举保留，新工具按分类填充

### 5.4 导航

参考 macos_ui `MUISidebar` 重新设计：分类 → 工具两级，图标 + 文字，选中态高亮，支持折叠（固定图标模式），spring 动画。不沿用原 Compose 实现。

### 5.5 状态（Riverpod Provider 树）

- `windowProvider`（窗口状态）
- `toolRegistryProvider`（注册表）
- `themeProvider`（主题模式）
- feature 级 Provider 由各工具自己管理，不依赖框架层

## 六、数据库发现工具设计

### 6.1 功能定义

- 输入：单个 IP 或 CIDR 网段（如 `192.168.1.0/24`，实时校验）
- 输出：异步流式扫描结果，按主机分组展示
- 支持服务默认集（8 种服务 9 个端口）：MySQL(3306)、PostgreSQL(5432)、ClickHouse(8123/9000)、Redis(6379)、MongoDB(27017)、SQL Server(1433)、Oracle(1521)、Elasticsearch(9200)
- 不含连接/管理能力（扫描结果仅展示）

### 6.2 扫描引擎（core/scanner，纯 Dart）

- `ScanEngine`：目标解析（单 IP / CIDR 展开）→ 生成 `(host, port)` 任务对 → 信号量限流并发调度 → TCP connect + 超时 → `Stream<ScanResult>`
- 可配置：并发数（默认 50）、单端口超时（默认 1000ms）
- 取消：Stream 取消 / 取消令牌；进度事件（已完成/总数）
- 可测试性：Socket 通过抽象接口注入，单测用 fake socket

### 6.3 协议指纹库（core/protocols，可扩展）

```dart
abstract class ServiceProbe {
  int get port;
  ProbeResult probe(Socket socket);   // 发送探测包，解析服务类型+版本
}
```

- 每服务一个实现类：MySQL 握手包、Redis PING/INFO、PostgreSQL 认证协商、MongoDB 握手、CK/ES HTTP 响应头、Oracle 与 SQL Server 预登录包
- 两级识别：端口开放但无指纹命中 → 「开放 / 未知服务」；命中 → 服务类型 + 版本
- 新增服务 = 新建类 + 注册一行（与工具注册表同一模式）

### 6.4 数据流

```
presentation (Riverpod StreamProvider)
  → data 层 ScanService（注入 Socket 工厂、进度/取消桥接）
    → core ScanEngine → Stream<ScanResult>
      → UI 流式追加到结果列表 + 进度条
```

### 6.5 UI（重构，不沿用原版）

- 输入区：目标输入框（IP/CIDR 实时校验）、超时设置、扫描/停止按钮
- 结果区：按主机分组（层级：主机 IP → 开放端口列表），服务图标、类型、版本、延迟
- 状态：扫描中（进度 + 流式追加）、完成、已取消；空状态引导；错误提示
- 细节：结果项复制 `IP:端口`

## 七、CI/CD

`.github/workflows/release.yml`（重建，单平台 Windows）：

```
触发：推送 tag（v*.*.*）
Job: windows-latest
  1. checkout + setup Flutter（stable）
  2. flutter analyze + flutter test（发布前置验证）
  3. flutter build windows --release
  4. Inno Setup 打包 → ToolBox-Setup-vX.Y.Z.exe
  5. 上传 GitHub Release（安装包 + ZIP 便携版）
版本号从 tag 提取（v1.2.0 → 1.2.0），注入构建参数
```

安装包格式选 Inno Setup（非 MSIX）：无需签名证书即可分发、向导安装体验、工具链成熟。预留后续加 Linux/macOS job 的 matrix 结构，本次不实现。

## 八、测试策略

| 层 | 测试 | 内容 |
|----|------|------|
| core | 纯 Dart 单测 | CIDR 展开正确性、非法输入校验、并发调度与限流、超时模拟、取消传播、协议指纹解析（fake socket 注入字节序列） |
| features | widget 测试 | 发现界面输入校验、流式结果追加渲染（注入 fake 引擎） |
| 框架 | widget 测试 | 注册表装载、平台过滤逻辑、导航切换 |
| 集成 | 手动验证 | Windows 真机：亚克力窗口效果、真实网段扫描 |

## 九、范围与非目标

**v1.2.0 范围**：Windows 桌面完整应用 —— 框架（无边框亚克力窗口、明暗主题、侧边栏导航、工具注册表）+ 数据库发现（网段扫描）。

**非目标（明确不做）**：

- MySQL/CK 连接备份（已删除）
- 任务列表/操作日志/系统设置（已删除）
- 非 Windows 平台实现（仅预留 `supportedPlatforms` 声明机制）
- 插件热加载/动态安装
- 连接管理、SQL 客户端等后续工具

**长远预留**：工具平台声明机制 + 六分类导航，未来 Linux/macOS 版只需新增对应平台支持的 tool + 注册声明，框架不动。

## 十、工程约束

- 所有代码修改**不提交 git**，仅本地修改
- core 层零 Flutter 依赖（保证跨平台与可测试性）
- 新增工具 = 新 feature 目录 + 注册一行
