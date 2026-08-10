import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeMode>(ThemeController.new);

/// 主题模式控制器：默认跟随系统，预留手动切换。
class ThemeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void setDark(bool dark) => state = dark ? ThemeMode.dark : ThemeMode.light;
}
