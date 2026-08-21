/// 监控数据模型与命令输出解析器（纯函数，便于单测）。
library;

/// 磁盘分区使用。
class DiskUsage {
  const DiskUsage({
    required this.mount,
    required this.totalBytes,
    required this.usedBytes,
  });

  final String mount;
  final int totalBytes;
  final int usedBytes;

  double get percent => totalBytes <= 0 ? 0 : usedBytes / totalBytes;
}

/// GPU 状态。
class GpuUsage {
  const GpuUsage({
    required this.index,
    required this.name,
    required this.utilPercent,
    required this.memUsedMiB,
    required this.memTotalMiB,
    required this.tempC,
    required this.powerWatts,
  });

  final int index;
  final String name;
  final double utilPercent;
  final double memUsedMiB;
  final double memTotalMiB;
  final double tempC;
  /// 当前功耗（瓦）。
  final double powerWatts;
}

/// 华为昇腾 NPU 状态。
class NpuUsage {
  const NpuUsage({
    required this.index,
    required this.name,
    required this.aiCorePercent,
    required this.hbmPercent,
    required this.powerWatts,
    required this.tempC,
    required this.health,
  });

  final int index;
  final String name;

  /// AI Core 使用率（0-100）。
  final double aiCorePercent;

  /// HBM 内存使用率（0-100）。
  final double hbmPercent;

  /// 功耗（瓦）。
  final double powerWatts;

  /// 温度（°C）。
  final double tempC;

  /// 健康状态（OK / Warning / Alarm / Critical / UNKNOWN）。
  final String health;
}

/// TOP 进程。
class TopProcess {
  const TopProcess({
    required this.pid,
    required this.name,
    required this.cpuPercent,
    required this.memPercent,
  });

  final int pid;
  final String name;
  final double cpuPercent;
  final double memPercent;
}

/// 单次采集结果。
class MonitorMetrics {
  const MonitorMetrics({
    required this.timestamp,
    required this.cpuPercent,
    required this.memUsedBytes,
    required this.memTotalBytes,
    required this.swapUsedBytes,
    required this.swapTotalBytes,
    required this.disks,
    required this.gpus,
    this.npus = const [],
    required this.netRxBytesPerSec,
    required this.netTxBytesPerSec,
    required this.load1,
    required this.load5,
    required this.load15,
    required this.processes,
    this.cpuCores = 1,
  });

  final DateTime timestamp;
  final double cpuPercent;
  final int memUsedBytes;
  final int memTotalBytes;
  final int swapUsedBytes;
  final int swapTotalBytes;
  final List<DiskUsage> disks;
  final List<GpuUsage> gpus;
  final List<NpuUsage> npus;
  final double netRxBytesPerSec;
  final double netTxBytesPerSec;
  final double load1;
  final double load5;
  final double load15;
  final List<TopProcess> processes;

  /// CPU 核心数（用于换算进程 CPU 占比）。
  final int cpuCores;

  double get memPercent =>
      memTotalBytes <= 0 ? 0 : memUsedBytes / memTotalBytes;
}

/// 解析 /proc/stat 的一行 cpu 数据为 tick 数组。
List<int> parseCpuTicks(String line) {
  final parts = line.split(RegExp(r'\s+'));
  final ticks = <int>[];
  for (var i = 1; i < parts.length; i++) {
    ticks.add(int.tryParse(parts[i]) ?? 0);
  }
  return ticks;
}

/// 依据两次 /proc/stat 的 cpu 行计算使用率（0-100）。
double parseCpuUsage(List<int> prev, List<int> cur) {
  int sum(List<int> t) => t.fold(0, (a, b) => a + b);
  final prevIdle = prev.length > 3 ? prev[3] + (prev.length > 4 ? prev[4] : 0) : 0;
  final curIdle = cur.length > 3 ? cur[3] + (cur.length > 4 ? cur[4] : 0) : 0;
  final prevTotal = sum(prev);
  final curTotal = sum(cur);
  final totalDelta = curTotal - prevTotal;
  if (totalDelta <= 0) return 0;
  final idleDelta = curIdle - prevIdle;
  return ((totalDelta - idleDelta) / totalDelta * 100).clamp(0, 100);
}

