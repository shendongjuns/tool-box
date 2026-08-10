import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/features/settings/data/app_settings.dart';
import 'package:toolbox/features/settings/presentation/settings_controller.dart';

/// 目录转移核心逻辑测试（不触发真实重启 —— 用 migrateDataDir）。
void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('toolbox_test_');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  /// 构造控制器：初始 dataDir 指向 [dataDir]（通过 gInitialSettings）。
  ProviderContainer makeContainer(String dataDir) {
    gInitialSettings = AppSettings(dataDir: dataDir);
    return ProviderContainer();
  }

  test('migrateDataDir：完整转移数据并删除旧目录', () async {
    final oldDir = Directory('${tempRoot.path}${Platform.pathSeparator}old')
      ..createSync(recursive: true);
    final newDir =
        Directory('${tempRoot.path}${Platform.pathSeparator}new');
    // 旧目录内放测试文件与子目录
    File('${oldDir.path}${Platform.pathSeparator}a.txt')
        .writeAsStringSync('hello');
    Directory('${oldDir.path}${Platform.pathSeparator}sub')
        .createSync(recursive: true);
    File('${oldDir.path}${Platform.pathSeparator}sub${Platform.pathSeparator}b.txt')
        .writeAsStringSync('world');

    final container = makeContainer(oldDir.path);
    addTearDown(container.dispose);

    final ok = await container
        .read(settingsControllerProvider.notifier)
        .migrateDataDir(newDir.path);

    expect(ok, isTrue);
    // 新目录包含全部数据
    expect(File('${newDir.path}${Platform.pathSeparator}a.txt').readAsStringSync(),
        'hello');
    expect(
        File('${newDir.path}${Platform.pathSeparator}sub${Platform.pathSeparator}b.txt')
            .readAsStringSync(),
        'world');
    // 旧目录已删除
    expect(oldDir.existsSync(), isFalse);
    // 状态已更新
    expect(container.read(settingsControllerProvider).dataDir, newDir.path);
  });

  test('migrateDataDir：新目录位于旧目录内部时拒绝', () async {
    final oldDir = Directory('${tempRoot.path}${Platform.pathSeparator}old')
      ..createSync(recursive: true);
    final inner = '${oldDir.path}${Platform.pathSeparator}inner';

    final container = makeContainer(oldDir.path);
    addTearDown(container.dispose);

    final ok = await container
        .read(settingsControllerProvider.notifier)
        .migrateDataDir(inner);

    expect(ok, isFalse);
    // 旧目录未受影响
    expect(oldDir.existsSync(), isTrue);
    expect(container.read(settingsControllerProvider).dataDir, oldDir.path);
  });

  test('migrateDataDir：相同目录拒绝', () async {
    final dir = Directory('${tempRoot.path}${Platform.pathSeparator}same')
      ..createSync(recursive: true);

    final container = makeContainer(dir.path);
    addTearDown(container.dispose);

    final ok = await container
        .read(settingsControllerProvider.notifier)
        .migrateDataDir(dir.path);
    expect(ok, isFalse);
  });

  test('损坏配置回退默认目录', () async {
    // 配置目录写损坏 JSON
    final configDir =
        Directory('${tempRoot.path}${Platform.pathSeparator}appdata')
          ..createSync(recursive: true);
    File('${configDir.path}${Platform.pathSeparator}tool-box${Platform.pathSeparator}settings.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{{{ 损坏的 JSON');

    final store = AppSettingsStore(appDataDir: configDir.path);
    final settings = await store.load();
    expect(settings.dataDir, AppSettings.defaultDataDir());
  });
}
