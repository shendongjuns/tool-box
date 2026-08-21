import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/features/monitor/monitor_models.dart';

void main() {
  group('parseCpuTicks / parseCpuUsage', () {
    test('两次 /proc/stat 差值计算 CPU 使用率', () {
      final prev = parseCpuTicks('cpu  100 0 100 800 0 0 0 0 0 0');
      final cur = parseCpuTicks('cpu  200 0 200 800 0 0 0 0 0 0');
      // 总增量 300，空闲不变（idle 800→800），使用 = (300-0)/300 = 100%
      expect(parseCpuUsage(prev, cur), closeTo(100, 0.01));
    });

    test('空闲增加时使用率降低', () {
      final prev = parseCpuTicks('cpu  100 0 100 800 0 0 0 0 0 0');
      final cur = parseCpuTicks('cpu  200 0 200 1000 0 0 0 0 0 0');
      // 总增量 400，idle 增 200 → 使用 200/400 = 50%
      expect(parseCpuUsage(prev, cur), closeTo(50, 0.01));
    });
  });

  group('parseMemInfo', () {
    test('解析 meminfo 关键字段', () {
      final mem = parseMemInfo('''
MemTotal:       16266216 kB
MemFree:         2030336 kB
MemAvailable:   9096316 kB
SwapTotal:       4194304 kB
SwapUsed:         123456 kB
''');
      expect(mem['MemTotal'], 16266216);
      expect(mem['MemAvailable'], 9096316);
      expect(mem['SwapUsed'], 123456);
    });
  });

  group('parseDf', () {
    test('解析 df -P 输出', () {
      final disks = parseDf('''
Filesystem 1024-blocks Used Available Capacity Mounted on
/dev/sda1       1024000 512000    512000 50% /
/dev/sda2      4096000 2048000   2048000 50% /home
''');
      expect(disks, hasLength(2));
      expect(disks[0].mount, '/');
      expect(disks[0].totalBytes, 1024000 * 1024);
      expect(disks[0].usedBytes, 512000 * 1024);
    });
  });

  group('parseNvidiaSmi', () {
    test('解析 nvidia-smi csv 输出（含功耗）', () {
      final gpus = parseNvidiaSmi(
        'NVIDIA GeForce RTX 3080, 45, 1234, 10240, 62, 250.5',
      );
      expect(gpus, hasLength(1));
      expect(gpus.single.name, 'NVIDIA GeForce RTX 3080');
      expect(gpus.single.utilPercent, 45);
      expect(gpus.single.memUsedMiB, 1234);
      expect(gpus.single.memTotalMiB, 10240);
      expect(gpus.single.tempC, 62);
      expect(gpus.single.powerWatts, 250.5);
    });

    test('无功耗字段时默认 0', () {
      final gpus = parseNvidiaSmi('GPU0, 10, 100, 1024, 40');
      expect(gpus.single.powerWatts, 0);
    });
  });

  group('parseNetDev / parseNetRate', () {
    test('两次 /proc/net/dev 差值计算速率', () {
      final prev = parseNetDev('''
eth0: 1000 0 0 0 0 0 0 0 2000 0 0 0 0 0 0 0
''');
      final cur = parseNetDev('''
eth0: 1500 0 0 0 0 0 0 0 3000 0 0 0 0 0 0 0
''');
      final (rx, tx) = parseNetRate(prev, cur, 1.0);
      expect(rx, 500);
      expect(tx, 1000);
    });
  });

  group('parseLoadAvg', () {
    test('解析负载', () {
      final (l1, l5, l15) = parseLoadAvg('1.02 0.80 0.60 1/345 1024');
      expect(l1, 1.02);
      expect(l5, 0.80);
      expect(l15, 0.60);
    });
  });

  group('parsePsTop', () {
    test('解析 ps -eo pid,args,%cpu,%mem 输出（完整命令含空格）', () {
      final procs = parsePsTop('''
  PID COMMAND                 %CPU %MEM
 1234 python3 train.py --epochs 10  25.5 2.1
  567 nginx: worker process    0.3 0.4
''');
      expect(procs, hasLength(2));
      expect(procs[0].pid, 1234);
      expect(procs[0].name, 'python3 train.py --epochs 10');
      expect(procs[0].cpuPercent, 25.5);
      expect(procs[0].memPercent, 2.1);
      expect(procs[1].name, 'nginx: worker process');
    });
  });

  group('parseNpuSmi', () {
    test('解析 npu-smi info 表格（310P 真实输出）', () {
      const text = '''
| npu-smi 25.0.rc1.1                     Version: 25.0.rc1.1 |
| NPU     Name                  | Health  | Power(W)  Temp(C)  Hugepages |
| Chip    Device                | Bus-Id  | AICore(%) Memory-Usage(MB) |
| 1       310P3                 | OK      | NA        44        605 / 605 |
| 0       0                     | 0000:01:00.0 | 0    3154 / 21527 |
| NPU     Chip                  | Process id | Process name | Process memory(MB) |
| 1       0                     | 3077486   | example_engine | 1358 |
''';
      final npus = parseNpuSmi(text);
      // 只解析出 1 个 NPU（进程表行被排除）。
      expect(npus, hasLength(1));
      expect(npus.single.name, '310P3');
      expect(npus.single.health, 'OK');
      expect(npus.single.aiCorePercent, 0);
      expect(npus.single.tempC, 44);
      expect(npus.single.powerWatts, 0); // NA
      expect(npus.single.hbmPercent, closeTo(3154 / 21527 * 100, 0.1));
    });
  });
}
