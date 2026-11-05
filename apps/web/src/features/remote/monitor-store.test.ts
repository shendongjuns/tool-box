import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  dropMonitor,
  isActivated,
  isMonitoring,
  markActivated,
  pauseMonitor,
  readBackgroundCollection,
  resumeMonitor,
  saveBackgroundCollection,
  startMonitor,
} from "./monitor-store";

/**
 * 后台采集开关与激活标记的行为验证。
 *
 * 核心约束：
 * - 新会话不自动采集（用户可能只用终端）
 * - 打开过监控页之后才标记为已激活
 * - 切走后是否继续采集，由开关决定
 */

describe("后台采集开关", () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it("默认开启", () => {
    expect(readBackgroundCollection()).toBe(true);
  });

  it("能保存关闭状态", () => {
    saveBackgroundCollection(false);
    expect(readBackgroundCollection()).toBe(false);
  });

  it("能保存开启状态", () => {
    saveBackgroundCollection(true);
    expect(readBackgroundCollection()).toBe(true);
  });

  it("空字符串视为默认开启", () => {
    window.localStorage.setItem("toolbox.monitor.background", "");
    expect(readBackgroundCollection()).toBe(true);
  });
});

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

    // 重新连接同一个服务器时应该重新判断 —— 否则会立刻开始采集
    expect(isActivated("session-z")).toBe(false);
  });
});

describe("开关与 active 的协同", () => {
  let collectCount = 0;
  const collect = async () => {
    collectCount += 1;
  };

  beforeEach(() => {
    vi.useFakeTimers();
    collectCount = 0;
    window.localStorage.clear();
  });

  afterEach(() => {
    dropMonitor("combo-test");
    vi.useRealTimers();
  });

  it("关闭开关时若仍在监控页，采集必须继续", async () => {
    /*
     * 这是用户明确提出的规则：
     * 开关只决定「切走之后」是否继续，不影响眼下的采集。
     *
     * 模拟：正在看监控页，把开关从开拨到关
     * 期望：采集不中断
     */
    startMonitor("combo-test", 1000, collect);
    await vi.advanceTimersByTimeAsync(1100);
    const before = collectCount;
    expect(before).toBeGreaterThan(0);

    saveBackgroundCollection(false);
    // 关键：不调用 pauseMonitor —— 因为还在监控页

    await vi.advanceTimersByTimeAsync(3000);
    expect(collectCount).toBeGreaterThan(before);
  });

  it("关闭开关后切走，采集才暂停", async () => {
    startMonitor("combo-test", 1000, collect);
    await vi.advanceTimersByTimeAsync(1100);
    const running = collectCount;

    saveBackgroundCollection(false);
    // 切走 -> 触发暂停
    pauseMonitor("combo-test");

    await vi.advanceTimersByTimeAsync(5000);
    expect(collectCount).toBe(running);
  });

  it("切回监控页时恢复采集，不受开关影响", async () => {
    startMonitor("combo-test", 1000, collect);
    await vi.advanceTimersByTimeAsync(1100);
    pauseMonitor("combo-test");
    const paused = collectCount;

    // 即使开关是关的，切回来也要继续采
    saveBackgroundCollection(false);
    resumeMonitor("combo-test");

    await vi.advanceTimersByTimeAsync(1100);
    expect(collectCount).toBeGreaterThan(paused);
  });

  it("开口时立即恢复被暂停的采集", async () => {
    startMonitor("combo-test", 1000, collect);
    await vi.advanceTimersByTimeAsync(1100);
    pauseMonitor("combo-test");
    const paused = collectCount;

    saveBackgroundCollection(true);
    resumeMonitor("combo-test");

    await vi.advanceTimersByTimeAsync(1100);
    expect(collectCount).toBeGreaterThan(paused);
  });
});

describe("采集引擎的暂停与恢复", () => {
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

  it("暂停后不再采集", async () => {
    startMonitor("engine-test", 1000, collect);
    await vi.advanceTimersByTimeAsync(1100);
    const afterFirst = collectCount;
    expect(afterFirst).toBeGreaterThan(0);

    pauseMonitor("engine-test");
    await vi.advanceTimersByTimeAsync(5000);

    expect(collectCount).toBe(afterFirst);
  });

  it("恢复后继续采集", async () => {
    startMonitor("engine-test", 1000, collect);
    await vi.advanceTimersByTimeAsync(1100);
    pauseMonitor("engine-test");

    const paused = collectCount;
    resumeMonitor("engine-test");
    await vi.advanceTimersByTimeAsync(1100);

    expect(collectCount).toBeGreaterThan(paused);
  });

  it("暂停不丢数据，isMonitoring 仍为 true", () => {
    startMonitor("engine-test", 1000, collect);
    pauseMonitor("engine-test");
    // 引擎还在，只是定时器停了 —— 与 dropMonitor 不同
    expect(isMonitoring("engine-test")).toBe(true);
  });

  it("dropMonitor 之后彻底停止", () => {
    startMonitor("engine-test", 1000, collect);
    dropMonitor("engine-test");
    expect(isMonitoring("engine-test")).toBe(false);
  });
});
