# ToolBox 扫描准确性重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 消除扫描误报：状态三态（open/closed/filtered）、服务识别三态（confirmed/tcpwrapped/unknown）、删除端口兜底硬标服务名、加强核心探测校验。借鉴 Nmap 服务版本探测逻辑。

**Architecture:** core 层改动：`ScanResult` 增加 `serviceIdentity` 与 `filtered` 状态；`ProbeResult` 重构为三态（outcome）；引擎按探测结果三态归类、删除 `defaultServiceFor` 兜底硬标；MySQL/Redis/HTTP/PostgreSQL 探测加强校验。UI 三态展示。

**Tech Stack:** Flutter 3.44.8、纯 Dart core（零 Flutter 依赖）。

## Global Constraints

- **不执行任何 git 提交**（用户指令）。任务以「测试/构建通过」为完成标准。
- `lib/core/` 零 Flutter 依赖、无 dart:io（条件导入已有）。
- 状态语义：open（TCP 握手成功）/ closed（RST 拒绝）/ **filtered（无响应/超时，替代原 timeout）**。
- 识别三态：`ServiceIdentity { confirmed, tcpwrapped, unknown }` —— confirmed 携带 serviceName+version；tcpwrapped（连接后无数据/立即断开，展示「疑似防火墙代理」）；unknown（连接保持但指纹不匹配，展示「未知服务」）。
- **删除端口兜底硬标**：`defaultServiceFor` 不再作为识别结论（端口→服务映射仅作探测提示，`probeFor` 已按端口注册）。
- UI 文案中文：状态列「开放 / 关闭 / 已过滤」，服务列「服务名 版本 / 未知服务 / 疑似防火墙代理」。
- 所有命令在项目根目录 `d:\project\ai\tool-box` 执行（PowerShell）。

---

### Task 1: core 模型（状态语义 + 识别三态）

**Files:**
- Modify: `lib/core/models/scan_result.dart`
- Test: `test/core/scanner/scan_engine_test.dart`（引用 ScanStatus.timeout 处同步）

**Interfaces:**
- Consumes: 无
- Produces:
  - `enum ScanStatus { open, closed, filtered }`（timeout 移除，语义归入 filtered）
  - `enum ServiceIdentity { confirmed, tcpwrapped, unknown }`
  - `class ScanResult` 增加 `final ServiceIdentity serviceIdentity;`（构造参数，默认 `ServiceIdentity.confirmed` 以最小化既有调用点改动——但引擎 Task 3 会显式传）

- [ ] **Step 1: 修改模型**

`lib/core/models/scan_result.dart`：
- `ScanStatus.timeout` → 改为 `filtered`（注释：无响应/超时，防火墙丢包过滤）
- 新增 `enum ServiceIdentity { confirmed, tcpwrapped, unknown }`
- `ScanResult` 增加字段与构造参数：`this.serviceIdentity = ServiceIdentity.confirmed`（默认值保证既有构造调用兼容）

- [ ] **Step 2: 同步既有引用**

全仓 grep `ScanStatus.timeout`（预期在 `test/core/scanner/scan_engine_test.dart` 的「拒绝连接 → closed，超时 → timeout」用例）：改为 `ScanStatus.filtered`，用例名同步「超时 → filtered」。

- [ ] **Step 3: 验证**

```powershell
flutter test test/core/scanner/scan_engine_test.dart
flutter analyze
```

预期：引擎测试通过（此时引擎仍产 timeout？—— 不，引擎 Task 3 才改；本任务先改模型，引擎若编译报错（构造 ScanResult 引用 timeoout）则同步修正引擎的 ScanStatus.timeout 引用为 filtered，行为等价）。analyze 0 issues。

**检查点**：Task 1 完成标准 —— 模型三态就位、全仓无 ScanStatus.timeout 残留、测试通过。

---

### Task 2: 指纹库接口三态化与探测加强

**Files:**
- Modify: `lib/core/protocols/service_probe.dart`（ProbeResult 三态）
- Modify: `lib/core/protocols/mysql_probe.dart`、`redis_probe.dart`、`http_probe.dart`、`postgresql_probe.dart`（加强校验）
- Test: `test/core/protocols/probes_test.dart`

**Interfaces:**
- Consumes: Task 1 的模型；`ScanSocket`（read/write/destroy）
- Produces:
  - `enum ProbeOutcome { confirmed, unknown, tcpwrapped }`
  - `class ProbeResult { const ProbeResult({required this.outcome, this.serviceName, this.version}); final ProbeOutcome outcome; final String? serviceName; final String? version; }`（confirmed 时 serviceName 必填；unknown/tcpwrapped 时两者为空）
  - 各探测返回语义：指纹确认 → confirmed+服务名+版本；读到数据但格式不符 → unknown；读不到数据（空/EOF/超时）→ tcpwrapped；探测抛异常由引擎兜底（Task 3）

