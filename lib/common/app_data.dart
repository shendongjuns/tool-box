import 'dart:io';

import 'package:flutter/foundation.dart';

/// 应用数据目录：**优先**使用 exe 同级的 `user/`（便携、便于整体备份）。
///
/// 但「安装到 `C:\Program Files` 后以普通用户运行」这类情况下该目录不可写，
/// 而本应用是 x64 进程（不享受 Windows 的 UAC 文件虚拟化重定向），
/// 写入会直接抛 `ACCESS_DENIED`。此时**自动回退**到
/// `%APPDATA%\ToolBox\user`，并给出显式告警（见 [warning]），
/// 避免用户遇到「保存了、下次启动却全没了」这种无声数据丢失。
class AppDataDir {
  AppDataDir._();

  static String? _resolved;
  static bool _fallback = false;
  static String? _warning;

  /// 应用数据目录（配置/文件存放于此）。
  static String get path => _resolved ??= _resolve();

  /// 是否回退到了用户目录。
  static bool get isFallback => _fallback;

  /// 需要在启动时告知用户的问题；无问题为 null。
  static String? get warning {
    if (_resolved == null) init();
    return _warning;
  }

  /// 尽早调用一次完成目录探测（main 里在日志初始化之前调用）。
  static void init() => path;

  /// 测试专用：把数据目录固定到 [path]（传 null 恢复自动探测）。
  ///
  /// 备份功能会**整体替换数据目录**，测试必须能在临时目录上跑，
  /// 绝不能碰到真实数据。
  @visibleForTesting
  static void overridePath(String? path) {
    _resolved = path;
    _fallback = false;
    _warning = null;
  }

  static String get _portablePath =>
      '${File(Platform.resolvedExecutable).parent.path}'
      '${Platform.pathSeparator}user';

  /// `%APPDATA%\ToolBox\user`（取不到环境变量时退到系统临时目录）。
  static String get _fallbackPath {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return '$appData${Platform.pathSeparator}ToolBox'
          '${Platform.pathSeparator}user';
    }
    return '${Directory.systemTemp.path}${Platform.pathSeparator}ToolBox'
        '${Platform.pathSeparator}user';
  }

  static String _resolve() {
    final portable = _portablePath;
    if (_isWritable(portable)) return portable;

    final fallback = _fallbackPath;
    if (_isWritable(fallback)) {
      _fallback = true;
      _warning =
          '程序所在目录没有写入权限，数据已改存到：\n$fallback\n\n'
          '把程序放到有写权限的目录（例如用户目录下），数据就会回到程序目录旁边。';
      return fallback;
    }

    _fallback = true;
    _warning = '程序目录和用户目录都不可写，本次运行的改动（连接、设置等）在关闭后不会保存。';
    return portable;
  }

  /// 真实写一个探针文件来判断可写性——只看目录是否存在是不够的。
  static bool _isWritable(String dir) {
    final probePath = '$dir${Platform.pathSeparator}.write-probe';
    try {
      final directory = Directory(dir);
      if (!directory.existsSync()) directory.createSync(recursive: true);
      final probe = File(probePath);
      probe.writeAsStringSync('ok', flush: true);
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }
}
