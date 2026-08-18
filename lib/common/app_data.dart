import 'dart:io';

/// 应用数据目录：统一存放于安装目录下的 `data` 子目录。
///
/// 无论压缩包解压运行还是 exe 安装运行，所有数据均写入 exe 同级目录下的
/// `data/`，保证两种分发方式的数据位置一致，且备份时只需整体备份 `data/`。
class AppDataDir {
  AppDataDir._();

  /// 应用数据目录（配置/文件存放于此）。
  static String get path =>
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}data';
}
