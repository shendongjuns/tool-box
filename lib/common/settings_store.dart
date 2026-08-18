import 'dart:convert';
import 'dart:io';

import 'package:toolbox/common/app_data.dart';

/// 应用设置持久化：JSON 文件（`settings.json`），存放于安装目录 `data/` 下。
class SettingsStore {
  SettingsStore({String? dir}) : _dir = dir ?? AppDataDir.path;

  final String _dir;

  String get _filePath => '$_dir${Platform.pathSeparator}settings.json';

  /// 读取全部设置；文件缺失/损坏时返回空表，避免阻断启动。
  Map<String, dynamic> read() {
    try {
      final file = File(_filePath);
      if (!file.existsSync()) return {};
      final content = file.readAsStringSync();
      if (content.trim().isEmpty) return {};
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return {};
      return decoded;
    } on Exception {
      return {};
    }
  }

  /// 全量写入设置（覆盖）。
  void write(Map<String, dynamic> data) {
    try {
      final dir = Directory(_dir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File(_filePath).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(data),
      );
    } on Exception {
      // 写入失败不阻断界面（设置仅丢失于本次会话）。
    }
  }
}
