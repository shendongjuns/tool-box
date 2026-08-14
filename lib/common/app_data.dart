import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 应用数据目录：优先使用用户可写的数据目录，便携模式回退到 exe 目录。
class AppDataDir {
  AppDataDir._();

  /// 应用数据目录（配置/文件存放于此）。
  ///
  /// 正常安装时使用系统用户数据目录（如 Windows `%APPDATA%`，可写、无需
  /// 管理员权限）；获取失败或便携模式下回退到 exe 所在目录。
  static Future<String> get path async {
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      return dir.path;
    } on Exception {
      final fallback = File(Platform.resolvedExecutable).parent;
      await fallback.create(recursive: true);
      return fallback.path;
    }
  }
}
