import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/common/settings_store.dart';

final settingsStoreProvider = Provider<SettingsStore>((ref) => SettingsStore());

final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeMode>(ThemeController.new);

/// 主题模式控制器：启动读取持久化配置，变更立即保存到 `user/settings.json`。
class ThemeController extends Notifier<ThemeMode> {
  static const _themeModeKey = 'themeMode';

  @override
  ThemeMode build() {
    final saved =
        ref.watch(settingsStoreProvider).read()[_themeModeKey] as String?;
    return _parseThemeMode(saved);
  }

  /// 直接设置主题模式并持久化。
  void setMode(ThemeMode mode) {
    state = mode;
    _save();
  }

  /// 循环切换：跟随系统 → 浅色 → 深色 → 跟随系统。
  void cycle() {
    setMode(switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    });
  }

  void _save() {
    final store = ref.read(settingsStoreProvider);
    // 合并写入，保留其他设置项。
    store.write({...store.read(), _themeModeKey: state.name});
  }

  static ThemeMode _parseThemeMode(String? raw) {
    for (final mode in ThemeMode.values) {
      if (mode.name == raw) return mode;
    }
    return ThemeMode.system;
  }
}
