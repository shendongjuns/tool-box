; ToolBox 安装脚本（Inno Setup 6）
; 构建参数：/DAppVersion=x.y.z（由 CI 传入，未传时默认 1.0.0）
; 注意：符号名必须与 CI 传参一致（AppVersion，非 MyAppVersion），
; 否则版本恒为默认值导致安装包名/版本错误。
#define MyAppName "ToolBox"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
; 相对路径基于本 iss 文件目录（.github/installer/），上两级到仓库根再进 build。
#ifndef MyAppSourceDir
  #define MyAppSourceDir "..\..\build\windows\x64\runner\Release"
#endif
#define MyAppPublisher "shendongjuns"
#define MyAppExeName "ToolBox.exe"

[Setup]
AppId={{8F2B1C44-7A3E-4D9E-9B4A-5C1D0E2F3A4B}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppPublisher={#MyAppPublisher}
; 安装到「当前用户目录」而不是 Program Files：
; 应用把数据写在 exe 同级的 user/ 下，而 Program Files 对普通用户不可写
; （本应用是 x64 进程，不享受 UAC 虚拟化重定向），会导致保存静默失败。
; 装到用户目录后免管理员、数据可写，也保持「数据在程序旁边」的设计。
DefaultDirName={localappdata}\Programs\{#MyAppName}
PrivilegesRequired=lowest
DefaultGroupName={#MyAppName}
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir=..\..
OutputBaseFilename=ToolBox-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
; 中文语言文件随仓库提供（官方发行版不带 ChineseSimplified.isl），
; 相对路径基于本 iss 文件所在目录（.github/installer/）。
Name: "chinesesimp"; MessagesFile: "Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务:"

[Files]
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent
