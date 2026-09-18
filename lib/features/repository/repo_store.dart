import 'dart:io';

import 'package:toolbox/common/app_data.dart';
import 'package:toolbox/common/json_file_recovery.dart';
import 'package:toolbox/common/json_store_io.dart';
import 'package:toolbox/features/repository/repo_models.dart';

/// 仓库数据持久化：JSON 文件，存放于数据目录下。
///
/// 写入原子替换、读取损坏自动回退上一版、单条坏数据只跳过该条
/// （详见 [JsonStoreIo]）。
class RepoStore {
  RepoStore({String? dir}) : _dir = dir ?? AppDataDir.path;

  static const String _tag = 'repo_groups';

  final String _dir;

  String get _filePath => '$_dir${Platform.pathSeparator}repo_groups.json';

  List<RepoGroup> load() {
    final result = JsonStoreIo.read(_filePath, tag: _tag);
    if (result.error != null) backupCorruptJsonFile(_filePath, result.error!);
    final data = result.data;
    if (data is! List) return [];
    return JsonStoreIo.parseList(data, RepoGroup.fromJson, tag: _tag);
  }

  bool save(List<RepoGroup> groups) => JsonStoreIo.write(
    _filePath,
    groups.map((e) => e.toJson()).toList(),
    tag: _tag,
  );
}
