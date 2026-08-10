; ToolBox 安装脚本（Inno Setup 6）
; 构建参数：/DAppVersion=x.y.z（由 CI 传入），未传时默认 1.0.0
#define MyAppName "ToolBox"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#ifndef MyAppSourceDir
  #define MyAppSourceDir "build\windows\x64\runner\Release"
#endif
#define MyAppPublisher "shendongjuns"
#define MyAppExeName "toolbox.exe"

[Setup]
AppId={{8F2B1C44-7A3E-4D9E-9B4A-5C1D0E2F3A4B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir=..\..
OutputBaseFilename=ToolBox-Setup-{#MyAppVersion}
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
