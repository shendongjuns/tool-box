import 'dart:async';

import 'package:flutter/material.dart';
import 'package:toolbox/common/app_log.dart';
import 'package:toolbox/common/settings_store.dart';
import 'package:toolbox/ui/window/app_tray.dart';
import 'package:window_manager/window_manager.dart';

/// 初始化应用窗口：系统标题栏、默认 1200×800、最小 900×600、居中显示。
Future<void> initAppWindow() async {
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1200, 800),
    minimumSize: Size(900, 600),
    center: true,
    title: 'ToolBox',
    titleBarStyle: TitleBarStyle.normal,
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
    await WindowGeometry.restore();
    WindowGeometry.watch();
    // 托盘图标与关窗拦截（内部失败会退化为「关闭即退出」）。
    await AppTray.init();
  });
}

/// 窗口**尺寸**与最大化状态的记忆（**不含位置**）。
///
/// 位置故意不记忆：桌面工具的期待是「打开就在眼前」。记住位置会在
/// 换显示器 / 拔掉外接屏 / 改分辨率之后把窗口开到看不见的地方或偏在角落，
/// 而这些场景在笔记本上非常常见。尺寸记忆没有这个副作用，所以只记尺寸，
/// 每次启动都把窗口**居中**显示。
///
/// 尺寸存进 `settings.json`（键 `window.size`），变更后防抖写盘；
/// 恢复时校验不小于最小限制，不合法就退回默认 1200×800。
abstract final class WindowGeometry {
  static const String _sizeKey = 'window.size';
  static const String _maximizedKey = 'window.maximized';

  /// 旧版本记录的是 `window.bounds`（含位置）；不再读取，并在下次写盘时清理掉。
  static const String _legacyBoundsKey = 'window.bounds';

  static const Size _defaultSize = Size(1200, 800);
  static const Size _minSize = Size(900, 600);

  static SettingsStore? _store;
  static Timer? _debounce;
  static _GeometryWatcher? _watcher;

  /// 恢复上次的窗口尺寸，并**居中**显示（窗口显示后调用）。
  static Future<void> restore() async {
    try {
      final store = _store ??= SettingsStore();
      final saved = store.read();
      final size = _parseSize(saved[_sizeKey]) ?? _defaultSize;
      await windowManager.setSize(size);
      // 始终居中：见类文档里「不记忆位置」的原因。
      await windowManager.center();
      if (saved[_maximizedKey] == true) {
        await windowManager.maximize();
      }
      // 落一次基线：即使这次用户没动窗口，也让文件里有一份可用尺寸，
      // 同时把遗留的 window.bounds 清掉。
      await saveNow();
    } catch (e) {
      AppLog.w('window', '恢复窗口尺寸失败（使用默认尺寸）：$e');
    }
  }

  /// 开始监听窗口尺寸变化并落盘。
  static void watch() {
    if (_watcher != null) return;
    _watcher = _GeometryWatcher(onChanged: _scheduleSave);
    windowManager.addListener(_watcher!);
  }

  /// 立即落盘（关窗或隐藏到托盘前调用）。
  ///
  /// 尺寸变更走的是 400ms 防抖，用户拖完窗口立刻点关闭时最后一次变更
  /// 还在防抖窗口里，必须先冲掉再隐藏。
  static Future<void> saveNow() async {
    _debounce?.cancel();
    await _save();
  }

  static void _scheduleSave() {
    _debounce?.cancel();
    // 拖拽 / 缩放过程中每帧都会触发，防抖后再写盘。
    _debounce = Timer(const Duration(milliseconds: 400), _save);
  }

  static Future<void> _save() async {
    try {
      final store = _store ??= SettingsStore();
      final maximized = await windowManager.isMaximized();
      final data = Map<String, dynamic>.from(store.read())
        ..remove(_legacyBoundsKey)
        ..[_maximizedKey] = maximized;

      // 最大化状态下 getSize() 返回的是「最大化后的尺寸」，记下来会导致
      // 下次以超大尺寸恢复，所以只在非最大化时更新尺寸。
      if (!maximized) {
        final size = await windowManager.getSize();
        if (size.width >= _minSize.width && size.height >= _minSize.height) {
          data[_sizeKey] = [size.width, size.height];
        }
      }
      store.write(data);
    } catch (e) {
      AppLog.w('window', '保存窗口尺寸失败：$e');
    }
  }

  static Size? _parseSize(Object? raw) {
    if (raw is! List || raw.length != 2) return null;
    final values = raw.map((e) => e is num ? e.toDouble() : null).toList();
    if (values.any((e) => e == null)) return null;
    final size = Size(values[0]!, values[1]!);
    if (size.width < _minSize.width || size.height < _minSize.height) {
      return null;
    }
    return size;
  }
}

/// 监听窗口缩放 / 最大化状态变化。
class _GeometryWatcher with WindowListener {
  _GeometryWatcher({required this.onChanged});

  final VoidCallback onChanged;

  @override
  void onWindowResize() => onChanged();

  @override
  void onWindowMaximize() => onChanged();

  @override
  void onWindowUnmaximize() => onChanged();

  // 关闭 / 最小化 / 失焦前也落一次盘：仅靠防抖，用户拖完窗口立刻关程序会丢。
  @override
  void onWindowBlur() => onChanged();

  @override
  void onWindowMinimize() => onChanged();

  @override
  void onWindowClose() => onChanged();
}

/// 让 Windows 原生窗口边框（标题栏 / 边框）跟随应用的明暗主题。
///
/// Flutter 只负责窗口内部的内容，系统边框由 Windows 绘制，
/// 必须通过 `windowManager.setBrightness` 显式同步，否则切到深色主题后
/// 标题栏仍是浅色。
class WindowBrightnessSync extends StatefulWidget {
  const WindowBrightnessSync({
    required this.brightness,
    required this.child,
    super.key,
  });

  /// 当前应当应用的亮度。
  final Brightness brightness;

  final Widget child;

  @override
  State<WindowBrightnessSync> createState() => _WindowBrightnessSyncState();
}

class _WindowBrightnessSyncState extends State<WindowBrightnessSync> {
  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(WindowBrightnessSync oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.brightness != widget.brightness) _sync();
  }

  void _sync() {
    // 平台调用是异步的，且窗口可能尚未就绪；失败时忽略，不影响界面。
    windowManager.setBrightness(widget.brightness).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
