/**
 * 测试环境的最小 localStorage 桩。
 *
 * zustand 的 persist 中间件在模块加载时会访问 localStorage。
 * node 环境没有它，会打出 "storage is currently unavailable" 警告 ——
 * 不影响断言，但会淹没真实输出。这里提供一个内存实现。
 */

const store = new Map<string, string>();

const localStorageStub: Storage = {
  get length() {
    return store.size;
  },
  clear: () => store.clear(),
  getItem: (key) => store.get(key) ?? null,
  key: (index) => [...store.keys()][index] ?? null,
  removeItem: (key) => {
    store.delete(key);
  },
  setItem: (key, value) => {
    store.set(key, value);
  },
};

if (typeof globalThis.localStorage === "undefined") {
  Object.defineProperty(globalThis, "localStorage", {
    value: localStorageStub,
    configurable: true,
  });
}

if (typeof globalThis.window === "undefined") {
  // 部分模块会在导入期检查 window
  Object.defineProperty(globalThis, "window", {
    value: globalThis,
    configurable: true,
  });
}
