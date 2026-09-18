import 'dart:io';

import 'package:toolbox/common/app_log.dart';

/// "打开文件"临时目录前缀（每次打开远程文件都会在系统临时目录下
/// 新建一个 `toolbox_sftp*` 目录，用后不删）。
const String _kOpenFileTempPrefix = 'toolbox_sftp';

/// 只清理「确实属于上次运行遗留」的目录：早于这个时长的才算遗留。
///
/// 多开窗口时，另一个实例的临时目录是新建的——按时间跳过它，
/// 避免把别的窗口正在查看的文件目录删掉。
const Duration _kMinAge = Duration(hours: 12);

/// 清理遗留的"打开文件"临时目录（跨次运行会无限累积）。
/// 应用启动时调用一次；正在被外部程序占用的目录删除失败会被忽略。
void cleanupOpenFileTempDirs() {
  var cleaned = 0;
  try {
    final now = DateTime.now();
    for (final entity in Directory.systemTemp.listSync()) {
      if (entity is! Directory) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      if (!name.startsWith(_kOpenFileTempPrefix)) continue;
      try {
        if (now.difference(entity.statSync().modified) < _kMinAge) continue;
        entity.deleteSync(recursive: true);
        cleaned++;
      } catch (_) {
        // 单个目录被占用/删除失败不影响其余清理。
      }
    }
  } catch (e) {
    // 临时目录不可读时跳过（不影响启动）。
    AppLog.w('sftp', '临时目录清理跳过：$e');
  }
  if (cleaned > 0) {
    AppLog.i('sftp', '已清理 $cleaned 个遗留的「打开文件」临时目录');
  }
}
