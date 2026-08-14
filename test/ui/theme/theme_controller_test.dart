import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/ui/theme/theme_controller.dart';

void main() {
  test('ThemeController 初始为跟随系统', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(themeControllerProvider), ThemeMode.system);
  });

  test('setMode 直接设置主题模式', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(themeControllerProvider.notifier).setMode(ThemeMode.dark);
    expect(container.read(themeControllerProvider), ThemeMode.dark);
    container.read(themeControllerProvider.notifier).setMode(ThemeMode.light);
    expect(container.read(themeControllerProvider), ThemeMode.light);
  });

  test('cycle 按 系统→浅色→深色→系统 循环', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(themeControllerProvider.notifier);
    expect(container.read(themeControllerProvider), ThemeMode.system);
    notifier.cycle();
    expect(container.read(themeControllerProvider), ThemeMode.light);
    notifier.cycle();
    expect(container.read(themeControllerProvider), ThemeMode.dark);
    notifier.cycle();
    expect(container.read(themeControllerProvider), ThemeMode.system);
  });
}
