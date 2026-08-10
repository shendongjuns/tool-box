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

- 第一个命令产出 Flutter 构建产物 `build\windows\x64\runner\Release\`（内含 `toolbox.exe`）。
- 第二个命令用 Inno Setup 编译安装脚本。`/DAppVersion` 用于指定版本号；省略时脚本默认取 `1.0.0`（见 `toolbox.iss` 中 `#ifndef MyAppVersion` 的默认值逻辑）。
- 安装包输出到项目根目录：`ToolBox-Setup-1.2.0.exe`（`OutputDir=..\..` 相对本脚本所在目录上溯两级，即仓库根目录）。

## 制作便携 zip（可选）

```powershell
cd build\windows\x64\runner\Release
7z a ../../../../ToolBox-portable.zip .
```

将 `Release` 目录整体压缩（含 `toolbox.exe`、`data\`、依赖 DLL），可直接解压运行，无需安装。

## 关于安装脚本

- `toolbox.iss` 使用 `{autopf}`（Program Files）作为默认安装目录，普通用户安装时 Inno Setup 会自动请求提权，无需管理员预先设置。
- 安装器内置中文简体语言（`chinesesimp`），默认勾选「创建桌面快捷方式」，安装完成后可勾选立即启动。
- 脚本中的 `MyAppSourceDir` 默认值 `build\windows\x64\runner\Release` 与 `flutter build windows --release` 的产物路径一致；若构建产物在其他位置，可用 `iscc /DMyAppSourceDir=...` 覆盖。

## CI 自动发布

推送标签 `git tag v1.2.0 && git push origin v1.2.0` 后，`.github/workflows/release.yml` 会在 GitHub Actions（windows-latest）上自动执行：构建 → 测试 → 打包，并上传 `ToolBox-Setup-<版本>.exe` 与 `ToolBox-portable.zip` 到对应 Release 页。
