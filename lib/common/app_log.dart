import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:toolbox/common/app_data.dart';
import 'package:toolbox/common/app_meta.dart';

/// 轻量落盘日志：`<数据目录>/logs/app.log`。
///
/// 只记录「用户报障时需要的关键节点」——连接/采集/传输失败、数据读写异常、
/// 启动告警。量很小，因此用同步追加，不需要维护 IOSink 生命周期。
///
/// 单文件超过 1 MB 时轮转，保留最近 3 个历史文件（`app.log.1`~`.3`）。
class AppLog {
  AppLog._();

  static const int _maxBytes = 1024 * 1024;
  static const int _keepFiles = 3;

  /// 每写多少行检查一次体积（不必每行都 stat）。
  static const int _rotateCheckEvery = 200;

  static String? _logPath;
  static bool _ready = false;
  static int _writes = 0;

  /// 是否已成功落盘（false 时只输出到控制台）。
  static bool get isReady => _ready;

  /// 日志文件路径（用于「打开日志」等入口）。
  static String? get path => _logPath;

  /// 在数据目录确定之后调用一次。失败则降级为「只在控制台输出」，不影响启动。
  static void init({String? dir}) {
    try {
      final directory = Directory(
        dir ?? '${AppDataDir.path}${Platform.pathSeparator}logs',
      );
      if (!directory.existsSync()) directory.createSync(recursive: true);
      _logPath = '${directory.path}${Platform.pathSeparator}app.log';
      _ready = true;
      _rotateIfNeeded();
      i('app', '==== 启动 $appName v$appVersion ====');
      if (AppDataDir.isFallback) {
        w('app', '数据目录不可写，已回退到：${AppDataDir.path}');
      }
    } catch (_) {
      _ready = false;
    }
  }

  static void i(String tag, String message) => _write('INFO ', tag, message);

  static void w(String tag, String message) => _write('WARN ', tag, message);

  static void e(String tag, String message, [Object? error]) =>
      _write('ERROR', tag, error == null ? message : '$message | $error');

  static void _write(String level, String tag, String message) {
    final line =
        '${DateTime.now().toIso8601String()} $level [$tag] $message\n';
    if (!_ready) {
      debugPrint(line.trimRight());
      return;
    }
    try {
      File(_logPath!).writeAsStringSync(line, mode: FileMode.append, flush: true);
      if (++_writes % _rotateCheckEvery == 0) _rotateIfNeeded();
    } catch (_) {
      // 写日志失败绝不能影响业务流程。
      debugPrint(line.trimRight());
    }
  }

  /// 体积超限时轮转：app.log.3 丢弃，其余依次后移，当前文件成为 app.log.1。
  static void _rotateIfNeeded() {
    final current = _logPath;
    if (current == null) return;
    try {
      final file = File(current);
      if (!file.existsSync() || file.lengthSync() < _maxBytes) return;
      for (var i = _keepFiles; i >= 1; i--) {
        final source = i == 1 ? file : File('$current.${i - 1}');
        if (!source.existsSync()) continue;
        final target = File('$current.$i');
        if (target.existsSync()) target.deleteSync();
        source.renameSync(target.path);
      }
    } catch (_) {
      // 轮转失败就继续往当前文件写，不能因此中断。
    }
  }
}
