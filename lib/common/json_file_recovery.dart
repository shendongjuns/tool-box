import 'dart:io';

import 'package:toolbox/common/app_log.dart';

/// 读取 JSON 数据文件失败时的兜底：把损坏文件改名留底
/// （`<原名>_yyyyMMdd-HHmmss.corrupt-bak`），**不静默覆盖/删除**用户数据，
/// 便于事后找回或排查；下次启动按「文件缺失」处理，不会反复在同一坏文件上失败。
///
/// 文件名带时间戳：同一路径第二次损坏时不会因为「目标名已存在」而备份失败
/// （旧实现用固定名，第二次损坏的备份会被静默吞掉）。
///
/// 返回备份文件路径；未备份（文件不存在或备份失败）返回 null。
String? backupCorruptJsonFile(String path, Object error) {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    final backupPath = _uniqueBackupPath(path);
    file.renameSync(backupPath);
    AppLog.e('store', '数据文件损坏，已备份为 $backupPath', error);
    return backupPath;
  } catch (e) {
    AppLog.e('store', '损坏数据文件备份失败：$path', e);
    return null;
  }
}

/// 生成一个尚未被占用的备份路径。
///
/// 时间戳精确到**毫秒**，并且仍然撞名时继续追加序号：同一毫秒内连续两次
/// 损坏（例如用户短时间反复改坏同一个文件）也必须各留一份底，
/// 否则后一次备份会因「目标已存在」而被静默吞掉（旧实现只到秒，已实际踩到）。
String _uniqueBackupPath(String path) {
  final stamp = _timestamp();
  final base = '${path}_$stamp.corrupt-bak';
  if (!File(base).existsSync()) return base;
  for (var n = 1; ; n++) {
    final candidate = '${path}_$stamp-$n.corrupt-bak';
    if (!File(candidate).existsSync()) return candidate;
  }
}

String _timestamp() {
  final now = DateTime.now();
  String pad(int v, int width) => v.toString().padLeft(width, '0');
  return '${now.year}${pad(now.month, 2)}${pad(now.day, 2)}'
      '-${pad(now.hour, 2)}${pad(now.minute, 2)}${pad(now.second, 2)}'
      '-${pad(now.millisecond, 3)}';
}
