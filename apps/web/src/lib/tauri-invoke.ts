/**
 * Tauri invoke 的共享注册表。
 *
 * 单独抽出来是为了打断循环依赖：
 *   desktop.ts  ->  api-context.tsx  (setTauriInvoke)
 *   api-context.tsx  ->  desktop.ts  (authHeaderFor / getLocalBaseUrl)
 *
 * 两边都同时被静态和动态导入，Rollup 会提示「动态导入无法拆包」。
 * 把这只读变量放进独立模块后，两边都变成对它的单向依赖。
 */

export type TauriInvoke = <T>(command: string, args?: Record<string, unknown>) => Promise<T>;

let invokeRef: TauriInvoke | null = null;

export function setTauriInvoke(fn: TauriInvoke | null): void {
  invokeRef = fn;
}

export function getTauriInvoke(): TauriInvoke | null {
  return invokeRef;
}
