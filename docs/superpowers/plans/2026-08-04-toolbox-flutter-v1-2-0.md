# ToolBox v1.2.0（Flutter 重构）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 ToolBox 从 Kotlin/Compose Desktop 迁移为 Flutter Windows 桌面应用：苹果风格框架壳（亚克力无边框窗口、主题、侧边栏导航、工具注册表）+ 数据库发现工具（IP/CIDR 网段扫描）。

**Architecture:** Core-Feature 分层 —— `lib/core/` 纯 Dart 内核（零 Flutter 依赖，模型/扫描引擎/协议指纹库，可独立单测）；`lib/ui/` 框架壳（macos_ui 主题与窗口）；`lib/features/discovery/` 工具（domain/data/presentation）；`lib/registry/` 工具接口与集中注册表（平台过滤）。数据流：UI → Riverpod → ScanService → ScanEngine → `Stream<ScanEvent>` → UI 流式追加。

**Tech Stack:** Flutter 3.44.8 stable（Windows）、macos_ui、window_manager、flutter_acrylic、flutter_riverpod 2.x、shared_preferences、dart:io Socket、Inno Setup。

## Global Constraints

- **不执行任何 git 提交**（用户明确指令）。每个任务以「测试/构建通过」为完成标准，无 commit 步骤。
- `lib/core/` 零 Flutter 依赖：禁止 `import 'package:flutter/...'`（仅允许 `dart:` 与 `package:test`/`package:meta` 等纯 Dart 依赖），保证跨平台与可测试性。
- 项目名 `toolbox`，org `com.djshen.toolbox`，窗口标题 `ToolBox`，产品名 `ToolBox`。
- 默认扫描并发 50、单端口超时 1000ms。
- 默认服务端口映射（探测失败时按端口兜底识别）：3306→MySQL、5432→PostgreSQL、8123/9000→ClickHouse、6379→Redis、27017→MongoDB、1433→SQL Server、1521→Oracle、9200→Elasticsearch。
- UI 文案使用中文；代码标识符使用英文。
- 平台目标：仅 Windows 实现；工具通过 `supportedPlatforms` 声明平台，注册表按当前平台过滤。
- 所有命令在项目根目录 `d:\project\ai\tool-box` 执行。

---

### Task 1: 清理旧项目并创建 Flutter 工程

**Files:**
- Delete: `app/`、`common/`、`platform/`、`tool-api/`、`tools/`、`test/`、`doc/`、`gradle/`、`build.gradle.kts`、`settings.gradle.kts`、`gradle.properties`、`gradlew`、`gradlew.bat`、`README.md`、`.gitignore`、`.github/workflows/release.yml`
- Create: `pubspec.yaml`、`lib/main.dart`（模板）、`windows/`（flutter create 生成）、`test/widget_test.dart`（模板）、`.gitignore`（Flutter 标准模板）、`.github/workflows/release.yml`（Task 11 重写，先保留空目录 `.github/workflows/`）

**Interfaces:**
- Produces: Flutter 工程骨架（后续所有任务的基础）；`pubspec.yaml` 已含依赖：macos_ui、window_manager、flutter_acrylic、flutter_riverpod、shared_preferences、cupertino_icons

- [ ] **Step 1: 删除旧项目文件**

```powershell
Remove-Item -Recurse -Force app, common, platform, tool-api, tools, test, doc, gradle
Remove-Item -Force build.gradle.kts, settings.gradle.kts, gradle.properties, gradlew, gradlew.bat, README.md, .gitignore
Remove-Item -Recurse -Force .github\workflows
```

预期：根目录仅剩 `.git`、`.github`（空 workflows 目录）、`docs/`。

- [ ] **Step 2: 创建 Flutter 工程**

```powershell
flutter create --project-name toolbox --org com.djshen.toolbox --platforms windows .
```

预期：生成 `lib/`、`windows/`、`test/`、`pubspec.yaml`、`.gitignore`（Flutter 标准）。

- [ ] **Step 3: 添加依赖**

```powershell
flutter pub add macos_ui window_manager flutter_acrylic flutter_riverpod shared_preferences cupertino_icons
```

预期：pubspec.yaml dependencies 新增 6 项；`flutter pub get` 成功。若与 Flutter 3.44.8 出现版本解析冲突，将冲突信息与所选兼容版本记录到任务说明中再继续。

- [ ] **Step 4: 修改 pubspec 描述**

将 `pubspec.yaml` 中 `description:` 改为：`A modern desktop toolbox with Apple-style UI, built with Flutter.`

- [ ] **Step 5: 验证工具链**

```powershell
flutter analyze
flutter build windows --debug
```

预期：analyze 无 error；build 成功产出 `build/windows/x64/runner/Debug/toolbox.exe`。

**检查点**：Task 1 完成标准 —— `flutter analyze` 通过、`flutter build windows --debug` 成功。

---

### Task 2: 窗口框架（window_manager + flutter_acrylic）

**Files:**
- Modify: `lib/main.dart`（替换模板）
- Create: `lib/ui/window/app_window.dart`
- Delete: `test/widget_test.dart`（模板测试引用 MyApp，已不存在）

**Interfaces:**
- Consumes: Task 1 工程骨架
- Produces: `Future<void> initAppWindow()`（无边框 1200×800 居中、最小 900×600、Mica 亚克力背景）；`ToolBoxApp`（暂为 CupertinoApp + 占位页，Task 8 替换为完整壳）

- [ ] **Step 1: 删除模板测试**

```powershell
Remove-Item test\widget_test.dart
```

（模板测试引用 `MyApp`，替换主入口后必然失败。）

- [ ] **Step 2: 创建窗口初始化**

创建 `lib/ui/window/app_window.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:window_manager/window_manager.dart';

Future<void> initAppWindow() async {
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1200, 800),
    minimumSize: Size(900, 600),
    center: true,
    title: 'ToolBox',
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  if (await WindowEffects.isEffectSupported(WindowEffect.mica)) {
    await WindowEffects.configureWindow(
      backgroundColor: Colors.transparent,
      effect: WindowEffect.mica,
    );
  }
}
```

- [ ] **Step 3: 重写入口**

替换 `lib/main.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:toolbox/ui/window/app_window.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initAppWindow();
  runApp(const ToolBoxApp());
}

class ToolBoxApp extends StatelessWidget {
  const ToolBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      title: 'ToolBox',
      home: Center(child: Text('ToolBox')),
    );
  }
}
```

- [ ] **Step 4: 编译验证**

```powershell
flutter analyze
flutter build windows --debug
```

预期：无 error，构建成功。

- [ ] **Step 5: 手动验证窗口效果**

```powershell
flutter run -d windows
```

预期检查清单：① 窗口无系统边框，可拖动 ② 窗口居中、最小尺寸限制生效 ③ 背景为 Mica 亚克力半透明效果 ④ 标题栏区域自绘（右上角有最小化/最大化/关闭按钮，`windowButtonVisibility` 为 false 时需在后续 Shell 中自绘 —— 本任务仅验证窗口可关闭即可，可临时依赖系统按钮）⑤ 关闭按钮可退出应用。

**检查点**：Task 2 完成标准 —— 窗口显示正常、无边框、亚克力背景生效、可关闭退出。

---

### Task 3: core 模型与目标解析（models）

**Files:**
- Create: `lib/core/models/scan_target.dart`、`lib/core/models/scan_result.dart`、`lib/core/models/scan_event.dart`
- Test: `test/core/models/scan_target_test.dart`

**Interfaces:**
- Consumes: 无（纯 Dart 新代码）
- Produces:
  - `ScanTarget.fromInput(String input)` —— 校验并解析，非法输入抛 `FormatException`（含中文错误信息）
  - `ScanTarget.expandIpv4s() -> List<String>` —— 单 IP 返回自身；CIDR 返回网段内全部 IP
  - `enum ScanStatus { open, closed, timeout }`
  - `class ScanResult { final String ip; final int port; final ScanStatus status; final String? serviceType; final String? version; final Duration latency; }`
  - `sealed class ScanEvent`：`ProgressEvent(done, total)`、`ResultEvent(ScanResult)`、`CompletedEvent`

- [ ] **Step 1: 写失败测试**

创建 `test/core/models/scan_target_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/core/models/scan_target.dart';

void main() {
  test('单 IP 解析', () {
    final t = ScanTarget.fromInput('192.168.1.10');
    expect(t.expandIpv4s(), ['192.168.1.10']);
  });

  test('CIDR /24 展开为 256 个 IP', () {
    final t = ScanTarget.fromInput('192.168.1.0/24');
    final ips = t.expandIpv4s();
    expect(ips.length, 256);
    expect(ips.first, '192.168.1.0');
    expect(ips.last, '192.168.1.255');
  });

  test('CIDR /30 展开为 4 个 IP', () {
    final t = ScanTarget.fromInput('10.0.0.1/30');
    expect(t.expandIpv4s().length, 4);
  });

  test('非法输入抛 FormatException', () {
    expect(() => ScanTarget.fromInput('abc'), throwsFormatException);
    expect(() => ScanTarget.fromInput('1.2.3'), throwsFormatException);
    expect(() => ScanTarget.fromInput('192.168.1.0/33'), throwsFormatException);
    expect(() => ScanTarget.fromInput('256.1.1.1'), throwsFormatException);
  });
}
```

- [ ] **Step 2: 运行确认失败**

```powershell
flutter test test/core/models/scan_target_test.dart
```

预期：编译失败（`ScanTarget` 不存在）。

- [ ] **Step 3: 实现模型**

创建 `lib/core/models/scan_target.dart`：

