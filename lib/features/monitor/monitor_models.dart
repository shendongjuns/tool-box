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

/// 解析 /proc/net/dev 为接口 -> {rx,tx} 字节的映射（跳过 lo）。
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
