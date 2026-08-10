import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/ui/theme/appflowy_colors.dart';
import 'package:toolbox/ui/theme/appflowy_theme.dart';

void main() {
  test('浅色主题关键色值与 AppFlowy 色板一致', () {
    final theme = AppflowyTheme.light();
    expect(theme.colorScheme.surface, AppflowyColors.light.surface);
    expect(theme.colorScheme.primary, const Color(0xFF0092D6));
    expect(theme.colorScheme.onSurface, const Color(0xFF21232A));
  });

  test('深色主题存在且色板翻转', () {
    final theme = AppflowyTheme.dark();
    expect(theme.colorScheme.surface, AppflowyColors.dark.surface);
    expect(theme.colorScheme.primary, AppflowyColors.dark.primary);
    expect(theme.colorScheme.brightness, Brightness.dark);
  });

  test('间距与圆角常量精确', () {
    expect(AppflowySpacing.xs, 4);
    expect(AppflowySpacing.m, 8);
    expect(AppflowySpacing.xxl, 20);
    expect(AppflowyRadius.m, 8);
  });

  test('Typography 使用微软雅黑', () {
    final theme = AppflowyTheme.light();
    expect(theme.textTheme.titleLarge?.fontFamily, 'Microsoft YaHei UI');
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Microsoft YaHei UI');
  });
}
