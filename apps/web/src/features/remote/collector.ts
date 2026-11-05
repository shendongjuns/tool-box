import type { MonitorMetrics, ServerInfo } from "@toolbox/contracts";
import { sshExec } from "@/lib/ssh";

/**
 * 通过 SSH 采集系统指标。
 *
 * 关键设计（继承 1.5.0 的经验）：
 * 1. **单条合并命令一次 SSH 往返** —— 用 `==XXX==` 分段标记。
 *    分成多次 exec 会在同一连接上创建大量 channel，部分服务器会拒绝或静默卡死。
 * 2. **CPU / 网络需要两次采样** —— 从 /proc 差值计算，首次只建基线。
 * 3. **进程命令读 /proc/<pid>/cmdline** —— ps 会截断长命令。
 * 4. GPU / NPU 可选 —— 命令不存在时静默跳过。
 */

/** 一次性查询服务器基本信息。 */
const INFO_COMMAND = [
  'echo "HOSTNAME=$(hostname 2>/dev/null)"',
  'echo "OS=$(. /etc/os-release 2>/dev/null && echo $PRETTY_NAME)"',
  'echo "KERNEL=$(uname -r 2>/dev/null)"',
  "echo \"CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)\"",
  'echo "CPU_CORES=$(grep -c ^processor /proc/cpuinfo 2>/dev/null)"',
  "echo \"MEM_TOTAL_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')\"",
  "echo \"IP=$(hostname -I 2>/dev/null | awk '{print $1}')\"",
].join("; ");

/** 单次采集全部指标。用 ==XXX== 分段，一次 SSH 往返拿完。 */
const METRICS_COMMAND = [
  // 每段独立执行，任一命令缺失（如非 Linux）也不影响后续分段
  "cat /proc/stat 2>/dev/null || true",
  "echo '==MEM=='",
  "cat /proc/meminfo 2>/dev/null || true",
  "echo '==DF=='",
  "df -P -B1 2>/dev/null || df -P 2>/dev/null || true",
  "echo '==NET=='",
  "cat /proc/net/dev 2>/dev/null || true",
  "echo '==UPTIME=='",
  "cat /proc/uptime 2>/dev/null || true",
  "echo '==LOAD=='",
  "cat /proc/loadavg 2>/dev/null || true",
  "echo '==NPROC=='",
  "nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || true",
  "echo '==PS=='",
  // 从 /proc/<pid>/cmdline 读完整命令行（ps 会截断），用 | 分隔字段
  "ps -eo pid,%cpu,%mem --sort=-%cpu 2>/dev/null | head -n 31 | tail -n +2 | while read pid cpu mem; do cmd=$(tr '\\0' ' ' < /proc/$pid/cmdline 2>/dev/null); [ -z \"$cmd\" ] && cmd='[kernel]'; echo \"$pid|$cmd|$cpu|$mem\"; done || true",
  "echo '==GPU=='",
  "nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw --format=csv,noheader,nounits 2>/dev/null || true",
  "echo '==NPU=='",
  "if command -v npu-smi >/dev/null 2>&1; then npu-smi info 2>/dev/null; fi; true",
].join("; ");

interface CpuBaseline {
  total: number;
  idle: number;
}

interface NetBaseline {
  rx: number;
  tx: number;
  at: number;
}

export class MonitorCollector {
  private prevCpu: CpuBaseline | null = null;
  private prevNet: NetBaseline | null = null;

  /** 上次失败原因（界面诊断用）。 */
  lastError: string | null = null;

  /** 采集服务器基本信息。 */
  async fetchServerInfo(sessionId: string): Promise<ServerInfo | null> {
    try {
      const raw = (await sshExec(sessionId, INFO_COMMAND, 10_000)) ?? "";
      const map = new Map<string, string>();
      for (const line of raw.split("\n")) {
        const eq = line.indexOf("=");
        if (eq <= 0) continue;
        map.set(line.slice(0, eq), line.slice(eq + 1).trim());
      }
      return {
        hostname: map.get("HOSTNAME") ?? "",
        os: map.get("OS") ?? "",
        kernel: map.get("KERNEL") ?? "",
        cpuModel: map.get("CPU_MODEL") ?? "",
        cpuCores: Number(map.get("CPU_CORES")) || 1,
        memTotalKb: Number(map.get("MEM_TOTAL_KB")) || 0,
        ip: map.get("IP") ?? "",
      };
    } catch {
      return null;
    }
  }

  /** 采集一次完整指标。首次调用只建立基线，返回 null。 */
  async collect(sessionId: string): Promise<MonitorMetrics | null> {
    if (this.prevCpu === null) {
      await this.collectOnce(sessionId);
      return null;
    }
    return this.collectOnce(sessionId);
  }