- [ ] **Step 1: 写失败测试（加强校验 + 三态）**

`test/core/protocols/probes_test.dart` 更新/新增：
- MySQL：正常握手 → confirmed('MySQL', '8.0.41')；**伪握手拒绝**（首字节 0x0a 但版本串非法，如 `0x0a` 后直接 0x00 空版本或 `abc` 非数字格式）→ unknown；**无数据**（read 返回空）→ tcpwrapped
- Redis：`+PONG` 且后续 `INFO` 响应含 `redis_version:` → confirmed('Redis', 版本)；`+PONG` 但 INFO 无 redis_version（或 INFO 读取失败）→ confirmed('Redis') 无版本（服务确认但版本未知）；读空 → tcpwrapped
- HTTP：响应头含 `HTTP/1.1 200` 状态行 + CK 特征 → confirmed；**非 HTTP 状态行**（如 `FOO` 开头）→ unknown；读空 → tcpwrapped
- PostgreSQL：长度前缀+0x52+认证类型 → confirmed；第 5 字节非 0x52 → unknown；读空 → tcpwrapped
- 其余探测（Mongo/Oracle/SQLServer）保持原简化行为，仅更新返回类型（confirmed 语义）

- [ ] **Step 2: 运行确认失败**

```powershell
flutter test test/core/protocols/probes_test.dart
```

预期：编译失败（ProbeResult 无 outcome 字段）。

- [ ] **Step 3: 实现三态接口与探测加强**

`lib/core/protocols/service_probe.dart`：按 Interfaces 定义 `ProbeOutcome`/`ProbeResult`。

`mysql_probe.dart`（加强）：
```dart
@override
Future<ProbeResult?> probe(ScanSocket socket) async {
  final data = await socket.read(64);
  if (data.isEmpty) return const ProbeResult(outcome: ProbeOutcome.tcpwrapped);
  if (data.first != 0x0a) return const ProbeResult(outcome: ProbeOutcome.unknown);
  final versionBytes = <int>[];
  for (final b in data.skip(1)) {
    if (b == 0x00) break;
    versionBytes.add(b);
  }
  final version = String.fromCharCodes(versionBytes);
  // 版本串必须是 数字.数字 格式才算确认（伪握手拒绝）
  if (!RegExp(r'^\d+\.\d+').hasMatch(version)) {
    return const ProbeResult(outcome: ProbeOutcome.unknown);
  }
  return ProbeResult(outcome: ProbeOutcome.confirmed, serviceName: serviceName, version: version);
}
```

`redis_probe.dart`（加强）：
```dart
@override
Future<ProbeResult?> probe(ScanSocket socket) async {
  await socket.write('PING\r\n'.codeUnits);
  final ping = await socket.read(32);
  if (ping.isEmpty) return const ProbeResult(outcome: ProbeOutcome.tcpwrapped);
  if (!String.fromCharCodes(ping).startsWith('+PONG')) {
    return const ProbeResult(outcome: ProbeOutcome.unknown);
  }
  // 二次验证：INFO server 取版本（失败降级为 confirmed 无版本）
  await socket.write('INFO server\r\n'.codeUnits);
  final info = String.fromCharCodes(await socket.read(4096));
  final m = RegExp(r'redis_version:([\d.]+)').firstMatch(info);
  return ProbeResult(
    outcome: ProbeOutcome.confirmed,
    serviceName: serviceName,
    version: m?.group(1),
  );
}
```

`http_probe.dart`（加强）：
```dart
@override
Future<ProbeResult?> probe(ScanSocket socket) async {
  await socket.write('GET / HTTP/1.0\r\nHost: localhost\r\n\r\n'.codeUnits);
  final data = await socket.read(4096);
  if (data.isEmpty) return const ProbeResult(outcome: ProbeOutcome.tcpwrapped);
  final head = String.fromCharCodes(data);
  if (!head.startsWith('HTTP/1.')) return const ProbeResult(outcome: ProbeOutcome.unknown);
  if (head.contains('X-ClickHouse-Server-Display-Name')) {
    return const ProbeResult(outcome: ProbeOutcome.confirmed, serviceName: 'ClickHouse');
  }
  if (head.contains('"tagline"')) {
    final m = RegExp(r'"number"\s*:\s*"([^"]+)"').firstMatch(head);
    return ProbeResult(outcome: ProbeOutcome.confirmed, serviceName: 'Elasticsearch', version: m?.group(1));
  }
  return const ProbeResult(outcome: ProbeOutcome.unknown);
}
```

