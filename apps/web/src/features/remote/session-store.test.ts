import { describe, expect, it } from "vitest";
import { nextLabel } from "./session-store";

/**
 * 会话标签去重。
 *
 * 同一台服务器多次打开时依次变成「名称（1）」「名称（2）」，
 * 关闭中间某个后应复用第一个空出的序号。
 */
describe("nextLabel", () => {
  it("首次使用原名", () => {
    expect(nextLabel("生产环境", [])).toBe("生产环境");
  });

  it("重名时依次递增", () => {
    expect(nextLabel("生产环境", ["生产环境"])).toBe("生产环境（1）");
    expect(nextLabel("生产环境", ["生产环境", "生产环境（1）"])).toBe("生产环境（2）");
    expect(nextLabel("生产环境", ["生产环境", "生产环境（1）", "生产环境（2）"])).toBe(
      "生产环境（3）",
    );
  });

  it("中间序号空出时应复用", () => {
    // 关掉（1）后再次打开，应复用（1）而不是跳到（3）
    expect(nextLabel("生产环境", ["生产环境", "生产环境（2）"])).toBe("生产环境（1）");
  });

  it("空名称退化为「未命名」", () => {
    expect(nextLabel("", [])).toBe("未命名");
    expect(nextLabel("   ", [])).toBe("未命名");
  });

  it("不同名称互不影响", () => {
    expect(nextLabel("测试机", ["生产环境", "生产环境（1）"])).toBe("测试机");
  });
});