```dart
/// 扫描目标：单个 IPv4 地址或 CIDR 网段。
class ScanTarget {
  ScanTarget._(this.host, this.prefix);

  /// host 为 IP 或网络地址；prefix 为 null 表示单 IP。
  final String host;
  final int? prefix;

  factory ScanTarget.fromInput(String input) {
    final s = input.trim();
    final slash = s.indexOf('/');
    if (slash == -1) {
      if (!_isValidIpv4(s)) {
        throw FormatException('无效的 IP 地址: $s');
      }
      return ScanTarget._(s, null);
    }
    final ip = s.substring(0, slash);
    final p = int.tryParse(s.substring(slash + 1));
    if (!_isValidIpv4(ip) || p == null || p < 0 || p > 32) {
      throw FormatException('无效的 CIDR 网段: $s');
    }
    return ScanTarget._(ip, p);
  }

  static bool _isValidIpv4(String s) {
    final parts = s.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  /// 展开为 IP 列表；单 IP 返回 [host] 自身。
  List<String> expandIpv4s() {
    if (prefix == null) return [host];
    final shift = 32 - prefix!;
    final base = host.split('.').map(int.parse).fold<int>(0, (acc, v) => (acc << 8) | v);
    final count = 1 << shift;
    return List.generate(count, (i) {
      final v = base + i;
      return '${(v >> 24) & 0xFF}.${(v >> 16) & 0xFF}.${(v >> 8) & 0xFF}.${v & 0xFF}';
    });
  }
}
```

创建 `lib/core/models/scan_result.dart`：

```dart
import 'dart:core';

enum ScanStatus { open, closed, timeout }

class ScanResult {
  const ScanResult({
    required this.ip,
    required this.port,
    required this.status,
    this.serviceType,
    this.version,
    this.latency = Duration.zero,
  });

  final String ip;
  final int port;
  final ScanStatus status;
  final String? serviceType;
  final String? version;
  final Duration latency;
}
```

创建 `lib/core/models/scan_event.dart`：

```dart
import 'scan_result.dart';

sealed class ScanEvent {}

class ProgressEvent extends ScanEvent {
  ProgressEvent(this.done, this.total);
  final int done;
  final int total;
}

class ResultEvent extends ScanEvent {
  ResultEvent(this.result);
  final ScanResult result;
}

class CompletedEvent extends ScanEvent {}
```

- [ ] **Step 4: 运行测试确认通过**

```powershell
flutter test test/core/models/scan_target_test.dart
```

预期：全部 PASS。

**检查点**：Task 3 完成标准 —— 测试通过，core 目录无 Flutter import。

---

### Task 4: core 扫描引擎（scanner）

**Files:**
- Create: `lib/core/scanner/scan_socket.dart`、`lib/core/scanner/scan_engine.dart`
- Test: `test/core/scanner/scan_engine_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `ScanTarget`/`ScanResult`/`ScanEvent`
- Produces:
  - `abstract class ScanSocket { Future<void> write(List<int> data); Future<List<int>> read(int maxBytes, {Duration timeout}); void destroy(); }`
  - `abstract class ScanSocketFactory { Future<ScanSocket> connect(String host, int port, Duration timeout); }`
  - `class RealScanSocketFactory implements ScanSocketFactory`（dart:io Socket 封装；connect 用 `Socket.connect(host, port, timeout: timeout)`）
  - `class ScanEngine { ScanEngine({required ScanSocketFactory socketFactory, required ProbeRegistry probeRegistry, int concurrency = 50, Duration timeout = const Duration(milliseconds: 1000)}); Stream<ScanEvent> scan(List<String> ips); void cancel(); }`
  - 行为契约：并发连接数不超过 concurrency；connect 失败（拒绝）→ `ScanStatus.closed`；connect 超时 → `ScanStatus.timeout`；connect 成功后调用 `probeRegistry.probeFor(port)` 探测（探测超时 2000ms），探测失败降级为端口映射服务类型；每个端口扫描完成发 `ProgressEvent`；全部完成发 `CompletedEvent`；`cancel()` 后立即停止发射后续事件并终止未完成连接。

- [ ] **Step 1: 写失败测试**

创建 `test/core/scanner/scan_engine_test.dart`：

```dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/core/models/scan_event.dart';
import 'package:toolbox/core/models/scan_result.dart';
import 'package:toolbox/core/protocols/probe_registry.dart';
import 'package:toolbox/core/protocols/service_probe.dart';
import 'package:toolbox/core/scanner/scan_engine.dart';
import 'package:toolbox/core/scanner/scan_socket.dart';

/// Fake socket：可编程的成功/拒绝/超时，可记录并发数。
class FakeSocket implements ScanSocket {
  FakeSocket();
  bool connected = true;

  @override
  Future<List<int>> read(int maxBytes,
          {Duration timeout = const Duration(seconds: 2)}) async =>
      [];

  @override
  Future<void> write(List<int> data) async {}

  @override
  void destroy() {
    connected = false;
  }
}

class FakeSocketFactory implements ScanSocketFactory {
  FakeSocketFactory({required this.mode});
  final String mode; // 'ok' | 'refused' | 'hang'
  final List<String> connectLog = [];
  int inflight = 0;
  int maxInflight = 0;

  @override
  Future<ScanSocket> connect(String host, int port, Duration timeout) async {
    connectLog.add('$host:$port');
    inflight++;
    if (inflight > maxInflight) maxInflight = inflight;
    if (mode == 'hang') {
      await Future<void>.delayed(timeout + const Duration(milliseconds: 100));
      inflight--;
      throw TimeoutException('timeout');
    }
    if (mode == 'refused') {
      inflight--;
      throw const ScanConnectException('refused');
    }
    return FakeSocket();
  }
}

class _NullProbeRegistry implements ProbeRegistry {
  @override
  ServiceProbe? probeFor(int port) => null;
  @override
  String? defaultServiceFor(int port) => null;
}

void main() {
  test('并发数受 concurrency 限制', () async {
    final factory = FakeSocketFactory(mode: 'ok');
    final engine = ScanEngine(
      socketFactory: factory,
      probeRegistry: _NullProbeRegistry(),
      concurrency: 2,
    );
    final events = <ScanEvent>[];
    await engine.scan(['10.0.0.1', '10.0.0.2']).listen(events.add).asFuture();
    expect(factory.maxInflight, lessThanOrEqualTo(2));
    expect(factory.connectLog.length, 2);
  });

  test('拒绝连接 → closed，超时 → timeout', () async {
    final refused = ScanEngine(
      socketFactory: FakeSocketFactory(mode: 'refused'),
      probeRegistry: _NullProbeRegistry(),
    );
    final refusedResults = <ScanResult>[];
    await refused.scan(['10.0.0.1'])
        .listen((e) { if (e is ResultEvent) refusedResults.add(e.result); }).asFuture();
    expect(refusedResults.single.status, ScanStatus.closed);

    final hung = ScanEngine(
      socketFactory: FakeSocketFactory(mode: 'hang'),
      probeRegistry: _NullProbeRegistry(),
      timeout: const Duration(milliseconds: 100),
    );
    final hungResults = <ScanResult>[];
    await hung.scan(['10.0.0.1'])
        .listen((e) { if (e is ResultEvent) hungResults.add(e.result); }).asFuture();
    expect(hungResults.single.status, ScanStatus.timeout);
  });

  test('开放端口调用协议探测并产出服务类型', () async {
    final factory = FakeSocketFactory(mode: 'ok');
    final engine = ScanEngine(
      socketFactory: factory,
      probeRegistry: _FakeProbeRegistry('MySQL', '8.0.41'),
    );
    final results = <ScanResult>[];
    await engine.scan(['10.0.0.1'])
        .listen((e) { if (e is ResultEvent) results.add(e.result); }).asFuture();
    expect(results.single.status, ScanStatus.open);
    expect(results.single.serviceType, 'MySQL');
    expect(results.single.version, '8.0.41');
  });

  test('完成时发射 ProgressEvent 与 CompletedEvent', () async {
    final factory = FakeSocketFactory(mode: 'ok');
    final engine = ScanEngine(
      socketFactory: factory,
      probeRegistry: _NullProbeRegistry(),
    );
    final events = <ScanEvent>[];
    await engine.scan(['10.0.0.1']).listen(events.add).asFuture();
    expect(events.whereType<CompletedEvent>(), hasLength(1));
    expect(events.whereType<ProgressEvent>().last.done, 1);
  });

  test('cancel 后停止发射事件', () async {
    final factory = FakeSocketFactory(mode: 'hang');
    final engine = ScanEngine(
      socketFactory: factory,
      probeRegistry: _NullProbeRegistry(),
      timeout: const Duration(milliseconds: 50),
    );
    final events = <ScanEvent>[];
    final sub = engine.scan(['10.0.0.1']).listen(events.add);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    engine.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(events.whereType<CompletedEvent>(), isEmpty);
    await sub.cancel();
  });
}

class _FakeProbeRegistry implements ProbeRegistry {
  _FakeProbeRegistry(this.service, this.version);
  final String service;
  final String? version;

  @override
  ServiceProbe? probeFor(int port) => _FakeProbe(service, version);
  @override
  String? defaultServiceFor(int port) => service;
}

class _FakeProbe implements ServiceProbe {
  _FakeProbe(this.serviceName, this.version);
  @override
  final String serviceName;
  final String? version;

  @override
  int get port => 3306;

  @override
  Future<ProbeResult?> probe(ScanSocket socket) async =>
      ProbeResult(serviceName: serviceName, version: version);
}
```

- [ ] **Step 2: 运行确认失败**

```powershell
flutter test test/core/scanner/scan_engine_test.dart
```

预期：编译失败（依赖类型不存在）。

- [ ] **Step 3: 实现 ScanSocket 抽象**

创建 `lib/core/scanner/scan_socket.dart`（**只含抽象与统一异常，无 dart:io 依赖**；dart:io 实现在 Task 9 以条件导入方式提供，保证 Web 编译安全）：

```dart
/// 连接失败（拒绝/网络错误）的统一异常：引擎据此判定 closed。
/// dart:io 实现将 SocketException 转换为本异常。
class ScanConnectException implements Exception {
  const ScanConnectException(this.message);
  final String message;
}

/// 可测试的 socket 抽象：core 层不直接依赖 dart:io Socket。
abstract class ScanSocket {
  Future<void> write(List<int> data);
  Future<List<int>> read(int maxBytes, {Duration timeout});
  void destroy();
}

