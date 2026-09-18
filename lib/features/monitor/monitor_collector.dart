import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:toolbox/common/app_log.dart';
import 'package:toolbox/features/monitor/monitor_models.dart';

/// 通过 SSH 采集远程系统指标。
///
/// 采集采用**单条合并命令一次 SSH 往返**（分段标记分隔），避免多次
/// execute 在同一连接上创建大量并发 channel 导致服务器拒绝/卡住，
/// 从而出现"无数据且无报错"的静默失败。
class MonitorCollector {
  MonitorCollector(this._client);

  final SSHClient _client;

  List<int>? _prevCpuTicks;
  Map<String, (int rx, int tx)>? _prevNet;
  DateTime? _prevTime;

  /// 最近一次采集失败的原因（界面展示诊断）。
  String? lastError;

  /// 服务器基本信息（一次性查询）。
  static const _infoCommand = 'echo "HOST=\$(hostname)"; '
      'echo "OS=\$(. /etc/os-release 2>/dev/null && echo \$PRETTY_NAME)"; '
      'echo "KERNEL=\$(uname -r)"; '
      'echo "CPU_MODEL=\$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)"; '
      'echo "CPU_CORES=\$(grep -c ^processor /proc/cpuinfo 2>/dev/null)"; '
      'echo "MEM_TOTAL=\$(grep MemTotal /proc/meminfo | awk \'{print \$2}\')"; '
      'echo "DISK_TOTAL=\$(df -P --total 2>/dev/null | tail -1 | awk \'{print \$2}\')"; '
      'echo "IP=\$(hostname -I 2>/dev/null | awk \'{print \$1}\')"';

  /// 采集服务器基本信息；失败返回 null。
  Future<Map<String, String>?> fetchServerInfo() async {
    SSHSession? session;
    try {
      session = await _client.execute(_infoCommand).timeout(
            const Duration(seconds: 10),
          );
      final sb = StringBuffer();
      await session.stdout
          .map((bytes) => sb.write(utf8.decode(bytes, allowMalformed: true)))
          .drain<void>()
          .timeout(const Duration(seconds: 10));
      final info = <String, String>{};
      for (final line in sb.toString().split('\n')) {
        final eq = line.indexOf('=');
        if (eq <= 0) continue;
        info[line.substring(0, eq)] = line.substring(eq + 1).trim();
      }
      return info;
    } catch (_) {
      // 超时/失败时关闭 exec channel，避免每秒采集持续泄漏。
      _closeQuietly(session);
      return null;
    }
  }

  /// 一次执行全部采集命令，输出用 `==XXX==` 标记分段。
  ///
  /// PS 段从 /proc/`pid`/cmdline 读完整命令行（不受 ps 截断影响），
  /// 输出格式：pid 完整命令 cpu mem。整体用单引号 Dart 字符串避免插值。
  static const _command = 'cat /proc/stat; '
      "echo '==MEM=='; cat /proc/meminfo; "
      "echo '==DF=='; df -P; "
      "echo '==NET=='; cat /proc/net/dev; "
      "echo '==LOAD=='; cat /proc/loadavg; "
      "echo '==NPROC=='; nproc; "
      "echo '==PS=='; ps -eo pid,%cpu,%mem --sort=-%cpu | head -n 30 | "
      'while read pid cpu mem; do '
      "cmd=\"\$(tr '\\0' ' ' < /proc/\$pid/cmdline 2>/dev/null)\"; "
      'if [ -z "\$cmd" ]; then cmd="[kernel]"; fi; '
      'echo "\$pid \$cmd \$cpu \$mem"; '
      'done; '
      "echo '==GPU=='; nvidia-smi --query-gpu=name,utilization.gpu,memory.used,"
      'memory.total,temperature.gpu,power.draw --format=csv,noheader,nounits 2>/dev/null; '
      // 华为昇腾 NPU：探测 npu-smi 存在则采集默认 info 表格
      // （部分机型如 310P 的 -t 查询受限，默认表格最通用）。
      "echo '==NPU=='; if command -v npu-smi >/dev/null 2>&1; then "
      'npu-smi info 2>/dev/null; fi';

  static final _sectionRe = RegExp(
    r'^==(?:MEM|DF|NET|LOAD|NPROC|PS|GPU|NPU)==$',
    multiLine: true,
  );

  /// 采集一次完整指标。
  ///
  /// 首次调用先执行一次建立 CPU/网络基线（不产出数据），第二次起才有
  /// 真实 CPU/网络值。
  Future<MonitorMetrics> collect() async {
    if (_prevCpuTicks == null) {
      await _collectOnce();
    }
    return _collectOnce();
  }