/// 解析 /proc/meminfo 为 key -> kB 的映射。
Map<String, int> parseMemInfo(String text) {
  final result = <String, int>{};
  for (final line in text.split('\n')) {
    final parts = line.split(':');
    if (parts.length < 2) continue;
    final key = parts[0].trim();
    final value = int.tryParse(parts[1].trim().split(RegExp(r'\s+')).first) ?? 0;
    result[key] = value;
  }
  return result;
}

/// 解析 `df -P` 输出为磁盘列表。
List<DiskUsage> parseDf(String text) {
  final result = <DiskUsage>[];
  final lines = text.trim().split('\n');
  for (var i = 1; i < lines.length; i++) {
    final parts = lines[i].trim().split(RegExp(r'\s+'));
    if (parts.length < 6) continue;
    final total = int.tryParse(parts[1]) ?? 0;
    final used = int.tryParse(parts[2]) ?? 0;
    final mount = parts[5];
    if (total <= 0 || mount.isEmpty) continue;
    result.add(DiskUsage(
      mount: mount,
      totalBytes: total * 1024,
      usedBytes: used * 1024,
    ));
  }
  return result;
}

/// 解析 `nvidia-smi --query-gpu=... --format=csv,noheader` 输出为 GPU 列表。
List<GpuUsage> parseNvidiaSmi(String text) {
  final result = <GpuUsage>[];
  final lines = text.trim().split('\n');
  for (var i = 0; i < lines.length; i++) {
    final parts = lines[i].split(',');
    if (parts.length < 4) continue;
    double num(String s) =>
        double.tryParse(s.trim().split(RegExp(r'\s+')).first) ?? 0;
    result.add(GpuUsage(
      index: i,
      name: parts[0].trim(),
      utilPercent: num(parts[1]),
      memUsedMiB: num(parts[2]),
      memTotalMiB: num(parts[3]),
      tempC: parts.length > 4 ? num(parts[4]) : 0,
      powerWatts: parts.length > 5 ? num(parts[5]) : 0,
    ));
  }
  return result;
}

/// 解析 `npu-smi info` 默认表格输出为 NPU 列表。
///
/// 表格每 NPU 两行：
///   `| N  Name  | Health | Power(W)  Temp(C)  Hugepages |`  （NPU 行）
///   `| C  Dev   | Bus-Id | AICore(%) Memory-Usage(MB)   |`  （Chip 行）
/// 按 `|` 切分、按 NPU 行（首列是数字）分组，Chip 行取 AICore/Memory。
List<NpuUsage> parseNpuSmi(String text) {
  final result = <NpuUsage>[];
  final lines = text.split('\n');

  List<String> cells(String line) =>
      line.split('|').map((e) => e.trim()).toList();

  String? curName;
  String? curHealth;
  String? curPower;
  String? curTemp;
  String? curAicore;
  String? curMemory;

  void flush() {
    if (curName == null) return;
    // Memory-Usage 形如 `3154 / 21527` 或 `0 / 0`。
    final memParts =
        (curMemory ?? '').split('/').map((e) => e.trim()).toList();
    final memUsed = double.tryParse(memParts.isNotEmpty ? memParts[0] : '') ?? 0;
    final memTotal =
        double.tryParse(memParts.length > 1 ? memParts[1] : '') ?? 0;
    result.add(NpuUsage(
      index: result.length,
      name: curName!,
      aiCorePercent: double.tryParse(curAicore ?? '') ?? 0,
      // HBM 使用率 = 已用 / 总量 * 100。
      hbmPercent: memTotal > 0 ? memUsed / memTotal * 100 : 0,
      powerWatts: double.tryParse(curPower ?? '') ?? 0,
      tempC: double.tryParse(curTemp ?? '') ?? 0,
      health: curHealth ?? '',
    ));
    curName = null;
    curHealth = null;
    curPower = null;
    curTemp = null;
    curAicore = null;
    curMemory = null;
  }

  for (final line in lines) {
    final c = cells(line);
    if (c.length < 4) continue; // [0] 行首空 + [1][2][3]
    // c[1] 形如 `1       310P3`（id + 名称）或 `0       0`（chip + dev）。
    final c1First = c[1].split(RegExp(r'\s+')).first;
    final isNumeric = int.tryParse(c1First) != null;
    // 排除进程表行：c[2] 是纯数字 PID、c[3] 是进程名（非数值）。
    final c2IsPid = int.tryParse(c[2]) != null;
    final c3First = c[3].split(RegExp(r'\s+')).first;
    final c3IsValue = int.tryParse(c3First) != null || c3First == 'NA';
    // NPU 行：c[1] 首段是数字，c[2] 是 Health（非 PID、非 Bus-Id），
    // c[3] 是 Power/Temp（数值或 NA）。
    if (isNumeric &&
        !c2IsPid &&
        !c[2].startsWith('NPU') &&
        !c[2].startsWith('Chip') &&
        !c[2].contains(':') &&
        !c[2].contains('.') &&
        c3IsValue) {
      flush();
      final c1Parts = c[1].split(RegExp(r'\s+'));
      curName = c1Parts.length > 1 ? c1Parts[1] : 'NPU $c1First';
      curHealth = c[2];
      // c[3] 含 Power/Temp/Hugepages：`90.4  48  0 / 0`。
      final p3 = c[3].split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
      curPower = p3.isNotEmpty ? p3[0] : null;
      curTemp = p3.length > 1 ? p3[1] : null;
    }
    // Chip 行：c[1] 首段是数字，c[2] 是 Bus-Id（含冒号/点）。
    else if (isNumeric &&
        (c[2].contains(':') || c[2].contains('.'))) {
      // c[3] 含 AICore/Memory：`0  3154 / 21527`。
      final p3 = c[3].split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
      curAicore = p3.isNotEmpty ? p3[0] : null;
      // 内存是 aicore 之后的 `3154 / 21527`。
      curMemory = p3.skip(1).join(' ');
    }
  }
  flush();

  return result;
}
Map<String, (int rx, int tx)> parseNetDev(String text) {
  final result = <String, (int, int)>{};
  for (final line in text.split('\n')) {
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    final iface = line.substring(0, colon).trim();
    if (iface == 'lo') continue;
    final nums = line.substring(colon + 1).trim().split(RegExp(r'\s+'));
    if (nums.length < 8) continue;
    final rx = int.tryParse(nums[0]) ?? 0;
    final tx = int.tryParse(nums[8]) ?? 0;
    result[iface] = (rx, tx);
  }
  return result;
}