abstract class ScanSocketFactory {
  Future<ScanSocket> connect(String host, int port, Duration timeout);
}
```

- [ ] **Step 4: 实现协议注册表接口（供引擎依赖）**

创建 `lib/core/protocols/probe_registry.dart` 与 `lib/core/protocols/service_probe.dart`（Task 5 将提供完整实现与默认注册表，本步骤先建接口）：

```dart
// lib/core/protocols/service_probe.dart
import '../scanner/scan_socket.dart';

class ProbeResult {
  const ProbeResult({required this.serviceName, this.version});
  final String serviceName;
  final String? version;
}

/// 协议指纹：对指定端口执行探测，返回服务类型与版本；null 表示未识别。
abstract class ServiceProbe {
  int get port;
  String get serviceName;
  Future<ProbeResult?> probe(ScanSocket socket);
}
```

```dart
// lib/core/protocols/probe_registry.dart
import 'service_probe.dart';

/// 指纹注册表：端口 → 探测器；端口兜底服务名映射。
abstract class ProbeRegistry {
  ServiceProbe? probeFor(int port);
  String? defaultServiceFor(int port);
}
```

- [ ] **Step 5: 实现扫描引擎**

创建 `lib/core/scanner/scan_engine.dart`：

```dart
import 'dart:async';
import '../models/scan_event.dart';
import '../models/scan_result.dart';
import '../protocols/probe_registry.dart';
import 'scan_socket.dart';

/// 并发扫描引擎：对 (ip, port) 对做 TCP 连通性 + 协议指纹探测。
class ScanEngine {
  ScanEngine({
    required this.socketFactory,
    required this.probeRegistry,
    this.concurrency = 50,
    this.timeout = const Duration(milliseconds: 1000),
  });

  final ScanSocketFactory socketFactory;
  final ProbeRegistry probeRegistry;
  final int concurrency;
  final Duration timeout;

  bool _cancelled = false;

  void cancel() => _cancelled = true;

  Stream<ScanEvent> scan(List<String> ips, List<int> ports) async* {
    _cancelled = false;
    final queue = <(String, int)>[
      for (final ip in ips)
        for (final port in ports) (ip, port),
    ];
    final total = queue.length;
    var done = 0;
    final active = <Future<void>>[];

    final controller = StreamController<ScanEvent>();

    Future<void> worker((String, int) task) async {
      final (ip, port) = task;
      if (_cancelled) return;
      final started = DateTime.now();
      ScanResult result;
      try {
        final socket = await socketFactory.connect(ip, port, timeout);
        if (_cancelled) {
          socket.destroy();
          return;
        }
        try {
          final probe = probeRegistry.probeFor(port);
          final probeResult = probe == null
              ? null
              : await probe
                  .probe(socket)
                  .timeout(const Duration(seconds: 2), onTimeout: () => null);
          result = ScanResult(
            ip: ip,
            port: port,
            status: ScanStatus.open,
            serviceType: probeResult?.serviceName ??
                probeRegistry.defaultServiceFor(port),
            version: probeResult?.version,
            latency: DateTime.now().difference(started),
          );
        } finally {
          socket.destroy();
        }
      } on TimeoutException {
        result = ScanResult(ip: ip, port: port, status: ScanStatus.timeout);
      } on ScanConnectException {
        result = ScanResult(ip: ip, port: port, status: ScanStatus.closed);
      } catch (_) {
        result = ScanResult(ip: ip, port: port, status: ScanStatus.closed);
      }
      if (!_cancelled) {
        controller.add(ResultEvent(result));
        done++;
        controller.add(ProgressEvent(done, total));
      }
    }

    try {
      for (final task in queue) {
        if (_cancelled) break;
        // 等待并发槽位：active 中的 future 完成时会把自己从列表移除
        while (active.length >= concurrency) {
          await Future.any(active);
        }
        late Future<void> tracked;
        tracked = () async {
          try {
            await worker(task);
          } finally {
            active.remove(tracked);
          }
        }();
        active.add(tracked);
      }
      await Future.wait(active);
      if (!_cancelled) controller.add(CompletedEvent());
    } finally {
      await controller.close();
      yield* controller.stream;
    }
  }
}
```

- [ ] **Step 6: 运行测试确认通过**

```powershell
flutter test test/core/scanner/scan_engine_test.dart
```

预期：全部 PASS。若并发控制实现存在竞态导致偶发失败，调整 `active.removeWhere` 逻辑（如改用 `Completer` 信号量）至稳定通过。

**检查点**：Task 4 完成标准 —— 引擎测试全绿；`lib/core/` 无 Flutter import。

---

### Task 5: core 协议指纹库（protocols）

**Files:**
- Create: `lib/core/protocols/mysql_probe.dart`、`redis_probe.dart`、`postgresql_probe.dart`、`mongodb_probe.dart`、`http_probe.dart`（ClickHouse/Elasticsearch 共用）、`oracle_probe.dart`、`sqlserver_probe.dart`、`default_probe_registry.dart`
- Test: `test/core/protocols/probes_test.dart`

**Interfaces:**
- Consumes: Task 4 的 `ServiceProbe`/`ProbeResult`/`ProbeRegistry`/`ScanSocket`
- Produces:
  - `class DefaultProbeRegistry implements ProbeRegistry` —— 端口→探测器映射与兜底服务名映射（映射表见 Global Constraints）
  - 各 `ServiceProbe` 实现，探测失败返回 null（由引擎降级为端口兜底类型）

- [ ] **Step 1: 写失败测试**

创建 `test/core/protocols/probes_test.dart`，使用可编程字节流 FakeSocket：

```dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/core/protocols/default_probe_registry.dart';
import 'package:toolbox/core/scanner/scan_socket.dart';

class BytesSocket implements ScanSocket {
  BytesSocket(this._chunks);
  final List<List<int>> _chunks;
  int _readIndex = 0;
  final List<List<int>> written = [];

  @override
  Future<List<int>> read(int maxBytes, {Duration timeout = const Duration(seconds: 2)}) async {
    if (_readIndex >= _chunks.length) return [];
    final chunk = _chunks[_readIndex++];
    return chunk.length > maxBytes ? chunk.sublist(0, maxBytes) : chunk;
  }

  @override
  Future<void> write(List<int> data) async => written.add(data);
  @override
  void destroy() {}
}

void main() {
  final registry = DefaultProbeRegistry();

  test('MySQL 握手包解析版本', () async {
    final p = registry.probeFor(3306)!;
    final r = await p.probe(BytesSocket([[
      0x0a, // 协议版本 10
      ...'8.0.41'.codeUnits, 0x00, // 服务器版本（null 结尾）
      1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13,
    ]]));
    expect(r?.serviceName, 'MySQL');
    expect(r?.version, '8.0.41');
  });

  test('MySQL 非法字节 → 未识别', () async {
    final p = registry.probeFor(3306)!;
    expect(await p.probe(BytesSocket([[0x01, 2, 3, 4]])), isNull);
  });

  test('Redis PING 响应识别', () async {
    final p = registry.probeFor(6379)!;
    final r = await p.probe(BytesSocket(['+PONG\r\n'.codeUnits]));
    expect(r?.serviceName, 'Redis');
  });

  test('PostgreSQL 认证协商包识别', () async {
    final p = registry.probeFor(5432)!;
    final r = await p.probe(BytesSocket([[0, 0, 0, 8, 0x52, 3, 0, 0]])); // 长度4 + 'R'
    expect(r?.serviceName, 'PostgreSQL');
  });

  test('MongoDB 探测响应识别', () async {
    final p = registry.probeFor(27017)!;
    final header = [0, 0, 0, 36, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]; // 16B 头
    final r = await p.probe(BytesSocket([header]));
    expect(r?.serviceName, 'MongoDB');
  });

  test('ClickHouse HTTP 响应头识别', () async {
    final p = registry.probeFor(8123)!;
    final resp = 'HTTP/1.1 200 OK\r\n'
        'X-ClickHouse-Server-Display-Name: localhost\r\n'
        'Content-Length: 3\r\n\r\nOk.';
    final r = await p.probe(BytesSocket([resp.codeUnits]));
    expect(r?.serviceName, 'ClickHouse');
  });

  test('Elasticsearch HTTP 响应识别', () async {
    final p = registry.probeFor(9200)!;
    final resp = 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n'
        '{"version":{"number":"8.13.4"},"tagline":"You Know, for Search"}';
    final r = await p.probe(BytesSocket([resp.codeUnits]));
    expect(r?.serviceName, 'Elasticsearch');
    expect(r?.version, '8.13.4');
  });

  test('SQL Server PRELOGIN 响应识别', () async {
    final p = registry.probeFor(1433)!;
    final r = await p.probe(BytesSocket([[0x04, 1, 0, 0, 0, 0, 0, 0]])); // packet type 0x04
    expect(r?.serviceName, 'SQL Server');
  });

  test('Oracle TNS 响应识别', () async {
    final p = registry.probeFor(1521)!;
    final r = await p.probe(BytesSocket([[0x02, 0, 0, 0, 0, 0, 0, 0]])); // TNS type 2
    expect(r?.serviceName, 'Oracle');
  });

  test('未知端口无探测器但可兜底服务名', () async {
    expect(registry.probeFor(12345), isNull);
    expect(registry.defaultServiceFor(9200), 'Elasticsearch');
    expect(registry.defaultServiceFor(9000), 'ClickHouse');
  });

  test('HTTP 探测写入 GET 请求', () async {
    final s = BytesSocket(['HTTP/1.1 200 OK\r\n\r\n'.codeUnits]);
    await registry.probeFor(8123)!.probe(s);
    expect(s.written.single.join(','), contains('GET / HTTP/1.0'));
  });
}
```

- [ ] **Step 2: 运行确认失败**

```powershell
flutter test test/core/protocols/probes_test.dart
```

预期：编译失败（实现不存在）。

- [ ] **Step 3: 实现各探测器**

创建 `lib/core/protocols/mysql_probe.dart`：

```dart
import '../scanner/scan_socket.dart';
import 'service_probe.dart';

