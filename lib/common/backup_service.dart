import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:toolbox/common/app_data.dart';
import 'package:toolbox/common/app_log.dart';
import 'package:toolbox/common/app_meta.dart';
import 'package:toolbox/common/byte_format.dart';
import 'package:toolbox/common/json_store_io.dart';

/// 备份清单的文件名。放在 zip 根部，导入时用它确认「这是本应用导出的备份」。
const String backupManifestName = 'backup-manifest.json';

/// 清单里的格式标识（防止用户误把别的 zip 当备份导入）。
const String backupFormat = 'toolbox-backup';

/// 当前备份格式版本。将来格式有破坏性变更时递增。
const int backupFormatVersion = 1;

/// 一次导出 / 导入 / 格式化 的结果。
///
/// 备份是**直接动用户数据**的操作，所以失败原因必须能原样展示给用户，
/// 不能让调用方自己去猜——这里用 [message] 承载可直接显示的中文说明。
class BackupResult {
  const BackupResult.ok(
    this.message, {
    this.fileCount = 0,
    this.bytes = 0,
    this.snapshotDir,
    this.backupPath,
  }) : success = true;

  const BackupResult.fail(this.message)
    : success = false,
      fileCount = 0,
      bytes = 0,
      snapshotDir = null,
      backupPath = null;

  /// 是否成功。
  final bool success;

  /// 可直接展示给用户的说明。
  final String message;

  /// 涉及的文件数。
  final int fileCount;

  /// zip 字节数（导出时有值）。
  final int bytes;

  /// 导入前自动留的回滚副本目录（仅导入成功时有值）。
  final String? snapshotDir;

  /// 格式化前强制留下的备份 zip（仅格式化成功时有值）。
  final String? backupPath;
}

/// 数据备份：导出为 zip / 用 zip 覆盖当前数据 / 格式化（清空）数据。
///
/// 备份范围就是整个数据目录（连接、设置、仓库、传输任务、日志），
/// 因为项目的定位就是「整份数据目录可整体备份」。
///
/// 三条硬性设计：
/// 1. **导出带清单**：zip 根部写入 [backupManifestName]，导入时校验格式与版本，
///    避免把无关 zip 解压到数据目录里造成污染；
/// 2. **导入先留底**：覆盖前把当前数据整体复制到 `.pre-import/<时间戳>/`，
///    用户发现导入错了可以直接把文件夹拷回去。该目录不参与导出；
/// 3. **格式化先强制备份**：清空数据前必须先成功导出一份备份，备份写不出去
///    就一个字节都不删（见 [formatData]）。
class BackupService {
  BackupService._();

  static const String _tag = 'backup';

  /// 无论备份、导入还是格式化，都**必须保留**的条目。
  ///
  /// - `.instance.lock`：本进程正持有它，删了会破坏单实例检测；
  /// - `.write-probe`：数据目录可写性探针（正常情况下不存在）。
  static const Set<String> _alwaysKeep = {'.instance.lock', '.write-probe'};

  /// 数据目录里不参与备份的条目。
  static const Set<String> _excludedNames = {
    ..._alwaysKeep,
    snapshotDirName, // 导入前的回滚副本，属于备份自身的产物
  };

  /// 导入前的回滚副本目录名（位于数据目录内）。
  static const String snapshotDirName = '.pre-import';

  /// 保留最近几份回滚副本。
  static const int _keepSnapshots = 3;

  /// 拒绝导入超过该体积的备份文件（整份读进内存，必须有上限）。
  static const int _maxImportBytes = 64 * 1024 * 1024;

  /// 导出的默认文件名（带时间戳，同一天多次导出不会互相覆盖）。
  static String defaultFileName([DateTime? now]) =>
      'ToolBox-backup-${_minuteStamp(now ?? DateTime.now())}.zip';

  /// 测试用：覆盖「格式化前强制备份」的落点。
  ///
  /// 生产环境永远为 null（走 [formatBackupPath]）；测试需要构造「备份写不出去」
  /// 的场景来验证**备份失败时绝不删数据**这条硬约束。
  @visibleForTesting
  static String? formatBackupPathOverride;

  /// 格式化前强制备份的落点：**数据目录的上一级**。
  ///
  /// 之所以放在上一级：数据目录本身马上要被清空，备份放里面等于没备份。
  /// 放在上一级还有个好处——便携模式下它就在 exe 旁边，用户一眼能看到；
  /// 需要恢复时用「导入备份」选这个文件即可。
  static String formatBackupPath([DateTime? now]) {
    final override = formatBackupPathOverride;
    if (override != null) return override;

    final parent = Directory(AppDataDir.path).parent.path;
    final base =
        'ToolBox-backup-before-format-${_secondStamp(now ?? DateTime.now())}';
    var candidate = '$parent${Platform.pathSeparator}$base.zip';
    // 同一秒内连着格式化两次时宁可多留一份，也不覆盖上一次的备份。
    for (var index = 1; File(candidate).existsSync(); index++) {
      candidate = '$parent${Platform.pathSeparator}$base-$index.zip';
    }
    return candidate;
  }

