# ToolBox 安装包打包说明

本目录包含 ToolBox 的 Windows 安装包构建脚本（Inno Setup 6）。CI 在推送 `v*` 标签时自动执行；你也可以在本地手动打包。

## 前置条件

- [Flutter SDK](https://docs.flutter.dev/get-started/install/windows)（需启用 Windows Desktop 支持，`flutter doctor` 无报错）
- [Inno Setup 6](https://jrsoftware.org/isdl.php)（安装后 `iscc` 加入 PATH）
- 7-Zip（可选，仅制作便携 zip 需要）

## 一键打包（PowerShell，项目根目录）

```powershell
flutter build windows --release
iscc /DAppVersion=1.2.0 .github/installer/toolbox.iss
```

- 第一个命令产出 Flutter 构建产物 `build\windows\x64\runner\Release\`（内含 `ToolBox.exe`）。
- 第二个命令用 Inno Setup 编译安装脚本。`/DAppVersion` 用于指定版本号；省略时脚本默认取 `1.0.0`（见 `toolbox.iss` 中 `#ifndef AppVersion` 的默认值逻辑，**CI 传的就是 `AppVersion` 这个名字**）。
- 安装包输出到项目根目录：`ToolBox-Setup-1.2.0.exe`（`OutputDir=..\..` 相对本脚本所在目录上溯两级，即仓库根目录）。

## 制作便携 zip（可选）

```powershell
cd build\windows\x64\runner\Release
7z a ../../../../ToolBox-portable.zip .
```

将 `Release` 目录整体压缩（含 `ToolBox.exe`、`data\`、依赖 DLL），可直接解压运行，无需安装。

## 升级：安装包自己识别，应用内不做更新检查

**结论：不要给应用加「检查更新」**。版本判断由安装程序负责：

- `toolbox.iss` 的 `AppId` 是**固定 GUID**、`DefaultDirName` 固定为
  `{localappdata}\Programs\ToolBox` —— Inno Setup 因此会把新版本识别为
  **同一程序的升级**，直接覆盖安装到原目录，不会并存两份、也不会新开一个安装位置。
- 需要升级时：下载新的 `ToolBox-Setup-<版本>.exe` 双击即可（安装向导会显示当前版本与
  新版本）。数据在 `user/` 子目录里，覆盖安装不会碰它。
- 若程序正在运行，Inno Setup 的 `CloseApplications`（默认开启）会用重启管理器提示关闭
  占用文件的进程再继续；由于本程序默认「关闭窗口即最小化到托盘」，升级前请先从
  **托盘右键菜单 → 退出 ToolBox**，否则会卡在「文件被占用」那一步。

## 关于安装脚本

- `toolbox.iss` 把默认安装目录设为 `{localappdata}\Programs\ToolBox`（当前用户目录），
  `PrivilegesRequired=lowest` —— **免管理员、免提权**。
  这样选择是因为应用把数据写在 exe 同级的 `user/` 下，而 Program Files 对普通用户不可写
  （本应用是 x64 进程，不享受 UAC 虚拟化重定向），装在那里会导致保存静默失败。
- 安装器内置中文简体语言（`chinesesimp`），默认勾选「创建桌面快捷方式」，安装完成后可勾选立即启动。
- 脚本中的 `MyAppSourceDir` 默认值 `..\..\build\windows\x64\runner\Release`（相对脚本目录上两级到仓库根）与 `flutter build windows --release` 的产物路径一致；若构建产物在其他位置，可用 `iscc /DMyAppSourceDir=...` 覆盖（相对脚本目录的路径）。

## CI 自动发布

推送标签 `git tag v1.2.0 && git push origin v1.2.0` 后，`.github/workflows/release.yml` 会在 GitHub Actions（windows-latest）上自动执行：构建 → 测试 → 打包，并上传 `ToolBox-Setup-<版本>.exe` 与 `ToolBox-portable.zip` 到对应 Release 页。