  Future<MonitorMetrics> _collectOnce() async {
    final now = DateTime.now();
    final elapsed = _prevTime == null
        ? 0.0
        : now.difference(_prevTime!).inMilliseconds / 1000.0;

    final text = await _readAll();
    // 分段：[0]=stat（首个标记前）, [1]=MEM, [2]=DF, [3]=NET, [4]=LOAD, [5]=PS, [6]=GPU
    final parts = text?.split(_sectionRe);
    String? part(int i) {
      if (parts == null || i >= parts.length) return null;
      final v = parts[i].trim();
      return v.isEmpty ? null : v;
    }

    final statText = part(0);
    final memText = part(1);
    final dfText = part(2);
    final netText = part(3);
    final loadText = part(4);
    final psText = part(6);
    final gpuText = part(7);

    // 华为昇腾 NPU：默认 info 表格交给解析器。
    final npuText = part(8);
    final npus = parseNpuSmi(npuText ?? '');

    // CPU 核心数。
    final cpuCores = int.tryParse(part(5)?.trim() ?? '') ?? 1;

    // CPU 使用率（两次 /proc/stat 差值）。
    var cpuPercent = 0.0;
    if (statText != null) {
      for (final line in statText.split('\n')) {
        if (line.startsWith('cpu') && !line.startsWith('cpu ')) {
          final curTicks = parseCpuTicks(line);
          final prev = _prevCpuTicks;
          if (prev != null) {
            cpuPercent = parseCpuUsage(prev, curTicks);
          }
          _prevCpuTicks = curTicks;
          break;
        }
      }
    }

    // 内存 / 交换。
    final mem = parseMemInfo(memText ?? '');
    final memTotal = (mem['MemTotal'] ?? 0) * 1024;
    final memAvailable = (mem['MemAvailable'] ?? mem['MemFree'] ?? 0) * 1024;
    final memUsed = (memTotal - memAvailable).clamp(0, memTotal);
    final swapTotal = (mem['SwapTotal'] ?? 0) * 1024;
    final swapUsed = (mem['SwapUsed'] ?? 0) * 1024;

    // 磁盘。
    final disks = parseDf(dfText ?? '');

    // 网络速率（两次 /proc/net/dev 差值）。
    var rxPerSec = 0.0;
    var txPerSec = 0.0;
    final curNet = parseNetDev(netText ?? '');
    final prevNet = _prevNet;
    if (prevNet != null && elapsed > 0) {
      (rxPerSec, txPerSec) = parseNetRate(prevNet, curNet, elapsed);
    }
    _prevNet = curNet;
    _prevTime = now;

    // 负载。
    final (load1, load5, load15) = parseLoadAvg(loadText ?? '');

    // TOP 进程。
    final processes = parsePsTop(psText ?? '');

    // GPU（命令缺失/失败则为空，不报错）。
    final gpus = parseNvidiaSmi(gpuText ?? '');

    return MonitorMetrics(
      timestamp: now,
      cpuPercent: cpuPercent,
      memUsedBytes: memUsed,
      memTotalBytes: memTotal,
      swapUsedBytes: swapUsed,
      swapTotalBytes: swapTotal,
      disks: disks,
      gpus: gpus,
      npus: npus,
      netRxBytesPerSec: rxPerSec,
      netTxBytesPerSec: txPerSec,
      load1: load1,
      load5: load5,
      load15: load15,
      processes: processes,
      cpuCores: cpuCores,
    );
  }

  /// 执行合并命令并读取 stdout（UTF-8 容错）；超时/失败返回 null。
  Future<String?> _readAll() async {
    SSHSession? session;
    try {
      session = await _client.execute(_command).timeout(
            const Duration(seconds: 15),
          );
      final sb = StringBuffer();
      await session.stdout
          .map((bytes) => sb.write(utf8.decode(bytes, allowMalformed: true)))
          .drain<void>()
          .timeout(const Duration(seconds: 15));
      return sb.toString();
    } catch (e) {
      lastError = '采集命令执行失败：$e';
      AppLog.w('monitor', '采集失败：$e');
      // 超时/失败时关闭 exec channel：否则服务器假死时每秒新建一条
      // 且永不关闭，最终被服务器拒绝会话。
      _closeQuietly(session);
      return null;
    }
  }

  void _closeQuietly(SSHSession? session) {
    try {
      session?.close();
    } catch (_) {}
  }
}
