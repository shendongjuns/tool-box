import * as React from "react";
import { hideToTray, listenCloseRequest } from "@/lib/desktop-close";
import { isDesktop } from "@/lib/platform";

/**
 * 关闭窗口即隐藏到托盘。
 *
 * Rust 侧拦截了 CloseRequested 并发 `app://close-requested`；
 * 这里直接隐藏窗口，不做任何询问。退出请用托盘菜单。
 */
export function TrayGuard() {
  React.useEffect(() => {
    if (!isDesktop()) return;

    let dispose: (() => void) | undefined;
    void listenCloseRequest(() => {
      void hideToTray();
    }).then((unlisten) => {
      dispose = unlisten;
    });

    return () => dispose?.();
  }, []);

  return null;
}