/// MySQL：服务器连接后立即发送握手包（首字节 0x0a + null 结尾的版本串）。
class MySqlProbe implements ServiceProbe {
  const MySqlProbe();

  @override
  int get port => 3306;
  @override
  String get serviceName => 'MySQL';

  @override
  Future<ProbeResult?> probe(ScanSocket socket) async {
    final data = await socket.read(64);
    if (data.isEmpty || data.first != 0x0a) return null;
    final versionBytes = <int>[];
    for (final b in data.skip(1)) {
      if (b == 0x00) break;
      versionBytes.add(b);
    }
    final version = String.fromCharCodes(versionBytes);
    return ProbeResult(
      serviceName: serviceName,
      version: version.isEmpty ? null : version,
    );
  }
}
```

创建 `lib/core/protocols/redis_probe.dart`：

```dart
import '../scanner/scan_socket.dart';
import 'service_probe.dart';

/// Redis：发送 PING，响应 +PONG 即识别。
class RedisProbe implements ServiceProbe {
  const RedisProbe();

  @override
  int get port => 6379;
  @override
  String get serviceName => 'Redis';

  @override
  Future<ProbeResult?> probe(ScanSocket socket) async {
    await socket.write('PING\r\n'.codeUnits);
    final data = await socket.read(32);
    if (String.fromCharCodes(data).startsWith('+PONG')) {
      return const ProbeResult(serviceName: serviceName);
    }
    return null;
  }
}
```

创建 `lib/core/protocols/postgresql_probe.dart`：

```dart
import '../scanner/scan_socket.dart';
import 'service_probe.dart';

/// PostgreSQL：服务器先发认证请求包，第 5 字节为 0x52（'R'）。
class PostgreSqlProbe implements ServiceProbe {
  const PostgreSqlProbe();

  @override
  int get port => 5432;
  @override
  String get serviceName => 'PostgreSQL';

  @override
  Future<ProbeResult?> probe(ScanSocket socket) async {
    final data = await socket.read(8);
    if (data.length >= 5 && data[4] == 0x52) {
      return const ProbeResult(serviceName: serviceName);
    }
    return null;
  }
}
```

创建 `lib/core/protocols/mongodb_probe.dart`：

```dart
import '../scanner/scan_socket.dart';
import 'service_probe.dart';

/// MongoDB：发送 isMaster 查询（OP_QUERY），读取 16 字节响应头（OP_REPLY）。
class MongoDbProbe implements ServiceProbe {
  const MongoDbProbe();

  @override
  int get port => 27017;
  @override
  String get serviceName => 'MongoDB';

  @override
  Future<ProbeResult?> probe(ScanSocket socket) async {
    // 16 字节消息头：msgLength(4) + requestID(4) + responseTo(4) + opCode(4)
    // OP_QUERY = 2004 (0x7D4 小端)
    final header = <int>[
      0x16, 0x00, 0x00, 0x00, // 22 字节请求
      0x01, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00,
      0xD4, 0x07, 0x00, 0x00, // opCode 2004
      0x00, 0x00, 0x00, 0x00, // flags
      0x00, 0x00, 0x00, 0x00, // collection name (空串)
    ];
    await socket.write(header);
    final data = await socket.read(16);
    if (data.length == 16 && data[15] == 0x01 && data[14] == 0x00) {
      // opCode == OP_REPLY(1) 小端
      return const ProbeResult(serviceName: serviceName);
    }
    return null;
  }
}
```

创建 `lib/core/protocols/http_probe.dart`：

```dart
import '../scanner/scan_socket.dart';
import 'service_probe.dart';

/// 通用 HTTP 探测：发送 GET /，按响应头识别 ClickHouse / Elasticsearch。
class HttpProbe implements ServiceProbe {
  const HttpProbe({required this.port, required this.serviceName});

  @override
  final int port;
  @override
  final String serviceName;

  @override
  Future<ProbeResult?> probe(ScanSocket socket) async {
    await socket.write('GET / HTTP/1.0\r\nHost: localhost\r\n\r\n'.codeUnits);
    final data = await socket.read(4096);
    final head = String.fromCharCodes(data);
    if (head.contains('X-ClickHouse-Server-Display-Name')) {
      return const ProbeResult(serviceName: 'ClickHouse');
    }
    if (head.contains('"tagline"')) {
      // Elasticsearch JSON 响应
      final m = RegExp(r'"number"\s*:\s*"([^"]+)"').firstMatch(head);
      return ProbeResult(serviceName: 'Elasticsearch', version: m?.group(1));
    }
    return null;
  }
}
```

创建 `lib/core/protocols/sqlserver_probe.dart`：

```dart
import '../scanner/scan_socket.dart';
import 'service_probe.dart';

/// SQL Server：服务器先发 PRELOGIN 响应，packet type 0x04。
class SqlServerProbe implements ServiceProbe {
  const SqlServerProbe();

  @override
  int get port => 1433;
  @override
  String get serviceName => 'SQL Server';

  @override
  Future<ProbeResult?> probe(ScanSocket socket) async {
    final data = await socket.read(8);
    if (data.isNotEmpty && data.first == 0x04) {
      return const ProbeResult(serviceName: serviceName);
    }
    return null;
  }
}
```

创建 `lib/core/protocols/oracle_probe.dart`：

```dart
import '../scanner/scan_socket.dart';
import 'service_probe.dart';

/// Oracle：服务器先发 TNS 数据包，首字节类型 0x02（ACCEPT）或 0x01（CONNECT）。
class OracleProbe implements ServiceProbe {
  const OracleProbe();

  @override
  int get port => 1521;
  @override
  String get serviceName => 'Oracle';

  @override
  Future<ProbeResult?> probe(ScanSocket socket) async {
    final data = await socket.read(8);
    if (data.isNotEmpty && (data.first == 0x02 || data.first == 0x01)) {
      return const ProbeResult(serviceName: serviceName);
    }
    return null;
  }
}
```

创建 `lib/core/protocols/default_probe_registry.dart`：

```dart
import 'http_probe.dart';
import 'mongodb_probe.dart';
import 'mysql_probe.dart';
import 'oracle_probe.dart';
import 'postgresql_probe.dart';
import 'probe_registry.dart';
import 'redis_probe.dart';
import 'service_probe.dart';
import 'sqlserver_probe.dart';

/// 默认指纹注册表：8 种服务 9 个端口。
class DefaultProbeRegistry implements ProbeRegistry {
  DefaultProbeRegistry()
      : _probes = {
          for (final p in _all) p.port: p,
        };

  static const _all = <ServiceProbe>[
    MySqlProbe(),
    PostgreSqlProbe(),
    RedisProbe(),
    MongoDbProbe(),
    SqlServerProbe(),
    OracleProbe(),
    HttpProbe(port: 8123, serviceName: 'ClickHouse'),
    HttpProbe(port: 9000, serviceName: 'ClickHouse'),
    HttpProbe(port: 9200, serviceName: 'Elasticsearch'),
  ];

  static const _defaultServices = <int, String>{
    3306: 'MySQL',
    5432: 'PostgreSQL',
    8123: 'ClickHouse',
    9000: 'ClickHouse',
    6379: 'Redis',
    27017: 'MongoDB',
    1433: 'SQL Server',
    1521: 'Oracle',
    9200: 'Elasticsearch',
  };

  final Map<int, ServiceProbe> _probes;

  @override
  ServiceProbe? probeFor(int port) => _probes[port];

  @override
  String? defaultServiceFor(int port) => _defaultServices[port];
}
```

- [ ] **Step 4: 运行测试确认通过**

```powershell
flutter test test/core/protocols/probes_test.dart
```

预期：全部 PASS。若 MongoDB 探测的真实字节布局与 fake 不一致，调整测试字节序列使与实现一致（实现不变，仅校正测试数据）。

**检查点**：Task 5 完成标准 —— 指纹测试全绿；`DefaultProbeRegistry` 映射完整（9 端口）。

---

### Task 6: 工具接口与集中注册表（registry）

**Files:**
- Create: `lib/registry/platform_type.dart`、`lib/registry/tool_category.dart`、`lib/registry/tool.dart`、`lib/registry/tool_registry.dart`
- Test: `test/registry/tool_registry_test.dart`

**Interfaces:**
- Consumes: 无（Flutter 侧新代码）
- Produces:
  - `enum PlatformType { windows, linux, macOS, android, ios, web }`
  - `enum ToolCategory { data, database, text, encode, system, other }`（含 `displayName`：数据处理/数据库管理/文本工具/编解码/系统工具/其他工具）
  - `abstract class Tool { String get id; String get name; String get description; ToolCategory get category; Set<PlatformType> get supportedPlatforms; Widget buildContent(BuildContext context); }`
  - `class ToolRegistry { List<Tool> registerAll(); List<Tool> availableTools(); }` —— `availableTools()` 按当前平台过滤（web/desktop 检测）；当前平台映射：Windows→windows、macOS→macOS、Linux→linux、Android→android、iOS→ios、Web→web
  - `PlatformType get currentPlatformType`

- [ ] **Step 1: 写失败测试**

创建 `test/registry/tool_registry_test.dart`：

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/registry/platform_type.dart';
import 'package:toolbox/registry/tool.dart';
import 'package:toolbox/registry/tool_category.dart';
import 'package:toolbox/registry/tool_registry.dart';

class _FakeTool extends Tool {
  _FakeTool(this._id, this._platforms);
  final String _id;
  final Set<PlatformType> _platforms;

  @override
  String get id => _id;
  @override
  String get name => _id;
  @override
  String get description => 'desc';
  @override
  ToolCategory get category => ToolCategory.other;
  @override
  Set<PlatformType> get supportedPlatforms => _platforms;

  @override
  Widget buildContent(BuildContext context) => const SizedBox.shrink();
}

class _FakeRegistry extends ToolRegistry {
  @override
  List<Tool> registerAll() => [
        _FakeTool('windows-tool', {PlatformType.windows}),
        _FakeTool('desktop-tool', {PlatformType.windows, PlatformType.linux}),
        _FakeTool('mobile-tool', {PlatformType.android, PlatformType.ios}),
      ];
}

void main() {
  test('availableTools 只含当前平台工具', () {
    final registry = _FakeRegistry();
    final available = registry.availableTools().map((t) => t.id).toList();
    final current = currentPlatformType;
    for (final id in available) {
      expect(
        registry.registerAll().firstWhere((t) => t.id == id).supportedPlatforms,
        contains(current),
      );
    }
    expect(available, contains('desktop-tool'));
  });

  test('ToolCategory 六分类展示名', () {
    expect(ToolCategory.values.length, 6);
    expect(ToolCategory.database.displayName, '数据库管理');
  });
}
```

