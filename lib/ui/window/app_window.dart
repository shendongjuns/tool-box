import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 初始化应用窗口：系统标题栏、1200×800 居中、最小 900×600。
Future<void> initAppWindow() async {
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1200, 800),
    minimumSize: Size(900, 600),
    center: true,
    title: '工具箱',
    titleBarStyle: TitleBarStyle.normal,
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
