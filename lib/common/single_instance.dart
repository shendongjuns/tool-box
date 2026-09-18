import 'dart:io';

import 'package:toolbox/common/app_data.dart';
import 'package:toolbox/common/app_log.dart';

/// 单实例检测：用数据目录下的 `.instance.lock` 持有**非阻塞独占锁**。
///
/// 两个实例同时读写同一批 JSON 会互相覆盖（last-write-wins），甚至交错写坏，
/// 所以启动时先取证：拿不到锁就说明已经有实例在跑。
///
/// 这里不做「第二个实例直接退出」——那样用户会以为程序坏了；
/// 而是交给上层弹一次明确的告警（见 [StartupNotice]），让用户自己决定。
///
/// 进程退出（含被强杀）时操作系统会自动释放文件锁，不会留下死锁。
class SingleInstance {
  SingleInstance._();

  static RandomAccessFile? _lock;
  static bool _isFirst = true;

  /// 当前是否为唯一实例。
  static bool get isFirst => _isFirst;

  /// 主动释放锁（**只用于「重启应用」**）。
  ///
  /// 重启是「先拉起新进程、再退出自己」，如果不在拉起之前释放锁，
  /// 新进程会以为已有实例在运行而弹出多开告警。释放后到进程真正退出之间
  /// 有几十毫秒的窗口期，这期间理论上可以有第三个实例拿到锁——
  /// 相比「每次重启都误报多开」，这个代价可以接受。
  static void release() {
    try {
      _lock?.closeSync();
    } catch (_) {
      // 关不掉也无所谓：进程一退出系统会释放。
    }
    _lock = null;
  }

  /// 启动时调用一次。任何异常都不阻塞启动。
  static void acquire() {
    final directory = Directory(AppDataDir.path);
    if (!directory.existsSync()) directory.createSync(recursive: true);
    final path = '${directory.path}${Platform.pathSeparator}.instance.lock';

    // 「打不开锁文件」在 Windows 上通常意味着**另一个实例正持有独占锁**
    // （表现为 errno 5 拒绝访问），而不是我们没权限。这时必须按「已有实例」
    // 处理：错误地当成首个实例，会让两个进程同时写同一批 JSON 而**毫无提示**。
    // 唯一需要排除的是上一个实例刚被强杀、句柄尚未完全释放的短暂窗口，
    // 所以先重试几次再下结论。
    for (var attempt = 0; ; attempt++) {
      try {
        final file = File(path).openSync(mode: FileMode.write);
        try {
          // 非阻塞锁：已被占用时立刻抛 FileSystemException。
          file.lockSync(FileLock.exclusive);
          file.writeStringSync('$pid\n');
          file.flushSync();
          _lock = file; // 持有到进程结束，由系统自动释放
          _isFirst = true;
          return;
        } on FileSystemException {
          file.closeSync();
          _isFirst = false;
          AppLog.w('app', '检测到已有实例在运行（锁文件被占用）');
          return;
        }
      } on FileSystemException catch (e) {
        if (attempt < 2) {
          sleep(const Duration(milliseconds: 200));
          continue;
        }
        _isFirst = false;
        AppLog.w('app', '无法打开单实例锁文件，按「已有实例在运行」处理：$e');
        return;
      } catch (e) {
        _isFirst = true;
        AppLog.w('app', '单实例检测异常，按首个实例继续启动：$e');
        return;
      }
    }
  }
}
/// 启动期需要告知用户的问题（数据目录回退、多实例等）。
///
/// 这些信息在 `runApp` 之前就已确定，但要等界面搭好才能展示，
/// 所以先收集、由 ShellView 在首帧后统一弹一次。
class StartupNotice {
  StartupNotice._();

  static final List<String> _messages = [];

  static List<String> get messages => List.unmodifiable(_messages);

  static bool get hasAny => _messages.isNotEmpty;

  static void add(String message) {
    if (message.trim().isEmpty) return;
    _messages.add(message);
    AppLog.w('app', '启动告警：${message.replaceAll('\n', ' ')}');
  }

  static void clear() => _messages.clear();
}