`postgresql_probe.dart`（加强）：长度前缀（前 4 字节大端长度 ≥ 8 且 ≤ 64）+ 第 5 字节 0x52 + 认证类型（字节 6-7）合理值 → confirmed；否则 unknown；读空 → tcpwrapped。

其余探测（mongodb/sqlserver/oracle）：读空 → tcpwrapped，数据但格式不符 → unknown，符合 → confirmed（原判定逻辑保留，仅补三态返回值）。

- [ ] **Step 4: 运行测试确认通过**

```powershell
flutter test test/core/protocols/probes_test.dart
```

预期：全部 PASS。

**检查点**：Task 2 完成标准 —— 指纹测试全绿、三态接口就位、四个核心探测加强完成。

---

### Task 3: 引擎识别流程重构（删除兜底硬标）

**Files:**
- Modify: `lib/core/scanner/scan_engine.dart`
- Test: `test/core/scanner/scan_engine_test.dart`

**Interfaces:**
- Consumes: Task 1 模型（ServiceIdentity/ScanStatus.filtered）、Task 2 ProbeResult 三态
- Produces: 引擎识别流程：
  - connect 成功 → 查 `probeRegistry.probeFor(port)`：
    - 有探测器：`probe.probe(socket)` → `ProbeResult.outcome` 映射为 `ScanResult.serviceIdentity`（confirmed/tcpwrapped/unknown），serviceType/version 透传
    - 无探测器（防御）：做一次短超时空读（`read(1, timeout: 500ms)`）→ 有数据 → unknown；空/超时 → tcpwrapped
  - **删除 `probeRegistry.defaultServiceFor(port)` 兜底硬标**（不再把开放端口按端口映射标服务名）
  - 探测抛异常 → tcpwrapped（连接被中断）
  - 状态映射：connect 超时（TimeoutException）→ filtered；拒绝（ScanConnectException）→ closed

- [ ] **Step 1: 更新引擎测试（三态场景）**

`test/core/scanner/scan_engine_test.dart`：
- 现有用例适配：ScanStatus.timeout → filtered；`_FakeProbeRegistry` 的探测返回类型适配 ProbeResult 三态
- 新增用例：
  - 探测返回 `unknown` → 结果 `serviceIdentity == unknown`、`serviceType == null`
  - 探测返回 `tcpwrapped` → 结果 `serviceIdentity == tcpwrapped`
  - 探测确认 → `serviceIdentity == confirmed` + serviceType/version 透传
  - 无探测器端口（probeFor 返回 null）：fake socket 有数据 → unknown；无数据 → tcpwrapped
  - 超时 → `ScanStatus.filtered`
  - **关键断言：不再出现「按端口兜底标服务名」**（probeRegistry.defaultServiceFor 不再被调用——可用 fake 记录调用次数断言 0 次）

- [ ] **Step 2: 运行确认失败**

```powershell
flutter test test/core/scanner/scan_engine_test.dart
```

预期：编译失败/部分失败。

- [ ] **Step 3: 重构引擎识别逻辑**

`lib/core/scanner/scan_engine.dart` 的 `_scanOne` 中，连接成功后的处理改为：

```dart
try {
  final probe = probeRegistry.probeFor(port);
  ProbeResult? probeResult;
  if (probe != null) {
    probeResult = await probe
        .probe(socket)
        .timeout(const Duration(seconds: 2), onTimeout: () => null);
  } else {
    // 无探测器端口：空读判断
    final data = await socket.read(1, timeout: const Duration(milliseconds: 500));
    probeResult = data.isEmpty
        ? const ProbeResult(outcome: ProbeOutcome.tcpwrapped)
        : const ProbeResult(outcome: ProbeOutcome.unknown);
  }
  if (probeResult == null) {
    // 探测超时（2s 无响应）：无数据 → tcpwrapped
    return ScanResult(
      ip: ip, port: port, status: ScanStatus.open,
      serviceIdentity: ServiceIdentity.tcpwrapped,
      latency: DateTime.now().difference(started),
    );
  }
  return ScanResult(
    ip: ip,
    port: port,
    status: ScanStatus.open,
    serviceIdentity: switch (probeResult.outcome) {
      ProbeOutcome.confirmed => ServiceIdentity.confirmed,
      ProbeOutcome.tcpwrapped => ServiceIdentity.tcpwrapped,
      ProbeOutcome.unknown => ServiceIdentity.unknown,
    },
    serviceType: probeResult.serviceName,
    version: probeResult.version,
    latency: DateTime.now().difference(started),
  );
} catch (_) {
  // 探测异常（连接被断等）→ tcpwrapped
  return ScanResult(
    ip: ip, port: port, status: ScanStatus.open,
    serviceIdentity: ServiceIdentity.tcpwrapped,
    latency: DateTime.now().difference(started),
  );
} finally {
  socket.destroy();
}
```