  private async collectOnce(sessionId: string): Promise<MonitorMetrics | null> {
    let raw: string;
    try {
      // 防御：IPC 在连接断开时可能返回 undefined，直接 split 会抛错
      raw = (await sshExec(sessionId, METRICS_COMMAND, 15_000)) ?? "";
      if (!raw.trim()) {
        this.lastError = "采集命令没有返回数据";
        return null;
      }
      this.lastError = null;
    } catch (error) {
      this.lastError = error instanceof Error ? error.message : String(error);
      return null;
    }

    const sections = splitSections(raw);
    const now = Date.now();

    // CPU
    const cpuLine = (sections.stat ?? "").split("\n")[0] ?? "";
    const cpu = parseCpu(cpuLine, this.prevCpu);
    this.prevCpu = cpu.baseline;

    // 内存
    const mem = parseMeminfo(sections.mem ?? "");

    // 磁盘
    const disks = parseDf(sections.df ?? "");

    // 网络
    const netNow = parseNetDev(sections.net ?? "");
    let rxRate = 0;
    let txRate = 0;
    if (this.prevNet && netNow && now > this.prevNet.at) {
      const secs = (now - this.prevNet.at) / 1000;
      rxRate = Math.max(0, (netNow.rx - this.prevNet.rx) / secs);
      txRate = Math.max(0, (netNow.tx - this.prevNet.tx) / secs);
    }
    if (netNow) this.prevNet = { ...netNow, at: now };

    /*
     * 系统运行时长。
     *
     * /proc/uptime 第一列是「自启动以来的秒数」（带小数）。
     * 拿不到就返回 null，界面上不显示 —— 而不是显示 0，
     * 那会让人误以为刚重启过。
     */
    const uptimeRaw = (sections.uptime ?? "").trim().split(/\s+/)[0] ?? "";
    const uptimeSeconds = Number.parseFloat(uptimeRaw);
    const uptime = Number.isFinite(uptimeSeconds) ? Math.floor(uptimeSeconds) : null;

    // 负载
    const load = (sections.load ?? "").trim().split(/\s+/);
    const load1 = Number(load[0]) || 0;
    const load5 = Number(load[1]) || 0;
    const load15 = Number(load[2]) || 0;

    // 核心数
    const cores = Number((sections.nproc ?? "").trim()) || 1;

    // 进程
    const processes = parseProcesses(sections.ps ?? "");

    // GPU
    const gpus = parseGpu(sections.gpu ?? "");

    // NPU
    const npus = parseNpu(sections.npu ?? "");

    return {
      timestamp: now,
      cpuPercent: cpu.percent,
      cpuCores: cores,
      memUsedBytes: mem.used,
      memTotalBytes: mem.total,
      swapUsedBytes: mem.swapUsed,
      swapTotalBytes: mem.swapTotal,
      disks,
      gpus,
      npus,
      netRxBytesPerSec: rxRate,
      netTxBytesPerSec: txRate,
      load1,
      load5,
      load15,
      uptimeSeconds: uptime,
      processes,
    };
  }
}

/** 按 `==XXX==` 标记切分命令输出。 */
function splitSections(raw: string): Record<string, string> {
  const out: Record<string, string> = {};
  if (typeof raw !== "string" || !raw) return out;
  let current = "stat";
  let buffer: string[] = [];

  for (const line of raw.split("\n")) {
    const match = /^==([A-Z]+)==$/.exec(line.trim());
    if (match) {
      out[current] = buffer.join("\n");
      current = match[1]!.toLowerCase();
      buffer = [];
      continue;
    }
    buffer.push(line);
  }
  out[current] = buffer.join("\n");
  return out;
}

function parseCpu(
  line: string,
  prev: CpuBaseline | null,
): { percent: number; baseline: CpuBaseline } {
  // cpu  user nice system idle iowait irq softirq steal ...
  const parts = line.trim().split(/\s+/).slice(1).map(Number);
  const idle = (parts[3] ?? 0) + (parts[4] ?? 0);
  const total = parts.reduce((sum, n) => sum + (Number.isFinite(n) ? n : 0), 0);
  const baseline = { total, idle };

  if (!prev || total <= prev.total) return { percent: 0, baseline };

  const totalDelta = total - prev.total;
  const idleDelta = idle - prev.idle;
  const percent = totalDelta > 0 ? ((totalDelta - idleDelta) / totalDelta) * 100 : 0;
  return { percent: Math.min(100, Math.max(0, percent)), baseline };
}

