# ToolBox 扫描准确性重构设计文档

> 日期：2026-08-05
> 状态：已确认（待用户审阅）
> 目标：消除扫描误报（未部署服务却报「有」），借鉴 Nmap 的服务版本探测逻辑重构识别流程。

---

## 一、背景与问题

用户反馈：很多 IP 和端口没有部署相应服务，扫描却告知有。定位到两个误报根源：

1. **端口兜底硬标服务名**：引擎逻辑 `探测失败 → 端口映射兜底标服务名`（任何 3306 开放端口即使握手探测失败也标「MySQL」）
2. **tcpwrapped 场景未识别**：防火墙/安全设备对未开放端口回 SYN-ACK（TCP 握手成功但无真实服务），被当作真实开放服务

调研 [Nmap 服务版本探测](https://nmap.org/book/vscan-technique.html)（业界权威）确认其核心原则：
- 端口状态四态：open / closed / filtered（无响应=过滤）/ open|filtered
- **探测失败 → unknown**（服务未知），从不因端口号报告服务
- 连接后无数据响应 → **tcpwrapped**（防火墙前端/TCP wrapper 典型特征）
- **端口号只决定先试哪种探测，绝不作为识别结论**

## 二、状态语义修正

```
enum ScanStatus { open, closed, filtered }
```

| 状态 | 判定 | 展示 |
|------|------|------|
| open | TCP 握手成功（SYN-ACK） | 开放 |
| closed | 收到 RST 明确拒绝 | 关闭 |
| filtered | 无响应/超时（防火墙丢包过滤） | 已过滤 |

原 `timeout` 归入 `filtered`（语义更准确：超时通常是被防火墙丢弃，而非明确的"关闭"）。

## 三、服务识别流程重构（核心）

```
连接成功（open）→ 按端口优先试对应协议探测（端口仅作探测提示）
  ├─ 指纹确认 → ProbeResult(serviceName, version)          → 「MySQL 8.0.41」
  ├─ 连接后立即断开/读取无数据 → 标记 tcpwrapped            → 「疑似防火墙代理」
  └─ 连接保持但指纹不匹配 → 标记 unknown                     → 「未知服务」
```

**关键变更**：删除「端口兜底硬标服务名」（`defaultServiceFor` 不再作为识别结论，仅作为探测顺序提示）。3306 开放但握手不符 → 显示「未知服务」，不再谎报 MySQL。

### 识别结果三态

```dart
enum ServiceIdentity {
  confirmed,   // 指纹确认：serviceName + version
  tcpwrapped,  // 连接后无数据/立即断开：疑似防火墙代理
  unknown,     // 连接保持但无匹配：服务未知
}
```

`ScanResult` 增加 `serviceIdentity` 字段（或重构 serviceType/version 语义），UI 按三态展示。

## 四、核心探测加强（降低指纹误判）

| 探测 | 现状 | 加强后 |
|------|------|--------|
| MySQL | 首字节 0x0a 即确认 | 校验完整握手包：首字节 0x0a + 版本串格式（数字.数字）+ 后续 capabilities 字段存在 |
| Redis | PING → +PONG 即确认 | PING → +PONG **后**发 INFO server，验证 `redis_version:` 字段（解析失败降级为 confirmed 无版本） |
| HTTP（CK/ES） | 响应头包含特征串 | 校验 `HTTP/1.x` 状态行格式 + 特征串 |
| PostgreSQL | 第 5 字节 0x52 即确认（布局错误：真实协议 0x52 在首字节） | 校验首字节 0x52 + 4 字节长度 + 认证类型字段合理范围 |
| 其余（Mongo/Oracle/SQLServer） | 单字节/简化 | 保持简化（探测失败落入 unknown/tcpwrapped，不误报） |

所有探测失败路径：**不再返回兜底服务名**，由引擎按连接行为归类 tcpwrapped / unknown。

## 五、UI 展示调整

| 区域 | 展示 |
|------|------|
| 状态列 | 结果列表**仅展示 open**（closed/filtered 仅计入进度计数，不进入结果分组）；扫描中状态列文本「开放」 |
| 服务列 | 「MySQL 8.0.41」/「未知服务」/「疑似防火墙代理」（三态区分） |
| 版本列 | confirmed 有版本显示版本；其余为空 |
| 统计 | 开放端口数统计仅计 open（不变） |

## 六、实施范围

| 改动 | 文件 |
|------|------|
| 状态语义 | `lib/core/models/scan_result.dart`（ScanStatus 加 filtered 去 timeout） |
| 识别三态 | `lib/core/models/scan_result.dart`（ServiceIdentity / ScanResult 字段） |
| 识别流程重构 | `lib/core/scanner/scan_engine.dart`（探测结果三态归类，删除兜底硬标） |
| 探测加强 | `lib/core/protocols/mysql_probe.dart`、`redis_probe.dart`、`http_probe.dart`、`postgresql_probe.dart` |
| 指纹库接口 | `lib/core/protocols/service_probe.dart`（ProbeResult 语义明确化，或新增识别结果类型） |
| UI 展示 | `lib/features/discovery/presentation/discovery_view.dart`（状态/服务列三态展示） |
| 测试 | `test/core/scanner/scan_engine_test.dart`、`test/core/protocols/probes_test.dart`、`test/features/discovery/` |

**不动**：扫描调度/并发/超时逻辑、controller 状态机（扫描流程不变）、分页/折叠交互、注册表/主题。

## 七、测试策略

- 引擎测试：探测失败且连接无数据 → tcpwrapped；探测失败但连接保持 → unknown；探测确认 → confirmed；closed/filtered 状态正确
- 指纹测试：各探测加强后的确认/拒绝路径（MySQL 伪握手拒绝、Redis 无 INFO 降级、HTTP 非状态行拒绝）
- 发现页测试：三态展示文案渲染
- 全量：flutter analyze + flutter test + flutter build windows --release

## 八、非目标

- 不做 Nmap 式多轮多探测字符串（probe 循环），单轮探测 + 三态归类已满足误报消除
- 不做 ICMP 在线检测（用户可选后续增强）
- 不改变并发/超时配置逻辑
