import { describe, expect, it } from "vitest";
import { parseNpuForTest } from "./collector";

/**
 * npu-smi info 解析测试。
 *
 * 输出是**两行一组**：NPU 行给 Health/Power/Temp，Chip 行给 AICore/Memory。
 * 之前的实现用单行正则，完全解析不出来；移植 1.5.0 逻辑后又发现
 * 两个上游 bug（Power 是小数、HBM 要取最后一组 a/b），这里全部固化。
 */

const SAMPLE_910B = `
+------------------------------------------------------------------------------------------------+
| npu-smi 23.0.3                   Version: 23.0.3                                               |
+---------------------------+---------------+----------------------------------------------------+
| NPU   Name                | Health        | Power(W)    Temp(C)           Hugepages-Usage(page)|
| Chip                      | Bus-Id        | AICore(%)   Memory-Usage(MB)  HBM-Usage(MB)        |
+===========================+===============+====================================================+
| 0     910B3               | OK            | 90.4        48                0    / 0             |
| 0                         | 0000:C1:00.0  | 0           0 / 0             3154 / 21527        |
+===========================+===============+====================================================+
| 1     910B3               | OK            | 88.1        46                0    / 0             |
| 0                         | 0000:C2:00.0  | 12          1024 / 0          21527 / 65536       |
+===========================+===============+====================================================+
`;

describe("parseNpu", () => {
  it("从两行合并出完整记录", () => {
    const result = parseNpuForTest(SAMPLE_910B);
    expect(result).toHaveLength(2);

    expect(result[0]!.name).toBe("910B3");
    expect(result[0]!.health).toBe("OK");
    // Power 是小数，早期实现用整数判断会把这行整个漏掉
    expect(result[0]!.powerWatts).toBeCloseTo(90.4, 1);
    expect(result[0]!.tempC).toBe(48);
    expect(result[0]!.aiCorePercent).toBe(0);
    // HBM 必须取最后一组 a/b（前面那组是 HugePages）
    expect(result[0]!.hbmPercent).toBeCloseTo((3154 / 21527) * 100, 1);

    expect(result[1]!.aiCorePercent).toBe(12);
    expect(result[1]!.hbmPercent).toBeCloseTo((21527 / 65536) * 100, 1);
  });

  it("空输入与无关输出返回空数组", () => {
    expect(parseNpuForTest("")).toEqual([]);
    expect(parseNpuForTest("command not found")).toEqual([]);
    expect(parseNpuForTest("| a | b |")).toEqual([]);
  });

  it("只有 NPU 行没有 Chip 行时，HBM 为 0 但记录仍存在", () => {
    const onlyNpu = `| 0     910B3  | OK | 90.4  48  0 / 0 |`;
    const result = parseNpuForTest(onlyNpu);
    expect(result).toHaveLength(1);
    expect(result[0]!.hbmPercent).toBe(0);
    expect(result[0]!.powerWatts).toBeCloseTo(90.4, 1);
  });
});
