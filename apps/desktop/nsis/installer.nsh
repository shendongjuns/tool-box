; ToolBox 安装器钩子
;
; 为什么需要：
; Tauri 的 NSIS 模板默认只在开始菜单创建快捷方式，桌面快捷方式需要自己加。
; 这份文件曾被误删（tauri.conf 仍引用它），导致安装后桌面上找不到图标。
;
; 注意：宏名必须与 Tauri 的 NSIS 模板完全一致，
; 否则不会被执行，而且不会有任何报错（静默失效）。

!macro NSIS_HOOK_POSTINSTALL
  ; 创建桌面快捷方式（仅当前用户，与 installMode=currentUser 对应）
  CreateShortcut "$DESKTOP\ToolBox.lnk" "$INSTDIR\${MAINBINARYNAME}.exe"
!macroend

!macro NSIS_HOOK_PREUNINSTALL
  ; 卸载时清理桌面快捷方式，不留残影
  Delete "$DESKTOP\ToolBox.lnk"
!macroend
