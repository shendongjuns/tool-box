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

  test('setDark 切换主题模式', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(themeControllerProvider.notifier).setDark(true);
    expect(container.read(themeControllerProvider), ThemeMode.dark);
    container.read(themeControllerProvider.notifier).setDark(false);
    expect(container.read(themeControllerProvider), ThemeMode.light);
  });
}