function parseMeminfo(raw: string): {
  total: number;
  used: number;
  swapTotal: number;
  swapUsed: number;
} {
  const map = new Map<string, number>();
  for (const line of raw.split("\n")) {
    const match = /^(\w+):\s+(\d+)/.exec(line);
    if (match) map.set(match[1]!, Number(match[2]) * 1024);
  }
  const total = map.get("MemTotal") ?? 0;
  const free = map.get("MemFree") ?? 0;
  const buffers = map.get("Buffers") ?? 0;
  const cached = map.get("Cached") ?? 0;
  const swapTotal = map.get("SwapTotal") ?? 0;
  const swapFree = map.get("SwapFree") ?? 0;

  return {
    total,
    used: Math.max(0, total - free - buffers - cached),
    swapTotal,
    swapUsed: Math.max(0, swapTotal - swapFree),
  };
}

function parseDf(raw: string): import("@toolbox/contracts").MonitorMetrics["disks"] {
  const out: import("@toolbox/contracts").MonitorMetrics["disks"] = [];
  const lines = raw.split("\n").slice(1);

  for (const line of lines) {
    const parts = line.trim().split(/\s+/);
    if (parts.length < 6) continue;
    const total = Number(parts[1]);
    const used = Number(parts[2]);
    // 挂载点可能含空格，取第 6 段之后拼接
    const mount = parts.slice(5).join(" ");
    if (!Number.isFinite(total) || total <= 0) continue;
    // 跳过内存盘与虚拟文件系统
    if (/^(tmpfs|devtmpfs|overlay|shm|udev)$/.test(parts[0] ?? "")) continue;
    out.push({ mount, totalBytes: total, usedBytes: used });
  }

  return out.slice(0, 8);
}

function parseNetDev(raw: string): { rx: number; tx: number } | null {
  let rx = 0;
  let tx = 0;
  let found = false;

  for (const line of raw.split("\n")) {
    const match = /^\s*(\w+):\s*(.+)$/.exec(line);
    if (!match) continue;
    const name = match[1]!;
    if (name === "lo") continue;
    const nums = match[2]!.trim().split(/\s+/).map(Number);
    if (nums.length < 9) continue;
    rx += nums[0] ?? 0;
    tx += nums[8] ?? 0;
    found = true;
  }

  return found ? { rx, tx } : null;
}

function parseProcesses(raw: string): {
  pid: number;
  name: string;
  cpuPercent: number;
  memPercent: number;
}[] {
  const out: { pid: number; name: string; cpuPercent: number; memPercent: number }[] = [];

  for (const line of raw.split("\n")) {
    const parts = line.split("|");
    if (parts.length < 4) continue;
    const pid = Number(parts[0]);
    const cpu = Number(parts[parts.length - 2]);
    const mem = Number(parts[parts.length - 1]);
    const name = parts.slice(1, -2).join("|").trim();
    if (!Number.isFinite(pid) || !name) continue;
    out.push({ pid, name, cpuPercent: cpu, memPercent: mem });
    if (out.length >= 12) break;
  }

  return out;
}

function parseGpu(raw: string): {
  index: number;
  name: string;
  utilPercent: number;
  memUsedMiB: number;
  memTotalMiB: number;
  tempC: number;
  powerWatts: number;
}[] {
  const out: {
    index: number;
    name: string;
    utilPercent: number;
    memUsedMiB: number;
    memTotalMiB: number;
    tempC: number;
    powerWatts: number;
  }[] = [];

  for (const line of raw.split("\n")) {
    const parts = line.split(",").map((s) => s.trim());
    if (parts.length < 7) continue;
    out.push({
      index: Number(parts[0]) || 0,
      name: parts[1] ?? "",
      utilPercent: Number(parts[2]) || 0,
      memUsedMiB: Number(parts[3]) || 0,
      memTotalMiB: Number(parts[4]) || 0,
      tempC: Number(parts[5]) || 0,
      powerWatts: Number(parts[6]) || 0,
    });
  }

  return out;
}

/**
 * 解析 `npu-smi info` 输出（华为昇腾）。
 *
 * 移植自 1.5.0 的 parseNpuSmi —— 输出是**两行一组**的表格：
 *
 *   | NPU     Name      | Health | Power(W) Temp(C) HugePages-Usage(page) |
 *   | 0       910B3     | OK     | 90.4     48      0 / 0                 |
 *   | Chip    | Bus-Id        | AICore(%) Memory-Usage(MB) HBM-Usage(MB) |
 *   | 0       | 0000:C1:00.0  | 0       0 / 0            3154 / 21527    |
 *
 * 关键点：
 * - **NPU 行**给 Health / Power / Temp，**Chip 行**给 AICore / Memory
 * - 必须先缓存 NPU 行，等 Chip 行到达再合并成一条记录
 * - 用列特征区分「NPU 行 / Chip 行 / 进程表行」，不能只靠正则匹配数字
 * - 部分机型（如 310P）的 `-t` 查询受限，所以采集用默认 info 表格
 */
