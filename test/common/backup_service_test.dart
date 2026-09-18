import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/common/app_data.dart';
import 'package:toolbox/common/backup_service.dart';
import 'package:toolbox/common/json_store_io.dart';
import 'package:toolbox/common/settings_store.dart';

/// 备份导出 / 导入的行为。
///
/// 这是**会整体替换用户数据**的功能，所以测试重点是「不许出错」的那几面：
/// 导出必须带清单、导入必须校验格式、覆盖前必须留底、拒绝时不能动数据、
/// 目录穿越条目必须被丢弃、导入后必须停止写盘（否则重启前就被覆盖回去）。
void main() {
  late Directory dir;
  late Directory scratch;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('backup_data');
    scratch = Directory.systemTemp.createTempSync('backup_zip');
    AppDataDir.overridePath(dir.path);
    JsonStoreIo.frozen = false;
  });

  tearDown(() {
    AppDataDir.overridePath(null);
    BackupService.formatBackupPathOverride = null;
    JsonStoreIo.frozen = false;
    for (final d in [dir, scratch]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  String p(String relative) => '${dir.path}${Platform.pathSeparator}$relative';

  void writeData(String relative, String content) {
    final file = File(p(relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  String readData(String relative) => File(p(relative)).readAsStringSync();

  bool exists(String relative) => File(p(relative)).existsSync();

  /// 把当前数据打包成 zip 并写到临时目录，返回路径。
  String exportZip([String name = 'backup.zip']) {
    final path = '${scratch.path}${Platform.pathSeparator}$name';
    File(path).writeAsBytesSync(BackupService.buildZip());
    return path;
  }

  /// 造一个「任意 zip」，用于验证非本应用备份会被拒绝。
  String writeForeignZip() {
    final archive = Archive()
      ..addFile(ArchiveFile.string('readme.txt', 'not a toolbox backup'));
    final path = '${scratch.path}${Platform.pathSeparator}foreign.zip';
    File(path).writeAsBytesSync(ZipEncoder().encode(archive)!);
    return path;
  }

  group('导出', () {
    test('打包数据目录里的全部文件，并写入清单', () {
      writeData('settings.json', '{"themeMode":"dark"}');
      writeData('ssh_connections.json', '[]');
      writeData('logs/app.log', 'hello');

      final archive = ZipDecoder().decodeBytes(BackupService.buildZip());
      final names = archive.files.map((f) => f.name).toSet();

      expect(names, contains('settings.json'));
      expect(names, contains('ssh_connections.json'));
      expect(names, contains('logs/app.log'));
      expect(names, contains(backupManifestName));

      final manifest = jsonDecode(
        utf8.decode(
          archive.files
                  .firstWhere((f) => f.name == backupManifestName)
                  .content
              as List<int>,
        ),
      ) as Map<String, dynamic>;
      expect(manifest['format'], backupFormat);
      expect(manifest['formatVersion'], backupFormatVersion);
      expect(manifest['fileCount'], 3);
    });

    test('不打包锁文件、原子写的中间文件与回滚副本目录', () {
      writeData('settings.json', '{}');
      writeData('.instance.lock', '1234');
      writeData('settings.json.tmp', '半截 json');
      writeData('${BackupService.snapshotDirName}/20260101/old/settings.json', '{}');

      final archive = ZipDecoder().decodeBytes(BackupService.buildZip());
      final names = archive.files.map((f) => f.name).toList();

      expect(names, contains('settings.json'));
      expect(names, isNot(contains('.instance.lock')));
      expect(names, isNot(contains('settings.json.tmp')));
      expect(
        names.where((n) => n.startsWith(BackupService.snapshotDirName)),
        isEmpty,
        reason: '回滚副本是备份自身的产物，不该被打进备份',
      );
    });

    test('数据目录为空时也能导出（只有清单）', () {
      final archive = ZipDecoder().decodeBytes(BackupService.buildZip());
      expect(archive.files.map((f) => f.name), [backupManifestName]);
    });

    test('默认文件名带日期时间且以 .zip 结尾', () {
      final name = BackupService.defaultFileName(DateTime(2026, 9, 18, 14, 23));
      expect(name, 'ToolBox-backup-20260918-1423.zip');
    });
  });

  group('导入', () {
    test('用备份覆盖当前数据：恢复文件、清掉多余的、留底旧数据', () {
      writeData('settings.json', '备份里的设置');
      writeData('ssh_connections.json', '备份里的连接');
      final zip = exportZip();

      // 备份之后用户又改了数据：改了一个、加了新的
      writeData('settings.json', '后来改的设置');
      writeData('repo_groups.json', '备份里没有的仓库分组');

      final result = BackupService.importFrom(zip);

      expect(result.success, isTrue, reason: result.message);
      expect(result.fileCount, 2);
      expect(readData('settings.json'), '备份里的设置');
      expect(readData('ssh_connections.json'), '备份里的连接');
      expect(
        exists('repo_groups.json'),
        isFalse,
        reason: '恢复语义是「回到备份当时的样子」，备份里没有的顶层数据要被清掉',
      );

      // 覆盖前必须留底，且内容是被覆盖前的那份
      final snapshot = result.snapshotDir;
      expect(snapshot, isNotNull);
      final backedUp = File('$snapshot${Platform.pathSeparator}settings.json');
      expect(backedUp.readAsStringSync(), '后来改的设置');
      expect(
        Directory('$snapshot${Platform.pathSeparator}settings.json')
            .existsSync(),
        isFalse,
      );
    });

    test('留底目录保留最近 3 份', () {
      writeData('settings.json', 'v1');
      final zip = exportZip();

      for (var i = 0; i < 5; i++) {
        writeData('settings.json', 'v$i');
        // 留底目录名精确到毫秒，连续导入不会撞名
        expect(BackupService.importFrom(zip).success, isTrue);
        sleep(const Duration(milliseconds: 5));
      }

      final snapshots =
          Directory(
            p(BackupService.snapshotDirName),
          ).listSync().whereType<Directory>().toList();
      expect(snapshots.length, lessThanOrEqualTo(3));
      expect(snapshots, isNotEmpty);
    });

    test('拒绝没有清单的 zip，且不改动当前数据', () {
      writeData('settings.json', '原样');
      final foreign = writeForeignZip();

      final result = BackupService.importFrom(foreign);

      expect(result.success, isFalse);
      expect(result.message, contains(backupManifestName));
      expect(readData('settings.json'), '原样');
      expect(
        Directory(p(BackupService.snapshotDirName)).existsSync(),
        isFalse,
        reason: '校验失败发生在动手之前，不该留下空目录',
      );
    });

    test('拒绝损坏的文件与不存在的路径', () {
      writeData('settings.json', '原样');
      final broken = '${scratch.path}${Platform.pathSeparator}broken.zip';
      File(broken).writeAsBytesSync(List<int>.filled(64, 7));

      expect(BackupService.importFrom(broken).success, isFalse);
      expect(
        BackupService.importFrom('${scratch.path}\\not-exists.zip').message,
        contains('不存在'),
      );
      expect(readData('settings.json'), '原样');
    });

    test('丢弃目录穿越条目（不能写到数据目录之外）', () {
      writeData('settings.json', '原样');
      final archive = Archive()
        ..addFile(
          ArchiveFile.string(
            backupManifestName,
            jsonEncode({
              'format': backupFormat,
              'formatVersion': backupFormatVersion,
            }),
          ),
        )
        ..addFile(ArchiveFile.string('settings.json', '来自备份'))
        ..addFile(ArchiveFile.string('../evil.json', '越界'))
        ..addFile(ArchiveFile.string('sub/../../evil2.json', '越界'))
        ..addFile(ArchiveFile.string('C:/evil3.json', '越界'));
      final evil = '${scratch.path}${Platform.pathSeparator}evil.zip';
      File(evil).writeAsBytesSync(ZipEncoder().encode(archive)!);

      final result = BackupService.importFrom(evil);

      expect(result.success, isTrue, reason: result.message);
      expect(result.fileCount, 1, reason: '越界条目应被丢弃，只写入合法的那一个');
      expect(readData('settings.json'), '来自备份');
      // 数据目录内外都不该出现这些文件
      final outside = Directory(dir.path).parent.path;
      for (final name in ['evil.json', 'evil2.json']) {
        expect(File('$outside${Platform.pathSeparator}$name').existsSync(), isFalse);
        expect(exists(name), isFalse);
      }
    });

    test('备份来自更新版本时拒绝导入（而不是按旧格式硬解）', () {
      writeData('settings.json', '原样');
      final archive = Archive()
        ..addFile(
          ArchiveFile.string(
            backupManifestName,
            jsonEncode({
              'format': backupFormat,
              'formatVersion': backupFormatVersion + 1,
            }),
          ),
        )
        ..addFile(ArchiveFile.string('settings.json', '来自未来'));
      final path = '${scratch.path}${Platform.pathSeparator}future.zip';
      File(path).writeAsBytesSync(ZipEncoder().encode(archive)!);

      final result = BackupService.importFrom(path);

      expect(result.success, isFalse);
      expect(result.message, contains('更新版本'));
      expect(readData('settings.json'), '原样');
    });

    test('剥掉统一的顶层 user/ 目录（用户重新打包整份目录也能导入）', () {
      final archive = Archive()
        ..addFile(
          ArchiveFile.string(
            backupManifestName,
            jsonEncode({
              'format': backupFormat,
              'formatVersion': backupFormatVersion,
            }),
          ),
        )
        ..addFile(ArchiveFile.string('user/settings.json', '嵌套备份'));
      final path = '${scratch.path}${Platform.pathSeparator}nested.zip';
      File(path).writeAsBytesSync(ZipEncoder().encode(archive)!);

      final result = BackupService.importFrom(path);

      expect(result.success, isTrue, reason: result.message);
      expect(readData('settings.json'), '嵌套备份');
      expect(exists('user/settings.json'), isFalse);
    });

    test('导入后停止写盘，避免运行中的旧数据把结果覆盖回去', () {
      writeData('settings.json', '备份里的设置');
      final zip = exportZip();
      expect(BackupService.importFrom(zip).success, isTrue);
      expect(JsonStoreIo.frozen, isTrue);

      final store = SettingsStore(dir: dir.path);
      expect(store.write({'themeMode': 'light'}), isFalse);
      expect(
        readData('settings.json'),
        '备份里的设置',
        reason: '导入后内存里的旧设置不许再落盘',
      );
    });
  });

  group('格式化', () {
    test('先强制备份再清空，而且那份备份真的能导入回来', () {
      writeData('settings.json', '要保住的数据');
      writeData('ssh_connections.json', '[]');
      writeData('logs/app.log', '日志');

      final result = BackupService.formatData();

      expect(result.success, isTrue, reason: result.message);
      final backup = result.backupPath;
      expect(backup, isNotNull);
      expect(File(backup!).existsSync(), isTrue, reason: '强制备份必须真的落盘');
      expect(
        Directory(backup).parent.path,
        Directory(dir.path).parent.path,
        reason: '备份要放在数据目录的上一级——数据目录本身马上要被清空',
      );

      // 数据目录已清空
      expect(exists('settings.json'), isFalse);
      expect(exists('ssh_connections.json'), isFalse);
      expect(exists('logs/app.log'), isFalse);

      // 备份不是走过场：能完整还原
      final restored = BackupService.importFrom(backup);
      expect(restored.success, isTrue, reason: restored.message);
      expect(readData('settings.json'), '要保住的数据');
      expect(readData('logs/app.log'), '日志');
    });

    test('备份写不出去时中止格式化，数据一个字节都不删', () {
      writeData('settings.json', '原始数据');
      // 让备份路径的父级是一个**文件**，创建目录必然失败
      final blocker = File('${scratch.path}${Platform.pathSeparator}blocker')
        ..writeAsStringSync('x');
      BackupService.formatBackupPathOverride =
          '${blocker.path}${Platform.pathSeparator}backup.zip';

      final result = BackupService.formatData();

      expect(result.success, isFalse);
      expect(result.message, contains('中止'));
      expect(readData('settings.json'), '原始数据');
      expect(JsonStoreIo.frozen, isFalse, reason: '没格式化就不该冻结写盘');
    });

    test('连历史回滚副本一起清掉，但保留锁文件与探针', () {
      writeData('settings.json', '{}');
      writeData('.instance.lock', '1234');
      writeData('.write-probe', 'ok');
      writeData('${BackupService.snapshotDirName}/20260101/settings.json', '{}');

      final result = BackupService.formatData();

      expect(result.success, isTrue, reason: result.message);
      expect(exists('.instance.lock'), isTrue, reason: '本进程持有的锁文件不能删');
      expect(exists('.write-probe'), isTrue);
      expect(
        Directory(p(BackupService.snapshotDirName)).existsSync(),
        isFalse,
        reason: '格式化要回到「刚装好的样子」，历史副本也清掉',
      );
    });

    test('格式化后停止写盘，避免界面把清空结果又写回去', () {
      writeData('settings.json', '{"themeMode":"dark"}');

      expect(BackupService.formatData().success, isTrue);
      expect(JsonStoreIo.frozen, isTrue);

      final store = SettingsStore(dir: dir.path);
      expect(store.write({'themeMode': 'light'}), isFalse);
      expect(exists('settings.json'), isFalse, reason: '被冻结的写入不该又把文件造出来');
    });

    test('备份文件名带时间戳；同一秒内连着格式化不会覆盖上一份', () {
      writeData('settings.json', '{}');

      final first = BackupService.formatData().backupPath!;
      final second = BackupService.formatData().backupPath!;

      expect(first, isNot(second));
      expect(File(first).existsSync(), isTrue);
      expect(File(second).existsSync(), isTrue);
    });

    test('默认落点与文件命名规则', () {
      final path = BackupService.formatBackupPath(
        DateTime(2026, 9, 18, 15, 2, 7),
      );
      expect(Directory(path).parent.path, Directory(dir.path).parent.path);
      expect(
        File(path).uri.pathSegments.last,
        'ToolBox-backup-before-format-20260918-150207.zip',
      );
    });
  });
}
