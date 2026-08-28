import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/common/app_data.dart';
import 'package:toolbox/common/json_file_recovery.dart';
import 'package:toolbox/features/remote/transfer_controller.dart';

final transferStoreProvider = Provider<TransferStore>((ref) => TransferStore());

/// 传输任务持久化：JSON 文件，存放于 `user/` 目录。
///
/// 复用 RemoteStore 的模板：文件缺失/损坏时回退空列表，写入失败静默忽略。
class TransferStore {
  TransferStore({String? dir}) : _dir = dir ?? AppDataDir.path;

  final String _dir;

  String get _filePath => '$_dir${Platform.pathSeparator}transfer_tasks.json';

  List<TransferTask> load() {
    try {
      final file = File(_filePath);
      if (!file.existsSync()) return [];
      final content = file.readAsStringSync();
      if (content.trim().isEmpty) return [];
      final decoded = jsonDecode(content);
      if (decoded is! List) return [];
      return decoded
          .map((e) => TransferTask.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // 损坏文件（含解析类型错误）改名留底，回退空列表。
      backupCorruptJsonFile(_filePath, e);
      return [];
    }
  }

  void save(List<TransferTask> tasks) {
    try {
      final dir = Directory(_dir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File(_filePath).writeAsStringSync(
        const JsonEncoder.withIndent('  ')
            .convert(tasks.map((e) => e.toJson()).toList()),
      );
    } on Exception {
      // 写入失败不阻断界面。
    }
  }
}
