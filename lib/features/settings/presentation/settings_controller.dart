import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/app_settings.dart';

/// 启动时加载的配置（runApp 前初始化，供 build 作初始值）。
AppSettings? gInitialSettings;

/// 设置控制器：管理数据目录配置。
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => gInitialSettings ??
      AppSettings(dataDir: AppSettings.defaultDataDir());

  final _store = AppSettingsStore();

  /// 启动时加载配置。
  Future<void> init() async {
    state = await _store.load();
  }

  /// 确认并创建数据目录（首次启动引导用）。成功返回 true。
  Future<bool> confirmDataDir(String dir) async {
    try {
      Directory(dir).createSync(recursive: true);
    } catch (_) {
      return false;
    }
    state = AppSettings(dataDir: dir);
    await _store.save(state);
    return true;
  }

  /// 当前数据目录是否存在（首次启动判断）。
  bool get dataDirExists => Directory(state.dataDir).existsSync();

  /// 弹出目录选择器，返回所选路径（null = 取消）。
  Future<String?> pickDirectory() async {
    final dir = await getDirectoryPath();
    if (dir == null || dir == state.dataDir) return null;
    return dir;
  }

  /// 更改数据目录：转移数据后重启应用。成功返回 true；失败返回 false。
  Future<bool> changeDataDir(String newDir) async {
    final ok = await migrateDataDir(newDir);
    if (ok) _restartApp();
    return ok;
  }

  /// 转移数据目录（不含重启，便于测试）：完整复制旧目录数据到新目录 →
  /// 更新配置 → 删除旧目录 → 更新状态。
  ///
  /// 防护：新目录不得位于旧目录内部（避免递归复制自身）；
  /// 转移先复制后删除，复制失败不触碰旧数据。
  Future<bool> migrateDataDir(String newDir) async {
    final oldDir = state.dataDir;
    if (newDir == oldDir) return false;

    final source = Directory(oldDir);
    final target = Directory(newDir);

    // 新目录位于旧目录内部（或相同路径）时拒绝，避免无限递归复制。
    final normalizedTarget = target.absolute.path
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    final normalizedSource = source.absolute.path
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    if (normalizedTarget == normalizedSource ||
        normalizedTarget.startsWith('$normalizedSource/')) {
      return false;
    }

    try {
      // 1. 创建新目录
      target.createSync(recursive: true);
      // 2. 完整转移数据（先复制，成功后才删除旧目录）
      if (source.existsSync()) {
        _copyRecursively(source, target);
      }
      // 3. 更新配置（指向新目录）
      await _store.save(AppSettings(dataDir: newDir));
      // 4. 删除旧目录（数据已完整转移）
      if (source.existsSync()) {
        source.deleteSync(recursive: true);
      }
      // 5. 更新状态
      state = AppSettings(dataDir: newDir);
      return true;
    } catch (_) {
      // 转移失败：保留旧目录与旧配置
      return false;
    }
  }

  /// 递归复制目录内容。
  /// 注意：不能用 uri.pathSegments.last 取名称 —— Directory 的 uri 以
  /// 斜杠结尾，pathSegments.last 为空字符串（子目录名丢失的 bug）。
  void _copyRecursively(Directory source, Directory target) {
    for (final entity in source.listSync(recursive: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      final dest = '${target.path}${Platform.pathSeparator}$name';
      if (entity is Directory) {
        Directory(dest).createSync(recursive: true);
        _copyRecursively(entity, Directory(dest));
      } else if (entity is File) {
        entity.copySync(dest);
      }
    }
  }

  /// 重启应用（当前 exe 新进程，退出旧进程）。
  void _restartApp() {
    try {
      Process.start(
        Platform.resolvedExecutable,
        [],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      // 重启失败不阻塞
    }
    exit(0);
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);