export function parseNpu(raw: string): {
  index: number;
  name: string;
  aiCorePercent: number;
  hbmPercent: number;
  powerWatts: number;
  tempC: number;
  health: string;
}[] {
  type Npu = {
    index: number;
    name: string;
    aiCorePercent: number;
    hbmPercent: number;
    powerWatts: number;
    tempC: number;
    health: string;
  };

  const result: Npu[] = [];
  if (typeof raw !== "string" || !raw.trim()) return result;

  /** 按 | 切列并 trim */
  const cells = (line: string) => line.split("|").map((part) => part.trim());

  let curName: string | null = null;
  let curHealth = "";
  let curPower = 0;
  let curTemp = 0;
  let curAicore = 0;
  /** Chip 行的 Memory-Usage，形如 "3154 / 21527" */
  let curMemory = "";

  const flush = () => {
    if (curName === null) return;

    // Memory-Usage 可能是 "3154 / 21527" 或 "0 / 0"
    const memParts = curMemory.split("/").map((part) => part.trim());
    const memUsed = Number.parseFloat(memParts[0] ?? "") || 0;
    const memTotal = Number.parseFloat(memParts[1] ?? "") || 0;

    result.push({
      index: result.length,
      name: curName,
      aiCorePercent: curAicore,
      // HBM 使用率 = 已用 / 总量 × 100
      hbmPercent: memTotal > 0 ? (memUsed / memTotal) * 100 : 0,
      powerWatts: curPower,
      tempC: curTemp,
      health: curHealth,
    });

    curName = null;
    curHealth = "";
    curPower = 0;
    curTemp = 0;
    curAicore = 0;
    curMemory = "";
  };

  for (const line of raw.split("\n")) {
    const c = cells(line);
    // 至少要有 4 列（行首空 + 3 个内容列）
    if (c.length < 4) continue;

    const c1First = (c[1] ?? "").split(/\s+/)[0] ?? "";
    const isNumeric = /^\d+$/.test(c1First);

    // 进程表行：c[2] 是纯数字 PID，c[3] 是进程名（非数值）
    const c2IsPid = /^\d+$/.test(c[2] ?? "");
    const c3First = (c[3] ?? "").split(/\s+/)[0] ?? "";
    // 注意：Power 可能是小数（如 90.4），所以要允许小数点
    const c3IsValue = /^\d+(\.\d+)?$/.test(c3First) || c3First === "NA";

    // ---- NPU 行 ----
    // c[1] 首段是数字，c[2] 是 Health（非 PID、非 Bus-Id），c[3] 是 Power/Temp
    if (
      isNumeric &&
      !c2IsPid &&
      !(c[2] ?? "").startsWith("NPU") &&
      !(c[2] ?? "").startsWith("Chip") &&
      !(c[2] ?? "").includes(":") &&
      !(c[2] ?? "").includes(".") &&
      c3IsValue
    ) {
      flush();
      const c1Parts = (c[1] ?? "").split(/\s+/);
      curName = c1Parts.length > 1 ? (c1Parts[1] ?? `NPU ${c1First}`) : `NPU ${c1First}`;
      curHealth = c[2] ?? "";

      // c[3] 形如 "90.4  48  0 / 0"（Power / Temp / HugePages）
      const p3 = (c[3] ?? "").split(/\s+/).filter(Boolean);
      curPower = Number.parseFloat(p3[0] ?? "") || 0;
      curTemp = Number.parseFloat(p3[1] ?? "") || 0;
      continue;
    }

    // ---- Chip 行 ----
    // c[1] 首段是数字，c[2] 是 Bus-Id（含冒号或点）
    if (isNumeric && ((c[2] ?? "").includes(":") || (c[2] ?? "").includes("."))) {
      /*
       * c[3] 的实际形态因机型而异，常见两种：
       *   "0  3154 / 21527"                    （只有 HBM）
       *   "0  0 / 0  3154 / 21527"             （HugePages + HBM）
       * 前者直接取剩余部分，后者要取**最后一组** a/b。
       */
      const p3 = (c[3] ?? "").split(/\s+/).filter(Boolean);
      curAicore = Number.parseFloat(p3[0] ?? "") || 0;

      // 从剩余 token 里找所有 "数字 / 数字" 组合，取最后一组作为 HBM
      const rest = p3.slice(1);
      const pairs: string[] = [];
      for (let i = 0; i + 2 < rest.length + 1; i += 1) {
        if (rest[i + 1] === "/" && rest[i] !== undefined && rest[i + 2] !== undefined) {
          pairs.push(`${rest[i]} / ${rest[i + 2]}`);
          i += 2;
        }
      }
      curMemory = pairs.length > 0 ? (pairs[pairs.length - 1] ?? "") : "";
    }
  }

  flush();
  return result;
}
/** 仅供单元测试使用。 */
export const parseNpuForTest = parseNpu;
