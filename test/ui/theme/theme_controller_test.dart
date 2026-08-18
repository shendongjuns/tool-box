import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/common/settings_store.dart';
import 'package:toolbox/ui/theme/theme_controller.dart';

void main() {
  late Directory tempDir;

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(SettingsStore(dir: tempDir.path)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('theme_controller_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('ThemeController 初始为跟随系统', () {
    final container = makeContainer();
    expect(container.read(themeControllerProvider), ThemeMode.system);
  });

  test('setMode 直接设置主题模式', () {
    final container = makeContainer();
    container.read(themeControllerProvider.notifier).setMode(ThemeMode.dark);
    expect(container.read(themeControllerProvider), ThemeMode.dark);
    container.read(themeControllerProvider.notifier).setMode(ThemeMode.light);
    expect(container.read(themeControllerProvider), ThemeMode.light);
  });

  test('主题模式变更持久化，新容器（重启）自动恢复', () {
    final container = makeContainer();
    container.read(themeControllerProvider.notifier).setMode(ThemeMode.dark);

    // 新容器模拟应用重启：从持久化配置恢复。
    final restarted = makeContainer();
    expect(restarted.read(themeControllerProvider), ThemeMode.dark);
  });

  test('cycle 按 系统→浅色→深色→系统 循环并持久化', () {
    final container = makeContainer();
    final notifier = container.read(themeControllerProvider.notifier);
    expect(container.read(themeControllerProvider), ThemeMode.system);
    notifier.cycle();
    expect(container.read(themeControllerProvider), ThemeMode.light);
    notifier.cycle();
    expect(container.read(themeControllerProvider), ThemeMode.dark);
    notifier.cycle();
    expect(container.read(themeControllerProvider), ThemeMode.system);

    final restarted = makeContainer();
    expect(restarted.read(themeControllerProvider), ThemeMode.system);
  });
}