/// 依据两次 /proc/net/dev 计算总收发速率（字节/秒）。
(double rxPerSec, double txPerSec) parseNetRate(
  Map<String, (int rx, int tx)> prev,
  Map<String, (int rx, int tx)> cur,
  double elapsedSeconds,
) {
  var rxDelta = 0;
  var txDelta = 0;
  for (final entry in cur.entries) {
    final p = prev[entry.key];
    if (p == null) continue;
    rxDelta += (entry.value.$1 - p.$1).clamp(0, 1 << 62);
    txDelta += (entry.value.$2 - p.$2).clamp(0, 1 << 62);
  }
  if (elapsedSeconds <= 0) return (0, 0);
  return (rxDelta / elapsedSeconds, txDelta / elapsedSeconds);
}

/// 解析 /proc/loadavg 的前三个负载值。
(double, double, double) parseLoadAvg(String text) {
  final parts = text.trim().split(RegExp(r'\s+'));
  double d(int i) => i < parts.length ? double.tryParse(parts[i]) ?? 0 : 0;
  return (d(0), d(1), d(2));
}

/// 解析 `ps -eo pid,args,%cpu,%mem` 输出为 TOP 进程列表。
///
/// args 为完整命令行（可含空格），从行尾反向匹配 %cpu/%mem 两个数字字段。
List<TopProcess> parsePsTop(String text) {
  final result = <TopProcess>[];
  final lines = text.trim().split('\n');
  final re = RegExp(r'^\s*(\d+)\s+(.*?)\s+([\d.]+)\s+([\d.]+)\s*$');
  for (var i = 1; i < lines.length; i++) {
    final m = re.firstMatch(lines[i]);
    if (m == null) continue;
    result.add(TopProcess(
      pid: int.tryParse(m.group(1)!) ?? 0,
      name: m.group(2)!.trim(),
      cpuPercent: double.tryParse(m.group(3)!) ?? 0,
      memPercent: double.tryParse(m.group(4)!) ?? 0,
    ));
  }
  return result;
}
