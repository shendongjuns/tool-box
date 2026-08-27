import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/ui/theme/forui_theme.dart';

void main() {
  test('浅色主题 FColors 映射精确', () {
    final theme = buildForuiTheme(Brightness.light);
    expect(theme.colors.background, const Color(0xFFFFFFFF));
    expect(theme.colors.foreground, const Color(0xFF302D42));
    expect(theme.colors.primary, const Color(0xFF7857C8));
    expect(theme.colors.secondary, const Color(0xFFE8E4EF));
    expect(theme.colors.muted, const Color(0xFFF8F7FC));
    expect(theme.colors.mutedForeground, const Color(0xFF9C97AC));
    expect(theme.colors.border, const Color(0xFFE8E4EF));
    expect(theme.colors.destructive, const Color(0xFFDF6D7D));
    expect(theme.colors.card, const Color(0xFFFFFFFF));
  });

  test('深色主题 FColors 映射精确', () {
    final theme = buildForuiTheme(Brightness.dark);
    expect(theme.colors.background, const Color(0xFF272634));
    expect(theme.colors.foreground, const Color(0xFFE9E6F1));
    expect(theme.colors.primary, const Color(0xFFA889EF));
    expect(theme.colors.secondary, const Color(0xFF373548));
    expect(theme.colors.muted, const Color(0xFF2B2A39));
    expect(theme.colors.border, const Color(0xFF373548));
    expect(theme.colors.destructive, const Color(0xFFE8808F));
    expect(theme.colors.card, const Color(0xFF272634));
  });

  test('深浅主题 primaryForeground 为白', () {
    expect(buildForuiTheme(Brightness.light).colors.primaryForeground,
        const Color(0xFFFFFFFF));
    expect(buildForuiTheme(Brightness.dark).colors.primaryForeground,
        const Color(0xFFFFFFFF));
  });
}