- [ ] **Step 2: 运行确认失败**

```powershell
flutter test test/registry/tool_registry_test.dart
```

预期：编译失败（类型不存在）。

- [ ] **Step 3: 实现注册表类型**

创建 `lib/registry/platform_type.dart`：

```dart
import 'package:flutter/foundation.dart';

enum PlatformType { windows, linux, macOS, android, ios, web }

PlatformType get currentPlatformType {
  if (kIsWeb) return PlatformType.web;
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows => PlatformType.windows,
    TargetPlatform.linux => PlatformType.linux,
    TargetPlatform.macOS => PlatformType.macOS,
    TargetPlatform.android => PlatformType.android,
    TargetPlatform.iOS => PlatformType.ios,
    TargetPlatform.fuchsia => PlatformType.linux,
  };
}
```

创建 `lib/registry/tool_category.dart`：

```dart
enum ToolCategory {
  data('数据处理'),
  database('数据库管理'),
  text('文本工具'),
  encode('编解码'),
  system('系统工具'),
  other('其他工具');

  const ToolCategory(this.displayName);
  final String displayName;
}
```

创建 `lib/registry/tool.dart`：

```dart
import 'package:flutter/widgets.dart';
import 'platform_type.dart';
import 'tool_category.dart';

/// 工具接口：每个工具实现此接口并在注册表中登记。
abstract class Tool {
  String get id;
  String get name;
  String get description;
  ToolCategory get category;

  /// 支持的平台集合，注册表按当前平台过滤。
  Set<PlatformType> get supportedPlatforms;

  Widget buildContent(BuildContext context);
}
```

创建 `lib/registry/tool_registry.dart`：

```dart
import 'package:flutter/widgets.dart';
import 'platform_type.dart';
import 'tool.dart';

/// 工具集中注册表：登记全部工具并按当前平台过滤。
abstract class ToolRegistry {
  /// 全部工具注册（子类集中登记）。
  List<Tool> registerAll();

  /// 当前平台可用的工具。
  List<Tool> availableTools() {
    final current = currentPlatformType;
    return registerAll()
        .where((t) => t.supportedPlatforms.contains(current))
        .toList();
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```powershell
flutter test test/registry/tool_registry_test.dart
```

预期：全部 PASS。

**检查点**：Task 6 完成标准 —— 注册表测试全绿。

---

### Task 7: 主题系统（ui/theme）

**Files:**
- Create: `lib/ui/theme/toolbox_theme.dart`、`lib/ui/theme/theme_controller.dart`
- Test: `test/ui/theme/theme_controller_test.dart`

**Interfaces:**
- Consumes: 无
- Produces:
  - `class ToolboxTheme { static MacosThemeData light(); static MacosThemeData dark(); }`（浅色：背景 `#F5F5F7`、主色 `#007AFF`；深色：背景 `#1C1C1E`、主色 `#0A84FF`；圆角 8dp；明暗双套）
  - `class ThemeController extends Notifier<ThemeMode>` —— 初始 `ThemeMode.system`，`setDark(bool)` 预留手动切换

- [ ] **Step 1: 写失败测试**

创建 `test/ui/theme/theme_controller_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/ui/theme/theme_controller.dart';

void main() {
  test('ThemeController 初始为跟随系统', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(themeControllerProvider), ThemeMode.system);
  });

  test('setDark 切换主题模式', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(themeControllerProvider.notifier).setDark(true);
    expect(container.read(themeControllerProvider), ThemeMode.dark);
    container.read(themeControllerProvider.notifier).setDark(false);
    expect(container.read(themeControllerProvider), ThemeMode.light);
  });
}
```

- [ ] **Step 2: 运行确认失败**

```powershell
flutter test test/ui/theme/theme_controller_test.dart
```

预期：编译失败。

- [ ] **Step 3: 实现主题与控制器**

创建 `lib/ui/theme/toolbox_theme.dart`：

```dart
import 'package:macos_ui/macos_ui.dart';

/// Apple 设计语言主题：暖灰白背景、iOS 系统蓝主色。
class ToolboxTheme {
  ToolboxTheme._();

  static const _blue = MacosColor(0xFF007AFF);
  static const _blueDark = MacosColor(0xFF0A84FF);

  static MacosThemeData light() => MacosThemeData(
        brightness: Brightness.light,
        primaryColor: _blue,
        backgroundColor: const MacosColor(0xFFF5F5F7),
        scaffoldBackgroundColor: const MacosColor(0xFFF5F5F7),
        textColor: const MacosColor(0xFF1C1C1E),
        dialogBackgroundColor: const MacosColor(0xFFFFFFFF),
        buttonTheme: const MacosButtonThemeData(
          backgroundColor: _blue,
          textColor: MacosColor(0xFFFFFFFF),
        ),
        accentColor: _blue,
        inputColor: const MacosColor(0xFFFFFFFF),
      );

  static MacosThemeData dark() => MacosThemeData(
        brightness: Brightness.dark,
        primaryColor: _blueDark,
        backgroundColor: const MacosColor(0xFF1C1C1E),
        scaffoldBackgroundColor: const MacosColor(0xFF1C1C1E),
        textColor: const MacosColor(0xFFFFFFFF),
        dialogBackgroundColor: const MacosColor(0xFF2C2C2E),
        buttonTheme: const MacosButtonThemeData(
          backgroundColor: _blueDark,
          textColor: MacosColor(0xFFFFFFFF),
        ),
        accentColor: _blueDark,
        inputColor: const MacosColor(0xFF2C2C2E),
      );
}
```

创建 `lib/ui/theme/theme_controller.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeMode>(ThemeController.new);

/// 主题模式控制器：默认跟随系统，预留手动切换。
class ThemeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void setDark(bool dark) => state = dark ? ThemeMode.dark : ThemeMode.light;
}
```

- [ ] **Step 4: 运行测试确认通过**

```powershell
flutter test test/ui/theme/theme_controller_test.dart
```

预期：全部 PASS。若 macos_ui 的 `MacosThemeData` 字段名与所装版本不一致，按该版本 API 调整（如 `primaryColor` 已改 `primary`），保持语义不变。

**检查点**：Task 7 完成标准 —— 主题控制器测试全绿。

---

### Task 8: 框架壳（侧边栏导航 + 内容区）

