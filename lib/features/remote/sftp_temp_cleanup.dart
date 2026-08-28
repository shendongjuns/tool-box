import 'dart:io';

/// "打开文件"临时目录前缀（每次打开远程文件都会在系统临时目录下
/// 新建一个 `toolbox_sftp*` 目录，用后不删）。
const String _kOpenFileTempPrefix = 'toolbox_sftp';

/// 清理上次运行遗留的"打开文件"临时目录（跨次运行会无限累积）。
/// 应用启动时调用一次；正在被外部程序占用的目录删除失败会被忽略。
void cleanupOpenFileTempDirs() {
  try {
    for (final entity in Directory.systemTemp.listSync()) {
      if (entity is! Directory) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      if (!name.startsWith(_kOpenFileTempPrefix)) continue;
      try {
        entity.deleteSync(recursive: true);
      } catch (_) {
        // 单个目录被占用/删除失败不影响其余清理。
      }
    }
  } catch (_) {
    // 临时目录不可读时静默跳过（不影响启动）。
  }
}
