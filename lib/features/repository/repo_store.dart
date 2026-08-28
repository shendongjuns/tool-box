import 'dart:convert';
import 'dart:io';

import 'package:toolbox/common/app_data.dart';
import 'package:toolbox/common/json_file_recovery.dart';
import 'package:toolbox/features/repository/repo_models.dart';

/// 仓库数据持久化：JSON 文件，存放于安装目录。
class RepoStore {
  RepoStore({String? dir}) : _dir = dir ?? AppDataDir.path;

  final String _dir;

  String get _filePath => '$_dir${Platform.pathSeparator}repo_groups.json';

  List<RepoGroup> load() {
    try {
      final file = File(_filePath);
      if (!file.existsSync()) return [];
      final content = file.readAsStringSync();
      if (content.trim().isEmpty) return [];
      final decoded = jsonDecode(content);
      if (decoded is! List) return [];
      return decoded
          .map((e) => RepoGroup.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // 文件缺失/损坏时回退为空列表，避免阻断启动；损坏文件改名留底。
      backupCorruptJsonFile(_filePath, e);
      return [];
    }
  }

  void save(List<RepoGroup> groups) {
    try {
      final dir = Directory(_dir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File(_filePath).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(
          groups.map((e) => e.toJson()).toList(),
        ),
      );
    } on Exception {
      // 写入失败不阻断界面（数据仅丢失于本次会话）。
    }
  }
}
