import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/ui/theme/forui_theme.dart';

void main() {
  test('浅色主题 FColors 映射精确', () {
    final theme = buildForuiTheme(Brightness.light);
    expect(theme.colors.background, const Color(0xFFFFFFFF));
    expect(theme.colors.foreground, const Color(0xFF21232A));
    expect(theme.colors.primary, const Color(0xFF0092D6));
    expect(theme.colors.secondary, const Color(0xFFE4E8F5));
    expect(theme.colors.muted, const Color(0xFFF8FAFF));
    expect(theme.colors.mutedForeground, const Color(0xFF989EB7));
    expect(theme.colors.border, const Color(0xFFE4E8F5));
    expect(theme.colors.destructive, const Color(0xFFE85D5D));
    expect(theme.colors.card, const Color(0xFFFFFFFF));
  });

  test('深色主题 FColors 映射精确', () {
    final theme = buildForuiTheme(Brightness.dark);
    expect(theme.colors.background, const Color(0xFF21232A));
    expect(theme.colors.foreground, const Color(0xFFF8FAFF));
    expect(theme.colors.primary, const Color(0xFF4EC1FF));
    expect(theme.colors.secondary, const Color(0xFF32343F));
    expect(theme.colors.muted, const Color(0xFF272930));
    expect(theme.colors.border, const Color(0xFF3D404F));
    expect(theme.colors.destructive, const Color(0xFFF27676));
    expect(theme.colors.card, const Color(0xFF21232A));
  });

  test('深浅主题 primaryForeground 为白', () {
    expect(buildForuiTheme(Brightness.light).colors.primaryForeground,
        const Color(0xFFFFFFFF));
    expect(buildForuiTheme(Brightness.dark).colors.primaryForeground,
        const Color(0xFFFFFFFF));
  });
}