**Files:**
- Create: `lib/ui/shell/navigation_controller.dart`、`lib/ui/shell/shell_view.dart`、`lib/registry/toolbox_registry.dart`
- Modify: `lib/main.dart`（接入完整壳）、`lib/ui/window/app_window.dart`（自绘窗口按钮）
- Test: `test/ui/shell/shell_view_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `initAppWindow`/`ToolBoxApp`；Task 6 的 `ToolRegistry`/`ToolCategory`/`Tool`；Task 7 的 `ToolboxTheme`/`themeControllerProvider`
- Produces:
  - `class ToolboxRegistry extends ToolRegistry` —— 登记 discovery 工具（Task 9 完成后填入；本任务先注册一个占位工具 `_PlaceholderTool` 验证链路，Task 9 替换）
  - `final selectedToolProvider = NotifierProvider<NavigationController, Tool?>(...)`
  - `final sidebarExpandedProvider = StateProvider<bool>((_) => true)`
  - `class NavigationController extends Notifier<Tool?> { void select(Tool tool); }`
  - `class ShellView extends ConsumerWidget` —— MUISidebar 左侧导航（分类分组 → 工具项，图标+文字、选中高亮、折叠按钮）+ 右侧内容区（选中工具 buildContent；无选中显示占位）

- [ ] **Step 1: 写失败测试**

创建 `test/ui/shell/shell_view_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:toolbox/registry/platform_type.dart';
import 'package:toolbox/registry/tool.dart';
import 'package:toolbox/registry/tool_category.dart';
import 'package:toolbox/registry/tool_registry.dart';
import 'package:toolbox/registry/toolbox_registry.dart';
import 'package:toolbox/ui/shell/navigation_controller.dart';
import 'package:toolbox/ui/shell/shell_view.dart';
import 'package:toolbox/ui/theme/toolbox_theme.dart';

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
  Widget buildApp(ToolRegistry registry) => ProviderScope(
        overrides: [
          toolboxRegistryProvider.overrideWith((ref) => registry),
        ],
        child: MacosApp(
          theme: ToolboxTheme.light(),
          home: const ShellView(),
        ),
      );

  testWidgets('侧边栏渲染分类与工具项', (tester) async {
    await tester.pumpWidget(buildApp(_TestRegistry()));
    expect(find.text('数据库管理'), findsOneWidget);
    expect(find.text('工具一'), findsOneWidget);
    expect(find.text('工具二'), findsOneWidget);
  });

  testWidgets('点击工具项切换内容区', (tester) async {
    await tester.pumpWidget(buildApp(_TestRegistry()));
    await tester.tap(find.text('工具一'));
    await tester.pumpAndSettle();
    expect(find.text('内容区:工具一'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行确认失败**

```powershell
flutter test test/ui/shell/shell_view_test.dart
```

预期：编译失败（类型不存在）。

- [ ] **Step 3: 实现导航控制器**

创建 `lib/ui/shell/navigation_controller.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/registry/tool.dart';
import 'package:toolbox/registry/toolbox_registry.dart';

final selectedToolProvider =
    NotifierProvider<NavigationController, Tool?>(NavigationController.new);

final sidebarExpandedProvider = StateProvider<bool>((ref) => true);

/// 导航状态：当前选中工具。
class NavigationController extends Notifier<Tool?> {
  @override
  Tool? build() {
    // 默认选中第一个可用工具
    final tools = ref.watch(toolboxRegistryProvider).availableTools();
    return tools.isEmpty ? null : tools.first;
  }

  void select(Tool tool) => state = tool;
}
```

创建 `lib/registry/toolbox_registry.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/registry/tool.dart';
import 'package:toolbox/registry/tool_registry.dart';

final toolboxRegistryProvider = Provider<ToolRegistry>(
  (ref) => ToolboxRegistry(),
);

/// 应用注册表：集中登记全部工具。
class ToolboxRegistry extends ToolRegistry {
  @override
  List<Tool> registerAll() => [
        // Task 9 替换为 DatabaseDiscoveryTool
        _PlaceholderTool(),
      ];
}

class _PlaceholderTool extends Tool {
  @override
  String get id => 'tool-placeholder';
  @override
  String get name => '数据库发现';
  @override
  String get description => '扫描 IP 或网段，发现数据库服务';
  @override
  ToolCategory get category => ToolCategory.database;
  @override
  Set<PlatformType> get supportedPlatforms => {
        PlatformType.windows,
        PlatformType.linux,
        PlatformType.macOS,
      };
  @override
  Widget buildContent(BuildContext context) =>
      const Center(child: Text('数据库发现（占位）'));
}
```

- [ ] **Step 4: 实现 Shell 视图**

创建 `lib/ui/shell/shell_view.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:toolbox/registry/tool.dart';
import 'package:toolbox/registry/tool_registry.dart';
import 'package:toolbox/registry/toolbox_registry.dart';
import 'navigation_controller.dart';

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

    return MacosWindow(
      sidebar: Sidebar(
        width: expanded ? 220 : 56,
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController,
            children: [
              // 折叠按钮
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: MacosIconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () =>
                        ref.read(sidebarExpandedProvider.notifier).state =
                            !expanded,
                  ),
                ),
              ),
              for (final entry in grouped.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Text(
                    entry.key.displayName,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                for (final tool in entry.value)
                  SidebarItem(
                    icon: _iconFor(tool.category),
                    label: tool.name,
                    tooltipMessage: tool.description,
                    selected: tool == selected,
                    onPressed: () =>
                        ref.read(selectedToolProvider.notifier).select(tool),
                  ),
              ],
            ],
          );
        },
      ),
      child: selected?.buildContent(context) ??
          const Center(child: Text('未选择工具')),
    );
  }

  IconData _iconFor(ToolCategory category) => switch (category) {
        ToolCategory.data => Icons.data_object,
        ToolCategory.database => Icons.storage,
        ToolCategory.text => Icons.text_fields,
        ToolCategory.encode => Icons.code,
        ToolCategory.system => Icons.settings,
        ToolCategory.other => Icons.widgets,
      };
}
```

- [ ] **Step 5: 改造主入口**

替换 `lib/main.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:toolbox/ui/shell/shell_view.dart';
import 'package:toolbox/ui/theme/theme_controller.dart';
import 'package:toolbox/ui/theme/toolbox_theme.dart';
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
      return MacosApp(
        title: 'ToolBox',
        theme: ToolboxTheme.light(),
        darkTheme: ToolboxTheme.dark(),
        themeMode: themeMode,
        debugShowCheckedModeBanner: false,
        home: const ShellView(),
      );
    });
  }
}
```

- [ ] **Step 6: 运行测试确认通过**

```powershell
flutter test test/ui/shell/shell_view_test.dart
flutter analyze
```

预期：全部 PASS，analyze 无 error。若测试因 MUISidebar 布局宽度或动画需要 `pumpAndSettle` 超时，将侧边栏宽度固定为展开态后重试。

- [ ] **Step 7: 手动运行验证壳**

```powershell
flutter run -d windows
```

预期：左侧分类「数据库管理」下显示工具项，点击切换右侧内容区；折叠按钮生效；深色模式跟随系统切换。

**检查点**：Task 8 完成标准 —— Shell 测试全绿、运行可见完整导航壳。

---

### Task 9: 数据库发现工具（discovery feature）

**Files:**
- Create:
  - `lib/features/discovery/domain/database_discovery_tool.dart`
  - `lib/features/discovery/data/scan_service.dart`
  - `lib/features/discovery/presentation/discovery_controller.dart`
  - `lib/features/discovery/presentation/discovery_view.dart`
- Modify: `lib/registry/toolbox_registry.dart`（占位工具替换为 `DatabaseDiscoveryTool`）
- Test: `test/features/discovery/discovery_controller_test.dart`、`test/features/discovery/discovery_view_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `ScanTarget`/`ScanEvent`/`ScanResult`；Task 4 的 `ScanEngine`/`RealScanSocketFactory`；Task 5 的 `DefaultProbeRegistry`；Task 6 的 `Tool`/`ToolCategory`/`PlatformType`
- Produces:
  - `class DatabaseDiscoveryTool extends Tool`（id `tool-db-discovery`、name `数据库发现`、category database、supportedPlatforms {windows, linux, macOS}）
  - `class ScanService { ScanService({ScanEngine? engine}); Stream<ScanEvent> scan(String input, {Duration timeout}); void cancel(); }` —— 默认用 `RealScanSocketFactory` + `DefaultProbeRegistry` 构造引擎；解析 `ScanTarget.fromInput`（FormatException 上抛）
  - `class DiscoveryState { final String target; final Duration timeout; final bool scanning; final int done; final int total; final String? error; final Map<String, List<ScanResult>> groupedResults; }`
  - `final discoveryControllerProvider = NotifierProvider<DiscoveryController, DiscoveryState>(...)` —— `startScan()` / `stopScan()` / `setTarget(String)` / `setTimeout(Duration)`；分组规则：结果按 `ScanResult.ip` 分组，仅开放端口进入结果组，closed/timeout 不展示（在状态中累计计数）
  - `class DiscoveryView extends ConsumerWidget` —— 输入区（目标输入框 + 校验错误、超时选择下拉、扫描/停止按钮）+ 进度区（LinearProgress + done/total）+ 结果区（按主机分组的卡片列表：主机 IP、端口/服务图标/类型/版本/延迟；复制按钮）

- [ ] **Step 1: 写 controller 失败测试**

创建 `test/features/discovery/discovery_controller_test.dart`：

```dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/core/models/scan_event.dart';
import 'package:toolbox/core/models/scan_result.dart';
import 'package:toolbox/features/discovery/data/scan_service.dart';
import 'package:toolbox/features/discovery/presentation/discovery_controller.dart';

class _FakeScanService extends ScanService {
  _FakeScanService() : super(engine: null);

  @override
  Stream<ScanEvent> scan(String input, {Duration timeout = const Duration(seconds: 1)}) async* {
    yield const ProgressEvent(0, 2);
    yield ResultEvent(const ScanResult(
        ip: '192.168.1.1', port: 3306, status: ScanStatus.open,
        serviceType: 'MySQL', version: '8.0.41'));
    yield ResultEvent(const ScanResult(
        ip: '192.168.1.2', port: 6379, status: ScanStatus.open,
        serviceType: 'Redis'));
    yield const ProgressEvent(2, 2);
    yield const CompletedEvent();
  }
}

void main() {
  final container = ProviderContainer(overrides: [
    scanServiceProvider.overrideWith((ref) => _FakeScanService()),
  ]);
  tearDown(container.dispose);

  test('非法目标输入产生错误', () async {
    final c = container.read(discoveryControllerProvider.notifier);
    c.setTarget('abc');
    expect(container.read(discoveryControllerProvider).error, isNotNull);
    expect(container.read(discoveryControllerProvider).scanning, isFalse);
  });

  test('扫描完成后按主机分组结果', () async {
    final c = container.read(discoveryControllerProvider.notifier);
    c.setTarget('192.168.1.0/30');
    final done = c.startScan();
    await done;
    final s = container.read(discoveryControllerProvider);
    expect(s.scanning, isFalse);
    expect(s.groupedResults.keys, containsAll(['192.168.1.1', '192.168.1.2']));
    expect(s.groupedResults['192.168.1.1']!.single.serviceType, 'MySQL');
  });
}
```

- [ ] **Step 2: 运行确认失败**

```powershell
flutter test test/features/discovery/discovery_controller_test.dart
```

预期：编译失败。

- [ ] **Step 3: 实现 ScanService**

创建 `lib/features/discovery/data/real_socket_factory_stub.dart`（Web/无 IO 平台的兜底实现）：

```dart
import 'package:toolbox/core/scanner/scan_socket.dart';

/// 非 IO 平台（如 Web）的兜底：抛出 UnsupportedError。
class RealScanSocketFactory implements ScanSocketFactory {
  const RealScanSocketFactory();

  @override
  Future<ScanSocket> connect(String host, int port, Duration timeout) {
    throw UnsupportedError('当前平台不支持 Socket 扫描');
  }
}
```

创建 `lib/features/discovery/data/real_socket_factory_io.dart`（dart:io 生产实现）：

```dart
import 'dart:io';
import 'package:toolbox/core/scanner/scan_socket.dart';

/// dart:io Socket 实现：连接拒绝等错误统一转换为 ScanConnectException。
class RealScanSocketFactory implements ScanSocketFactory {
  const RealScanSocketFactory();

  @override
  Future<ScanSocket> connect(String host, int port, Duration timeout) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      return _RealScanSocket(socket);
    } on SocketException catch (e) {
      throw ScanConnectException(e.message);
    }
  }
}

class _RealScanSocket implements ScanSocket {
  _RealScanSocket(this._socket);
  final Socket _socket;

  @override
  Future<void> write(List<int> data) async => _socket.add(data);

  @override
  Future<List<int>> read(int maxBytes,
      {Duration timeout = const Duration(seconds: 2)}) async {
    final bytes = <int>[];
    await for (final chunk in _socket.timeout(timeout).take(maxBytes)) {
      bytes.addAll(chunk);
    }
    return bytes;
  }

  @override
  void destroy() => _socket.destroy();
}
```

创建 `lib/features/discovery/data/real_socket_factory.dart`（条件导入入口）：

```dart
import 'real_socket_factory_stub.dart'
    if (dart.library.io) 'real_socket_factory_io.dart';
```

创建 `lib/features/discovery/data/scan_service.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/core/models/scan_event.dart';
import 'package:toolbox/core/models/scan_target.dart';
import 'package:toolbox/core/protocols/default_probe_registry.dart';
import 'package:toolbox/core/scanner/scan_engine.dart';
import 'real_socket_factory.dart';

/// 扫描服务：解析目标 → 驱动引擎 → 事件流。测试可注入 fake 引擎。
class ScanService {
  ScanService({ScanEngine? engine})
      : engine = engine ??
            ScanEngine(
              socketFactory: const RealScanSocketFactory(),
              probeRegistry: DefaultProbeRegistry(),
            );

  final ScanEngine engine;

  Stream<ScanEvent> scan(String input,
      {Duration timeout = const Duration(seconds: 1)}) async* {
    final target = ScanTarget.fromInput(input); // FormatException 上抛
    yield* engine.scan(target.expandIpv4s(), _defaultPorts);
  }

  void cancel() => engine.cancel();
}

const _defaultPorts = [
  3306, 5432, 8123, 9000, 6379, 27017, 1433, 1521, 9200,
];

/// 扫描服务 Provider：测试通过 overrideWith 注入 fake。
final scanServiceProvider = Provider<ScanService>(
  (ref) => ScanService(),
);
```

- [ ] **Step 4: 实现 DiscoveryController**

创建 `lib/features/discovery/presentation/discovery_controller.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/core/models/scan_event.dart';
import 'package:toolbox/core/models/scan_result.dart';
import 'package:toolbox/core/models/scan_target.dart';
import 'package:toolbox/features/discovery/data/scan_service.dart';

class DiscoveryState {
  const DiscoveryState({
    this.target = '',
    this.timeout = const Duration(milliseconds: 1000),
    this.scanning = false,
    this.done = 0,
    this.total = 0,
    this.error,
    this.groupedResults = const {},
    this.hostCount = 0,
    this.openCount = 0,
  });

  final String target;
  final Duration timeout;
  final bool scanning;
  final int done;
  final int total;
  final String? error;
  final Map<String, List<ScanResult>> groupedResults;
  final int hostCount;
  final int openCount;

  DiscoveryState copyWith({
    String? target,
    Duration? timeout,
    bool? scanning,
    int? done,
    int? total,
    String? error,
    Map<String, List<ScanResult>>? groupedResults,
    int? hostCount,
    int? openCount,
  }) =>
      DiscoveryState(
        target: target ?? this.target,
        timeout: timeout ?? this.timeout,
        scanning: scanning ?? this.scanning,
        done: done ?? this.done,
        total: total ?? this.total,
        error: error ?? this.error,
        groupedResults: groupedResults ?? this.groupedResults,
        hostCount: hostCount ?? this.hostCount,
        openCount: openCount ?? this.openCount,
      );
}

final discoveryControllerProvider =
    NotifierProvider<DiscoveryController, DiscoveryState>(
        DiscoveryController.new);

class DiscoveryController extends Notifier<DiscoveryState> {
  @override
  DiscoveryState build() => const DiscoveryState();

  void setTarget(String target) {
    state = state.copyWith(target: target);
    if (target.trim().isNotEmpty) {
      try {
        ScanTarget.fromInput(target);
        state = state.copyWith(error: null);
      } on FormatException catch (e) {
        state = state.copyWith(error: e.message);
      }
    }
  }

  void setTimeout(Duration timeout) => state = state.copyWith(timeout: timeout);

  Future<void> startScan() async {
    final target = state.target.trim();
    try {
      ScanTarget.fromInput(target);
    } on FormatException catch (e) {
      state = state.copyWith(error: e.message);
      return;
    }
    final service = ref.read(scanServiceProvider);
    state = state.copyWith(
      scanning: true,
      error: null,
      done: 0,
      total: 0,
      groupedResults: const {},
      hostCount: 0,
      openCount: 0,
    );
    final grouped = <String, List<ScanResult>>{};
    var done = 0;
    var total = 0;
    var open = 0;
    await for (final event in service.scan(target, timeout: state.timeout)) {
      switch (event) {
        case ProgressEvent():
          done = event.done;
          total = event.total;
        case ResultEvent():
          final r = event.result;
          if (r.status == ScanStatus.open) {
            open++;
            grouped.putIfAbsent(r.ip, () => []).add(r);
            state = state.copyWith(
              groupedResults: Map.of(grouped),
              done: done,
              total: total,
              openCount: open,
              hostCount: grouped.length,
            );
          }
        case CompletedEvent():
          break;
      }
    }
    state = state.copyWith(
      scanning: false,
      done: done,
      total: total,
      groupedResults: Map.of(grouped),
      openCount: open,
      hostCount: grouped.length,
    );
  }

  void stopScan() {
    ref.read(scanServiceProvider).cancel();
    state = state.copyWith(scanning: false);
  }
}
```

- [ ] **Step 5: 运行 controller 测试确认通过**

```powershell
flutter test test/features/discovery/discovery_controller_test.dart
```

预期：全部 PASS。

- [ ] **Step 6: 写 View 失败测试**

创建 `test/features/discovery/discovery_view_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:toolbox/core/models/scan_result.dart';
import 'package:toolbox/features/discovery/presentation/discovery_controller.dart';
import 'package:toolbox/features/discovery/presentation/discovery_view.dart';
import 'package:toolbox/ui/theme/toolbox_theme.dart';

/// 固定状态控制器：测试直接注入预置状态。
class _StubController extends DiscoveryController {
  _StubController(this._fixed);
  final DiscoveryState _fixed;
  @override
  DiscoveryState build() => _fixed;
}

void main() {
  testWidgets('输入非法目标显示错误提示', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MacosApp(theme: ToolboxTheme.light(), home: const DiscoveryView()),
    ));
    await tester.enterText(find.byType(TextField).first, 'abc');
    await tester.pump();
    expect(find.textContaining('无效'), findsOneWidget);
  });

  testWidgets('预置结果按主机分组渲染', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        discoveryControllerProvider.overrideWith(
          () => _StubController(const DiscoveryState(
            groupedResults: {
              '192.168.1.1': [
                ScanResult(
                    ip: '192.168.1.1', port: 3306, status: ScanStatus.open,
                    serviceType: 'MySQL', version: '8.0.41'),
              ],
            },
            hostCount: 1,
            openCount: 1,
          )),
        ),
      ],
      child: MacosApp(theme: ToolboxTheme.light(), home: const DiscoveryView()),
    ));
    expect(find.text('192.168.1.1'), findsOneWidget);
    expect(find.text('MySQL'), findsOneWidget);
    expect(find.text('8.0.41'), findsOneWidget);
  });
}
```

- [ ] **Step 7: 运行确认失败**

```powershell
flutter test test/features/discovery/discovery_view_test.dart
```

预期：编译失败（DiscoveryView 不存在）。

- [ ] **Step 8: 实现 DiscoveryView**

创建 `lib/features/discovery/presentation/discovery_view.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:toolbox/core/models/scan_result.dart';
import 'discovery_controller.dart';