  /// 格式化（清空）数据目录。
  ///
  /// **硬约束：备份成功才允许清空。** 格式化不可撤销，所以这里先无条件导出一份
  /// 备份到 [formatBackupPath]；备份写不出去就直接返回失败，**一个字节都不删**。
  /// 「先备份再格式化」不是可选项，所以没有「跳过备份」的参数。
  static BackupResult formatData() {
    final backupPath = formatBackupPath();
    try {
      final bytes = buildZip();
      final file = File(backupPath);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes, flush: true);
      AppLog.i(
        _tag,
        '格式化前已强制备份：$backupPath（${formatBytes(bytes.length)}）',
      );
    } catch (e) {
      AppLog.e(_tag, '格式化前的强制备份失败，已中止格式化：$e');
      return BackupResult.fail('备份没写成（$e），已中止格式化，数据没有改动');
    }

    try {
      // 格式化连历史回滚副本一起清掉（此时手上已有一份强制备份）。
      final removed = _clearDataDir(keepSnapshots: false);
      JsonStoreIo.frozen = true;
      AppLog.i(_tag, '已格式化数据目录：清掉 $removed 个条目；备份在 $backupPath');
      return BackupResult.ok(
        '已清空 $removed 项数据',
        fileCount: removed,
        backupPath: backupPath,
      );
    } catch (e) {
      AppLog.e(_tag, '清空数据目录失败：$e');
      return BackupResult.fail('清空数据失败：$e');
    }
  }

  /// 把数据目录整体打包成 zip 字节。
  ///
  /// 同步实现：数据目录只有几十 KB 到几 MB（日志按 1 MB 轮转、最多 4 个），
  /// 打包耗时在几十毫秒量级，不值得为它引入 isolate 的复杂度。
  static Uint8List buildZip() {
    final root = Directory(AppDataDir.path);
    final archive = Archive();
    var files = 0;

    if (root.existsSync()) {
      for (final file in _collectFiles(root)) {
        final relative = _relativePath(root.path, file.path);
        final data = file.readAsBytesSync();
        final entry = ArchiveFile(relative, data.length, data);
        // 保留原始修改时间（ZipEncoder 约定：lastModTime 是「秒」时间戳）。
        entry.lastModTime = file.lastModifiedSync().millisecondsSinceEpoch ~/ 1000;
        archive.addFile(entry);
        files++;
      }
    }

    final manifest = <String, dynamic>{
      'format': backupFormat,
      'formatVersion': backupFormatVersion,
      'app': appName,
      'appVersion': appVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'fileCount': files,
    };
    final manifestBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(manifest),
    );
    archive.addFile(
      ArchiveFile(backupManifestName, manifestBytes.length, manifestBytes),
    );

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw StateError('打包失败：编码器没有返回数据');
    }
    AppLog.i(_tag, '已打包 $files 个文件（${formatBytes(encoded.length)}）');
    return Uint8List.fromList(encoded);
  }

  /// 用 [zipPath] 里的备份**覆盖**当前数据目录。
  ///
  /// 语义是「恢复到备份当时的状态」：备份里有的文件会被覆盖，
  /// 当前数据目录里备份没有的顶层条目会被清掉（覆盖前已整体留底）。
  ///
  /// ⚠️ 调用方必须在成功后**重启应用**：内存里的设置/连接是启动时读入的，
  /// 不重启的话下一次保存会把刚导入的数据又覆盖回去。
  static BackupResult importFrom(String zipPath) {
    final File source;
    try {
      source = File(zipPath);
      if (!source.existsSync()) {
        return const BackupResult.fail('备份文件不存在，可能已被移动或删除');
      }
      final size = source.lengthSync();
      if (size > _maxImportBytes) {
        return BackupResult.fail(
          '备份文件过大（${formatBytes(size)}），'
          '超过 ${formatBytes(_maxImportBytes)} 的备份不支持导入',
        );
      }
    } catch (e) {
      AppLog.e(_tag, '读取备份文件失败：$zipPath', e);
      return BackupResult.fail('读取备份文件失败：$e');
    }

    final Archive archive;
    try {
      // verify: 校验每个条目的 CRC，损坏的备份必须在覆盖数据之前就被拒绝。
      archive = ZipDecoder().decodeBytes(source.readAsBytesSync(), verify: true);
    } catch (e) {
      AppLog.e(_tag, '备份文件不是合法的 zip：$zipPath', e);
      return BackupResult.fail('备份文件已损坏或不是 zip 格式');
    }

    final manifest = _readManifest(archive);
    if (manifest == null) {
      return BackupResult.fail(
        '这不是本应用导出的备份（压缩包里找不到 $backupManifestName）',
      );
    }
    final version = manifest['formatVersion'];
    if (version is! int || version > backupFormatVersion) {
      return BackupResult.fail(
        '备份来自更新版本的应用（格式版本 $version），当前版本无法导入',
      );
    }

    final entries = _readEntries(archive);
    if (entries.isEmpty) {
      return BackupResult.fail('备份里没有任何数据文件');
    }

    try {
      final snapshot = _snapshotCurrentData();
      _clearDataDir();

      final root = AppDataDir.path;
      var written = 0;
      for (final entry in entries) {
        final target = File('$root${Platform.pathSeparator}${entry.name}');
        target.parent.createSync(recursive: true);
        target.writeAsBytesSync(entry.bytes, flush: true);
        written++;
      }
      _pruneSnapshots();

      // 数据目录已经换成备份里的内容，本次运行内存里的旧数据不能再落盘，
      // 否则用户随手改个设置就会把导入结果覆盖回去（见 JsonStoreIo.frozen）。
      JsonStoreIo.frozen = true;

      AppLog.i(
        _tag,
        '导入完成：覆盖 $written 个文件，导入前的数据已留底到 $snapshot',
      );
      return BackupResult.ok(
        '已恢复 $written 个文件',
        fileCount: written,
        snapshotDir: snapshot,
      );
    } catch (e) {
      AppLog.e(_tag, '写入数据目录失败', e);
      return BackupResult.fail('写入数据目录失败：$e');
    }
  }

  // ---------------- 内部实现 ----------------

  /// 读取并解析清单；不存在或不是本应用的备份时返回 null。
  static Map<String, dynamic>? _readManifest(Archive archive) {
    for (final file in archive.files) {
      if (!file.isFile || file.name != backupManifestName) continue;
      try {
        final decoded = jsonDecode(utf8.decode(file.content as List<int>));
        if (decoded is! Map<String, dynamic>) return null;
        if (decoded['format'] != backupFormat) return null;
        return decoded;
      } catch (e) {
        AppLog.w(_tag, '备份清单无法解析：$e');
        return null;
      }
    }
    return null;
  }

  /// 取出备份里可以落盘的文件条目（已做路径安全校验与公共前缀剥离）。
  static List<({String name, List<int> bytes})> _readEntries(Archive archive) {
    final files = archive.files
        .where((f) => f.isFile && f.name != backupManifestName)
        .toList();
    if (files.isEmpty) return const [];

    // 有人会把整个 `user` 目录再压一层，这里剥掉统一的顶层目录，
    // 否则数据会被还原到 `user/user/` 下，界面看起来「什么都没恢复」。
    final prefixes = files.map((f) => _firstSegment(f.name)).toSet();
    final stripPrefix = prefixes.length == 1 && prefixes.first == 'user';

    final entries = <({String name, List<int> bytes})>[];
    for (final file in files) {
      var name = file.name.replaceAll('\\', '/');
      if (stripPrefix) name = name.substring(name.indexOf('/') + 1);
      if (!_isSafeEntryName(name)) {
        AppLog.w(_tag, '跳过不安全的备份条目：${file.name}');
        continue;
      }
      entries.add((name: name, bytes: file.content as List<int>));
    }
    return entries;
  }

  /// 条目名是否可安全地拼接到数据目录下。
  ///
  /// 防的是「压缩包目录穿越」（zip-slip）：绝对路径、`..`、盘符都要挡掉，
  /// 否则一个恶意/损坏的备份可以把文件写到数据目录之外。
  static bool _isSafeEntryName(String name) {
    if (name.isEmpty) return false;
    if (name.startsWith('/') || name.contains('..')) return false;
    if (name.contains(':')) return false; // 盘符或 ADS（备用数据流）
    if (name.endsWith('/')) return false; // 目录条目：空目录不影响数据
    final first = _firstSegment(name);
    return !_excludedNames.contains(first);
  }

  static String _firstSegment(String name) {
    final normalized = name.replaceAll('\\', '/');
    final index = normalized.indexOf('/');
    return index < 0 ? normalized : normalized.substring(0, index);
  }

  /// 递归收集数据目录下参与备份的文件。
  static List<File> _collectFiles(Directory root) {
    final result = <File>[];
    final pending = <Directory>[root];
    while (pending.isNotEmpty) {
      final dir = pending.removeLast();
      for (final entity in dir.listSync(followLinks: false)) {
        final name = _basename(entity.path);
        if (_excludedNames.contains(name)) continue;
        if (name.endsWith('.tmp')) continue; // 原子写的中间文件
        if (entity is File) {
          result.add(entity);
        } else if (entity is Directory) {
          pending.add(entity);
        }
        // 软链接不跟随：既避免递归成环，也避免把数据目录外的内容打进备份。
      }
    }
    result.sort((a, b) => a.path.compareTo(b.path));
    return result;
  }

  /// 把当前数据目录整体复制一份到 `.pre-import/<时间戳>/`，返回该目录路径。
  static String _snapshotCurrentData() {
    final root = Directory(AppDataDir.path);
    final stamp = _timestamp(DateTime.now());
    final target = Directory(
      '${root.path}${Platform.pathSeparator}$snapshotDirName'
      '${Platform.pathSeparator}$stamp',
    );
    target.createSync(recursive: true);

    if (root.existsSync()) {
      for (final file in _collectFiles(root)) {
        final relative = _relativePath(root.path, file.path);
        final copy = File('${target.path}${Platform.pathSeparator}$relative');
        copy.parent.createSync(recursive: true);
        file.copySync(copy.path);
      }
    }
    AppLog.i(_tag, '导入前已留底：${target.path}');
    return target.path;
  }

  /// 清空数据目录；返回清掉的条目数。
  ///
  /// 永远保留 [._alwaysKeep] 里的条目（本进程正持有的锁文件、可写性探针）；
  /// [keepSnapshots] 为 false 时连 `.pre-import/` 历史回滚副本一起清掉 ——
  /// 格式化要的就是「恢复到刚装好的样子」。
  static int _clearDataDir({bool keepSnapshots = true}) {
    final root = Directory(AppDataDir.path);
    if (!root.existsSync()) {
      root.createSync(recursive: true);
      return 0;
    }
    var removed = 0;
    for (final entity in root.listSync(followLinks: false)) {
      final name = _basename(entity.path);
      if (_alwaysKeep.contains(name)) continue;
      if (keepSnapshots && name == snapshotDirName) continue;
      try {
        if (entity is File) {
          entity.deleteSync();
        } else if (entity is Directory) {
          entity.deleteSync(recursive: true);
        } else {
          continue;
        }
        removed++;
      } on FileSystemException catch (e) {
        // 单个条目删不掉不该让整次操作失败：后续同名文件会被覆盖，
        // 备份里没有的残留条目最多是多留一份旧数据。
        AppLog.w(_tag, '清理旧数据失败（已跳过）：${entity.path}（$e）');
      }
    }
    return removed;
  }

  /// 只保留最近 [_keepSnapshots] 份回滚副本。
  static void _pruneSnapshots() {
    try {
      final dir = Directory(
        '${AppDataDir.path}${Platform.pathSeparator}$snapshotDirName',
      );
      if (!dir.existsSync()) return;
      final snapshots =
          dir.listSync().whereType<Directory>().toList()
            ..sort((a, b) => b.path.compareTo(a.path)); // 时间戳命名 → 倒序即最新在前
      for (final stale in snapshots.skip(_keepSnapshots)) {
        stale.deleteSync(recursive: true);
      }
    } catch (e) {
      AppLog.w(_tag, '清理历史回滚副本失败：$e');
    }
  }

  static String _relativePath(String root, String path) {
    final prefix = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
    final relative = path.startsWith(prefix)
        ? path.substring(prefix.length)
        : path;
    return relative.replaceAll(Platform.pathSeparator, '/');
  }

  static String _basename(String path) {
    final index = path.lastIndexOf(Platform.pathSeparator);
    return index < 0 ? path : path.substring(index + 1);
  }

  /// 快照目录用的时间戳：精确到毫秒（同一毫秒内连续两次也能区分）。
  static String _timestamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}'
        '${two(t.minute)}${two(t.second)}-${three(t.millisecond)}';
  }

  /// 导出文件名用的时间戳：到分钟即可（够区分，又不会长得难读）。
  static String _minuteStamp(DateTime t) => '${_date(t)}-${_hhmm(t)}';

  /// 格式化备份文件名用的时间戳：到秒（避免连点两次只留一份）。
  static String _secondStamp(DateTime t) =>
      '${_date(t)}-${_hhmm(t)}${_two(t.second)}';

  static String _date(DateTime t) => '${t.year}${_two(t.month)}${_two(t.day)}';

  static String _hhmm(DateTime t) => '${_two(t.hour)}${_two(t.minute)}';

  static String _two(int v) => v.toString().padLeft(2, '0');

}
