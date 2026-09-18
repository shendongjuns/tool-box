import 'dart:io';

import 'package:toolbox/common/app_data.dart';
import 'package:toolbox/common/json_file_recovery.dart';
import 'package:toolbox/common/json_store_io.dart';

/// 应用设置持久化：JSON 文件（`settings.json`），存放于数据目录下。
///
/// 写入走 [JsonStoreIo.write]（原子替换 + 一版回滚），
/// 读取走 [JsonStoreIo.read]（损坏时自动回退上一版）。
class SettingsStore {
  SettingsStore({String? dir}) : _dir = dir ?? AppDataDir.path;

  static const String _tag = 'settings';

  final String _dir;

  String get _filePath => '$_dir${Platform.pathSeparator}settings.json';

  /// 读取全部设置；文件缺失/损坏时返回空表，避免阻断启动。
  Map<String, dynamic> read() {
    final result = JsonStoreIo.read(_filePath, tag: _tag);
    if (result.error != null) backupCorruptJsonFile(_filePath, result.error!);
    final data = result.data;
    return data is Map<String, dynamic> ? data : {};
  }

  /// 全量写入设置（原子替换）。返回是否成功。
  bool write(Map<String, dynamic> data) =>
      JsonStoreIo.write(_filePath, data, tag: _tag);
}