class DiscoveryView extends ConsumerWidget {
  const DiscoveryView({super.key});

  static const _timeoutOptions = <Duration>[
    Duration(milliseconds: 500),
    Duration(milliseconds: 1000),
    Duration(milliseconds: 2000),
    Duration(milliseconds: 5000),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(discoveryControllerProvider);
    final controller = ref.read(discoveryControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('数据库发现',
              style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 4),
          Text('扫描 IP 或 CIDR 网段，发现内网数据库服务',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          // 输入区
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: '例如 192.168.1.0/24',
                    labelText: '扫描目标',
                    errorText: state.error,
                  ),
                  onChanged: controller.setTarget,
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<Duration>(
                value: state.timeout,
                items: [
                  for (final t in _timeoutOptions)
                    DropdownMenuItem(
                        value: t,
                        child: Text('超时 ${t.inMilliseconds}ms')),
                ],
                onChanged: (v) {
                  if (v != null) controller.setTimeout(v);
                },
              ),
              const SizedBox(width: 8),
              state.scanning
                  ? MacosButton(
                      child: const Text('停止'),
                      onPressed: controller.stopScan,
                    )
                  : MacosButton(
                      child: const Text('扫描'),
                      onPressed: controller.startScan,
                    ),
            ],
          ),
          // 进度区
          if (state.scanning) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: state.total == 0 ? null : state.done / state.total,
            ),
            const SizedBox(height: 4),
            Text('扫描中 ${state.done}/${state.total} …'),
          ],
          if (!state.scanning &&
              state.hostCount > 0) ...[
            const SizedBox(height: 8),
            Text('发现 ${state.hostCount} 台主机、${state.openCount} 个开放端口'),
          ],
          const SizedBox(height: 16),
          // 结果区：按主机分组
          Expanded(
            child: state.hostCount == 0
                ? Center(
                    child: Text(state.scanning
                        ? '正在扫描…'
                        : '输入目标后点击「扫描」开始发现'),
                  )
                : ListView(
                    children: [
                      for (final entry in state.groupedResults.entries)
                        _HostCard(host: entry.key, results: entry.value),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _HostCard extends StatelessWidget {
  const _HostCard({required this.host, required this.results});

  final String host;
  final List<ScanResult> results;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dns, size: 18),
                const SizedBox(width: 8),
                Text(host, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            for (final r in results)
              ListTile(
                dense: true,
                leading: Icon(_iconFor(r.serviceType), size: 18),
                title: Text('${r.port} · ${r.serviceType ?? '未知服务'}'),
                subtitle: Text(r.version ?? ''),
                trailing: IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: '复制 IP:端口',
                  onPressed: () => Clipboard.setData(
                      ClipboardData(text: '${r.ip}:${r.port}')),
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String? service) => switch (service) {
        'MySQL' => Icons.storage,
        'Redis' => Icons.memory,
        'PostgreSQL' => Icons.dns,
        'MongoDB' => Icons.layers,
        'ClickHouse' => Icons.table_chart,
        'Elasticsearch' => Icons.search,
        'SQL Server' => Icons.schema,
        'Oracle' => Icons.account_tree,
        _ => Icons.radio_button_checked,
      };
}
```

- [ ] **Step 9: 运行 View 测试确认通过**

```powershell
flutter test test/features/discovery/discovery_view_test.dart
```

预期：全部 PASS。

- [ ] **Step 10: 替换占位工具**

修改 `lib/registry/toolbox_registry.dart`：删除 `_PlaceholderTool`，`registerAll()` 返回 `[DatabaseDiscoveryTool()]`（import `package:toolbox/features/discovery/domain/database_discovery_tool.dart`）。

创建 `lib/features/discovery/domain/database_discovery_tool.dart`：

```dart
import 'package:flutter/widgets.dart';
import 'package:toolbox/registry/platform_type.dart';
import 'package:toolbox/registry/tool.dart';
import 'package:toolbox/registry/tool_category.dart';
import '../presentation/discovery_view.dart';

class DatabaseDiscoveryTool extends Tool {
  @override
  String get id => 'tool-db-discovery';
  @override
  String get name => '数据库发现';
  @override
  String get description => '扫描 IP 或 CIDR 网段，发现数据库服务';
  @override
  ToolCategory get category => ToolCategory.database;
  @override
  Set<PlatformType> get supportedPlatforms => {
        PlatformType.windows,
        PlatformType.linux,
        PlatformType.macOS,
      };
  @override
  Widget buildContent(BuildContext context) => const DiscoveryView();
}
```

- [ ] **Step 11: 全量验证**

```powershell
flutter analyze
flutter test
flutter build windows --debug
```

预期：analyze 无 error，全部测试 PASS，构建成功。

- [ ] **Step 12: 手动真机验证**

```powershell
flutter run -d windows
```

验证步骤：① 输入 `127.0.0.1` 扫描，本机若运行 MySQL/Redis 应显示对应服务与版本 ② 输入 `192.168.1.0/24` 等网段扫描内网 ③ 扫描中点击「停止」立即停止 ④ 非法输入（`abc`）即时显示校验错误 ⑤ 复制按钮复制 `IP:端口` ⑥ 侧边栏折叠后仍可操作。

**检查点**：Task 9 完成标准 —— controller/view 测试全绿、全量 analyze/test/build 通过、真机扫描功能可用。

---

### Task 10: 重写 README（开源风格）

**Files:**
- Modify: `README.md`（替换 flutter create 模板）

- [ ] **Step 1: 编写 README**

按开源项目标准结构编写，包含：项目名与一句话简介、特性徽章行（Flutter/macos_ui/license 徽章占位，链接指向仓库实际地址）、特性列表（Apple 风格 UI、数据库发现、可扩展工具框架、明暗主题）、快速开始（源码运行：`flutter run -d windows`；安装包获取说明）、项目结构（lib/core、lib/ui、lib/features、lib/registry 说明）、技术栈表格、如何添加新工具（实现 Tool + 注册一行 + 平台声明）、构建安装包说明（`flutter build windows --release` + Inno Setup）、许可证（MIT，署名 shendongjuns）、截图占位（`![screenshot](docs/screenshots/main.png)` 留待补充）。

- [ ] **Step 2: 通读校验**

检查：无旧 Kotlin 项目残留描述、命令均为 Flutter 命令、徽章与仓库信息一致。

**检查点**：Task 10 完成标准 —— README 通读无矛盾，无 Kotlin 残留。

---

### Task 11: CI/CD（GitHub Actions + Inno Setup）

**Files:**
- Create: `.github/workflows/release.yml`、`.github/installer/toolbox.iss`、`.github/installer/README.md`（说明本地打包方式）
- Modify: 无（如需图标，将 `.ico` 放置于 `windows/runner/resources/`）

**Interfaces:**
- Consumes: Task 1-9 的工程与测试；tag 版本号（如 `v1.2.0`）
- Produces: 触发 `git tag v1.2.0 && git push` 后，Actions 产出 `ToolBox-Setup-1.2.0.exe` 与 `ToolBox-1.2.0-windows.zip` 附加到 Release

- [ ] **Step 1: 编写 Inno Setup 脚本**

创建 `.github/installer/toolbox.iss`：

```ini
; ToolBox 安装脚本（Inno Setup 6）
; 构建参数：/DAppVersion=x.y.z（由 CI 传入），未传时默认 1.0.0
#define MyAppName "ToolBox"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#ifndef MyAppSourceDir
  #define MyAppSourceDir "build\windows\x64\runner\Release"
#endif
#define MyAppPublisher "shendongjuns"
#define MyAppExeName "toolbox.exe"

[Setup]
AppId={{8F2B1C44-7A3E-4D9E-9B4A-5C1D0E2F3A4B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir=..\..
OutputBaseFilename=ToolBox-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务:"

[Files]
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent
```

- [ ] **Step 2: 编写 release workflow**

创建 `.github/workflows/release.yml`：

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write

jobs:
  build-windows:
    runs-on: windows-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable

      - name: Install dependencies
        run: flutter pub get

      - name: Analyze
        run: flutter analyze

      - name: Test
        run: flutter test

      - name: Build Windows
        run: flutter build windows --release

      - name: Compress portable zip
        shell: bash
        run: |
          cd build/windows/x64/runner/Release
          7z a ../../../../../ToolBox-portable.zip .

      - name: Setup Inno Setup
        uses: wangyucode/setup-innosetup@v2

      - name: Build installer
        env:
          APP_VERSION: ${{ github.ref_name }}  # 例如 v1.2.0
        run: |
          $ver = $env:APP_VERSION.TrimStart('v')
          $env:APP_VERSION = $ver
          iscc /DAppVersion=$ver .github/installer/toolbox.iss

      - name: Release
        uses: softprops/action-gh-release@v2
        with:
          files: |
            ToolBox-Setup-*.exe
            ToolBox-portable.zip
```

- [ ] **Step 3: 本地验证构建产物路径**

```powershell
flutter build windows --release
Get-ChildItem build\windows\x64\runner\Release\toolbox.exe
```

预期：`toolbox.exe` 存在（确认 Inno Setup 脚本中的 SourceDir 正确）。

- [ ] **Step 4: 本地安装 Inno Setup 验证脚本（若环境已装）**

```powershell
iscc /DAppVersion=1.2.0 .github/installer/toolbox.iss
```

若 `iscc` 不可用：跳过此步并在完成说明中标注「Inno Setup 脚本将在 CI 首次运行时验证」；确保 iss 中 `#ifndef` 逻辑允许 `{autopf}` 在非管理员模式下工作。

**检查点**：Task 11 完成标准 —— workflow 文件就绪、本地 build release 成功、iss 脚本无语法错误（若可本地验证）。

---

### Task 12: 最终验证与收尾

**Files:**
- Modify: 无（验证性任务）

- [ ] **Step 1: 全量测试与静态检查**

```powershell
flutter analyze
flutter test
flutter build windows --release
```

预期：全部通过，release 构建成功。

- [ ] **Step 2: 全功能手动回归**

按顺序验证：① 启动应用（无边框亚克力窗口）② 深色模式跟随系统 ③ 侧边栏折叠/展开与工具切换 ④ 数据库发现：非法输入校验、合法扫描、停止、结果分组展示与复制 ⑤ 关闭退出。

- [ ] **Step 3: 项目文件清单核对**

核对：`docs/superpowers/specs/2026-08-04-toolbox-flutter-v1-2-0-design.md` 存在；`.github/workflows/release.yml` 存在；`.gitignore` 为 Flutter 标准；原 Kotlin 文件无残留。

**检查点**：Task 12 完成标准 —— 全部验证通过，项目可交付。

---

## Self-Review 记录

- **Spec 覆盖**：设计文档各节均有对应任务 —— 窗口(Task 2)、主题(Task 7)、导航(Task 8)、注册表(Task 6)、扫描引擎(Task 4)、指纹库(Task 5)、发现工具(Task 9)、CI(Task 11)、README(Task 10)、清理脚手架(Task 1)。
- **占位符检查**：无 TBD；所有代码块为完整实现或明确的最小实现。
- **类型一致性**：`ScanResult`/`ScanEvent`/`ProbeResult`/`ProbeRegistry`/`ScanSocket`/`ScanEngine`/`Tool`/`ToolRegistry` 在各任务间签名一致。
- **已知现实调整点**：macos_ui 与 flutter_acrylic 的 API 字段名可能随版本演化，任务中已标注「按所装版本调整」的应对方式。

### 自检修正记录（2026-08-04）

1. **Web 编译安全**：core 层移除 dart:io 依赖 —— `RealScanSocketFactory` 从 core 移到 features/data 层，采用条件导入（stub + io 双实现）；引擎异常统一为 core 定义的 `ScanConnectException`（dart:io 的 `SocketException` 由工厂转换），引擎仅 catch `ScanConnectException`/`TimeoutException`（dart:async，纯 Dart 可用）。
2. **并发调度可靠性**：引擎并发控制改为 tracked-future 模式（worker 完成时从 active 列表移除自身），替代不可靠的 `isComplete` 轮询扩展。
3. **Riverpod 2.x API**：删除自定义 `ProviderOverride` 函数，统一使用 `xxxProvider.overrideWith(...)`；测试中不再直接给 Notifier 的 `state` 赋值（protected），View 测试改用固定状态 `_StubController`。
4. **测试环境**：widget 测试统一用 `MacosApp`（含 MaterialApp）包裹，保证 macos_ui 主题祖先存在；补齐缺失 import（toolbox_registry/toolbox_theme/macos_ui）。
5. **Inno Setup 脚本**：`GetEnv` 与命令行 `/D` 冲突问题修正为 `#ifndef MyAppVersion` 默认值模式。
6. **清理死代码**：Task 4 测试 FakeSocket 移除未使用的 onConnect 回调。
