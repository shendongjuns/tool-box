import { beforeEach, describe, expect, it } from "vitest";
import { useTransfers, type TransferTask } from "./transfer-store";

/**
 * 传输任务 store。
 *
 * 关键行为：
 * - 新任务插到最前，总数上限 50（避免 localStorage 无限膨胀）
 * - 「清空已完成」保留进行中的任务
 * - 应用启动时把上次残留的「进行中」标记为中断
 *   （否则重启后会看到永远卡在某个百分比的幽灵任务）
 */

function makeTask(overrides: Partial<TransferTask> = {}): TransferTask {
  return {
    id: "t1",
    name: "file.zip",
    direction: "download",
    remoteDir: "/home/user",
    localPath: "C:/Downloads/file.zip",
    transferred: 0,
    total: 100,
    percent: 0,
    status: "running",
    createdAt: 1_700_000_000_000,
    ...overrides,
  };
}

describe("transfer-store", () => {
  beforeEach(() => {
    useTransfers.setState({ tasks: [] });
  });

  it("新任务插入到最前", () => {
    useTransfers.getState().add(makeTask({ id: "a" }));
    useTransfers.getState().add(makeTask({ id: "b" }));
    expect(useTransfers.getState().tasks.map((t) => t.id)).toEqual(["b", "a"]);
  });

  it("任务数上限 50", () => {
    for (let i = 0; i < 60; i += 1) {
      useTransfers.getState().add(makeTask({ id: `t${i}` }));
    }
    expect(useTransfers.getState().tasks).toHaveLength(50);
  });

  it("patch 只更新目标任务", () => {
    useTransfers.getState().add(makeTask({ id: "a" }));
    useTransfers.getState().add(makeTask({ id: "b" }));
    useTransfers.getState().patch("a", { percent: 50, status: "done" });

    const a = useTransfers.getState().tasks.find((t) => t.id === "a");
    const b = useTransfers.getState().tasks.find((t) => t.id === "b");
    expect(a?.percent).toBe(50);
    expect(a?.status).toBe("done");
    expect(b?.percent).toBe(0);
  });

  it("清空已完成后保留进行中任务", () => {
    useTransfers.getState().add(makeTask({ id: "done", status: "done" }));
    useTransfers.getState().add(makeTask({ id: "running", status: "running" }));
    useTransfers.getState().add(makeTask({ id: "failed", status: "failed" }));

    useTransfers.getState().clearFinished();
    expect(useTransfers.getState().tasks.map((t) => t.id)).toEqual(["running"]);
  });

  it("应用重启后把 running 标记为中断", () => {
    useTransfers.getState().add(makeTask({ id: "a", status: "running" }));
    useTransfers.getState().add(makeTask({ id: "b", status: "done" }));

    useTransfers.getState().markInterrupted();

    const a = useTransfers.getState().tasks.find((t) => t.id === "a");
    const b = useTransfers.getState().tasks.find((t) => t.id === "b");
    expect(a?.status).toBe("failed");
    expect(a?.error).toContain("重启");
    // 已完成的不能被误伤
    expect(b?.status).toBe("done");
  });

  it("remove 按 id 删除", () => {
    useTransfers.getState().add(makeTask({ id: "a" }));
    useTransfers.getState().add(makeTask({ id: "b" }));
    useTransfers.getState().remove("a");
    expect(useTransfers.getState().tasks.map((t) => t.id)).toEqual(["b"]);
  });
});
