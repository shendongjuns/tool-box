; ToolBox NSIS 自定义安装脚本
;
; 目标：
;   1. 允许用户修改安装目录（Tauri 的 NSIS 模板默认已提供 MUI_PAGE_DIRECTORY）
;   2. 在桌面创建快捷方式，取消勾选也能通过开始菜单启动

!macro NSIS_HOOK_POSTINSTALL
  ; 桌面快捷方式
  CreateShortcut "$DESKTOP\ToolBox.lnk" "$INSTDIR\toolbox-desktop.exe" "" "$INSTDIR\toolbox-desktop.exe" 0
!macroend

!macro NSIS_HOOK_PREUNINSTALL
  ; 卸载时清理桌面快捷方式
  Delete "$DESKTOP\ToolBox.lnk"
!macroend
