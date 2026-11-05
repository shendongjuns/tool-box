import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  dropMonitor,
  isActivated,
  isMonitoring,
  markActivated,
  startMonitor,
} from "./monitor-store";

/**
 * 监控采集引擎的行为验证。
 *
 * 三条规则：
 * 1. 新会话不自动采集（用户可能只想用终端）
 * 2. 打开过监控页之后才标记为已激活
 * 3. 一旦激活就持续采集，直到会话关闭
 */

describe("激活标记", () => {
  it("新会话默认未激活", () => {
    expect(isActivated("session-new")).toBe(false);
  });

  it("标记后变为已激活", () => {
    markActivated("session-a");
    expect(isActivated("session-a")).toBe(true);
  });

  it("不同会话互不影响", () => {
    markActivated("session-x");
    expect(isActivated("session-x")).toBe(true);
    expect(isActivated("session-y")).toBe(false);
  });

  it("dropMonitor 会清掉激活标记", () => {
    markActivated("session-z");
    expect(isActivated("session-z")).toBe(true);

    dropMonitor("session-z");

    // 重新连接同一服务器时应重新判断，而不是立刻开始采集
    expect(isActivated("session-z")).toBe(false);
  });
});

describe("采集引擎", () => {
  let collectCount = 0;
  const collect = async () => {
    collectCount += 1;
  };

  beforeEach(() => {
    vi.useFakeTimers();
    collectCount = 0;
  });

  afterEach(() => {
    dropMonitor("engine-test");
    vi.useRealTimers();
  });

  it("启动后按间隔持续采集", async () => {
    startMonitor("engine-test", 1000, collect);

    await vi.advanceTimersByTimeAsync(1100);
    expect(collectCount).toBe(1);

    await vi.advanceTimersByTimeAsync(1000);
    expect(collectCount).toBe(2);

    await vi.advanceTimersByTimeAsync(2000);
    expect(collectCount).toBe(4);
  });

  it("间隔为 0 时不采集", async () => {
    startMonitor("engine-test", 0, collect);
    await vi.advanceTimersByTimeAsync(5000);
    expect(collectCount).toBe(0);
  });

  it("重复调用 startMonitor 不会产生第二个定时器", async () => {
    startMonitor("engine-test", 1000, collect);
    startMonitor("engine-test", 1000, collect);
    startMonitor("engine-test", 1000, collect);

    await vi.advanceTimersByTimeAsync(1100);
    // 如果产生了多个定时器，这里会是 3
    expect(collectCount).toBe(1);
  });

  it("切换间隔后按新间隔采集", async () => {
    startMonitor("engine-test", 1000, collect);
    await vi.advanceTimersByTimeAsync(1100);
    expect(collectCount).toBe(1);

    startMonitor("engine-test", 3000, collect);
    await vi.advanceTimersByTimeAsync(1100);
    // 还没到 3 秒
    expect(collectCount).toBe(1);

    await vi.advanceTimersByTimeAsync(2000);
    expect(collectCount).toBe(2);
  });

  it("dropMonitor 之后彻底停止", async () => {
    startMonitor("engine-test", 1000, collect);
    await vi.advanceTimersByTimeAsync(1100);
    const before = collectCount;

    dropMonitor("engine-test");
    expect(isMonitoring("engine-test")).toBe(false);

    await vi.advanceTimersByTimeAsync(5000);
    expect(collectCount).toBe(before);
  });

  it("采集抛错不中断循环", async () => {
    let calls = 0;
    const flaky = async () => {
      calls += 1;
      throw new Error("网络抖动");
    };

    startMonitor("engine-test", 1000, flaky);
    await vi.advanceTimersByTimeAsync(3100);

    // 抛错后仍应继续排下一次
    expect(calls).toBeGreaterThanOrEqual(3);
  });

  it("isMonitoring 反映真实状态", () => {
    expect(isMonitoring("engine-test")).toBe(false);

    startMonitor("engine-test", 1000, collect);
    expect(isMonitoring("engine-test")).toBe(true);

    dropMonitor("engine-test");
    expect(isMonitoring("engine-test")).toBe(false);
  });
});