同时：状态映射处 `on TimeoutException → ScanStatus.filtered`；`on ScanConnectException → ScanStatus.closed`。删除 `defaultServiceFor` 的使用。

- [ ] **Step 4: 运行测试确认通过**

```powershell
flutter test test/core/scanner/scan_engine_test.dart
```

预期：全部 PASS（含三态新增用例）。

**检查点**：Task 3 完成标准 —— 引擎测试全绿、`defaultServiceFor` 不再被引擎调用、无兜底硬标。

---

### Task 4: UI 三态展示

**Files:**
- Modify: `lib/features/discovery/presentation/discovery_view.dart`
- Modify: `test/features/discovery/discovery_view_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `ServiceIdentity`；`DiscoveryState.groupedResults` 不变
- Produces: 服务列三态展示：
  - confirmed → `服务名`（+ 版本在 subtitle）
  - tcpwrapped → 「疑似防火墙代理」（tertiary 色）
  - unknown → 「未知服务」（tertiary 色）

- [ ] **Step 1: 修改展示**

`discovery_view.dart` 的 `_HostCard` 服务行（FTile title）：服务名文本逻辑改为：

```dart
final identity = r.serviceIdentity;
final titleText = switch (identity) {
  ServiceIdentity.confirmed => r.serviceType ?? '未知服务',
  ServiceIdentity.tcpwrapped => '疑似防火墙代理',
  ServiceIdentity.unknown => '未知服务',
};
title: Text('${r.port} · $titleText'),
subtitle: identity == ServiceIdentity.confirmed ? Text(r.version ?? '') : null,
```

图标：tcpwrapped/unknown 用中性图标（Icons.help_outline 或保留原 `_serviceIcon` 的默认分支），confirmed 用品牌图标。

- [ ] **Step 2: 更新测试**

`discovery_view_test.dart`：预置的 ScanResult 构造新增 `serviceIdentity`（默认 confirmed 兼容）；新增用例：tcpwrapped 结果显示「疑似防火墙代理」、unknown 结果显示「未知服务」。

- [ ] **Step 3: 验证**

```powershell
flutter test test/features/discovery/discovery_view_test.dart
flutter analyze
```

预期：全部 PASS、analyze 0 issues。

**检查点**：Task 4 完成标准 —— 发现页测试全绿、三态展示就位。

---

### Task 5: 全量验证

**Files:**
- Modify: `README.md`（若提及扫描逻辑描述处，如「8 种数据库识别」补充三态说明——按需）

- [ ] **Step 1: 全量验证**

```powershell
flutter analyze
flutter test
flutter build windows --release
```

预期：analyze 0 issues、全部测试通过、release 构建成功（C1083 时先删 .dart_tool\flutter_build）。

- [ ] **Step 2: 启动冒烟**

```powershell
flutter run -d windows
```

预期：启动无崩溃。手动验证清单写入报告：①扫 127.0.0.1 本机开放端口（确认服务识别正确）②扫描时状态列显示「开放/关闭/已过滤」③无服务的开放端口显示「未知服务」或「疑似防火墙代理」而非误报服务名 ④探测加强后 MySQL/Redis 识别正常。

**检查点**：Task 5 完成标准 —— 全量验证通过、误报场景人工确认。

---

## Self-Review 记录

- **Spec 覆盖**：状态语义(Task 1)、探测加强(Task 2)、识别流程(Task 3)、UI 展示(Task 4)、验证(Task 5)。
- **占位符检查**：无 TBD；关键代码块完整（探测加强、引擎重构全量给出）。
- **类型一致性**：`ScanStatus.filtered`/`ServiceIdentity`/`ProbeOutcome`/`ProbeResult(outcome, serviceName, version)` 跨任务签名一致；`ScanResult` 新增字段带默认值保证兼容。
- **已知风险**：Redis INFO 二次验证对某些 Redis 变体（如代理）可能无响应——已设计降级（confirmed 无版本）；探测超时（2s onTimeout → null）归 tcpwrapped；probeFor 为 null 的防御路径仅影响非默认端口（当前端口清单固定，实际不会触发）。
