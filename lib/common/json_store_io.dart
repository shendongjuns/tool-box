import 'dart:convert';
import 'dart:io';

import 'package:toolbox/common/app_log.dart';

/// JSON 数据文件的原子读写（含一版回滚）。
///
/// **为什么不能直接覆写**：`writeAsStringSync` 直接写目标文件时，若进程在
/// 写入途中被强杀/断电，文件会只剩半个 JSON；下次启动就只能判定「损坏」→
/// 回退空数据 → 用户全部数据消失。
///
/// 写入顺序保证任何时刻主文件都是完整的：
/// 1. 写临时文件 `<file>.tmp`；
/// 2. 现有文件转存为 `<file>.prev`（上一版，可回滚）；
/// 3. `rename` 原子替换主文件。
///
/// 读取时主文件缺失/损坏会自动回退 `.prev`，把「人工抢救」变成自动恢复。
class JsonStoreIo {
  JsonStoreIo._();

  static const String tmpSuffix = '.tmp';
  static const String prevSuffix = '.prev';

  /// 「导入备份」把数据目录整体换掉之后置位。
  ///
  /// 此时内存里的设置/连接还是**导入之前**的那份，任何一次落盘都会把刚导入的
  /// 数据覆盖回去（典型场景：导完不重启，随手拖一下窗口就把 settings.json 写回了）。
  /// 所以导完之后本进程一律不再写数据，直到用户重启。
  static bool frozen = false;

  /// 原子写入。返回是否成功（失败已记日志，调用方无需再弹错）。
  static bool write(String path, Object? data, {required String tag}) {
    if (frozen) {
      AppLog.w(tag, '已导入备份且尚未重启，本次写入被跳过：$path');
      return false;
    }
    final text = const JsonEncoder.withIndent('  ').convert(data);
    final tmp = File('$path$tmpSuffix');
    try {
      final parent = Directory(
        path.substring(0, path.lastIndexOf(Platform.pathSeparator)),
      );
      if (!parent.existsSync()) parent.createSync(recursive: true);
      tmp.writeAsStringSync(text, flush: true);
    } on FileSystemException catch (e) {
      AppLog.e(tag, '写入临时文件失败，本次数据未保存：$path', e);
      _tryDelete(tmp);
      return false;
    }

    final target = File(path);
    try {
      if (target.existsSync()) {
        final prev = File('$path$prevSuffix');
        _tryDelete(prev);
        target.renameSync(prev.path);
      }
      tmp.renameSync(path);
      return true;
    } on FileSystemException catch (e) {
      // 极端情况（目标被外部进程/杀软占用）：退回直接覆写，
      // 虽然失去原子性，但比「彻底不保存」更符合用户预期。
      AppLog.w(tag, '原子替换失败，退回直接写入：$path（$e）');
      try {
        tmp.copySync(path);
        _tryDelete(tmp);
        return true;
      } on FileSystemException catch (e2) {
        AppLog.e(tag, '写入数据文件失败，本次数据未保存：$path', e2);
        _tryDelete(tmp);
        return false;
      }
    }
  }

  /// 读取并解析：主文件优先，缺失或损坏时自动回退 `.prev`。
  static JsonReadResult read(String path, {required String tag}) {
    final primary = _readRaw(path);
    if (primary == null || primary.trim().isEmpty) {
      return const JsonReadResult(data: null);
    }

    final (data, error) = _decode(primary);
    if (error == null) return JsonReadResult(data: data);

    // 主文件损坏 → 先试上一版，能救回来就不用让用户面对空数据。
    final prevPath = '$path$prevSuffix';
    final prev = _readRaw(prevPath);
    if (prev != null && prev.trim().isNotEmpty) {
      final (prevData, prevError) = _decode(prev);
      if (prevError == null) {
        AppLog.w(tag, '主文件损坏，已自动回退上一版：$path → $prevPath');
        return JsonReadResult(data: prevData, fallback: true, error: error);
      }
    }

    AppLog.e(tag, '数据文件损坏且无可回退版本：$path', error);
    return JsonReadResult(data: null, error: error);
  }

  /// 逐条解析 JSON 数组：**跳过坏条目而不是废弃整份文件**。
  ///
  /// 一条记录的字段类型不对（手工改过、旧版本残留）不应导致其余完好数据
  /// 全部消失——这里只跳过它并记录日志。
  static List<T> parseList<T>(
    List<dynamic> raw,
    T? Function(Map<String, dynamic> json) parse, {
    required String tag,
  }) {
    final result = <T>[];
    var skipped = 0;
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) {
        skipped++;
        continue;
      }
      try {
        final parsed = parse(entry);
        if (parsed != null) result.add(parsed);
      } catch (e) {
        skipped++;
        AppLog.w(tag, '跳过无法解析的数据条目：$e');
      }
    }
    if (skipped > 0) {
      AppLog.w(tag, '共跳过 $skipped 条无法解析的数据（其余 ${result.length} 条已正常载入）');
    }
    return result;
  }

  /// 返回 (已解码对象, 错误描述)；错误非空表示不是合法 JSON。
  static (Object?, String?) _decode(String text) {
    try {
      return (jsonDecode(text), null);
    } catch (e) {
      return (null, '$e');
    }
  }

  static String? _readRaw(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      return file.readAsStringSync();
    } catch (e) {
      AppLog.w('store', '读取文件失败：$path（$e）');
      return null;
    }
  }

  static void _tryDelete(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // 删除失败不影响主流程（临时文件会在下次写入时被覆盖）。
    }
  }
}

/// [JsonStoreIo.read] 的返回：已解码数据 + 是否用了回退版本 + 错误描述。
class JsonReadResult {
  const JsonReadResult({required this.data, this.fallback = false, this.error});

  /// 已解码的 JSON；null 表示文件不存在或不可恢复。
  final Object? data;

  /// 数据是否来自 `.prev` 回退版本。
  final bool fallback;

  /// 主文件解析失败的描述（用于备份命名/日志）。
  final String? error;
}
