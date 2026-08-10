import 'dart:io';

/// 应用数据目录：固定为 exe 所在目录（安装目录），无需配置。
class AppDataDir {
  AppDataDir._();

  /// exe 所在目录（安装目录）。所有应用数据（配置/文件）存放于此。
  static String get path =>
      File(Platform.resolvedExecutable).parent.path;
}
