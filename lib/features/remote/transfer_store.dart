import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/common/app_data.dart';
import 'package:toolbox/common/json_file_recovery.dart';
import 'package:toolbox/common/json_store_io.dart';
import 'package:toolbox/features/remote/transfer_controller.dart';

final transferStoreProvider = Provider<TransferStore>((ref) => TransferStore());

/// 传输任务持久化：JSON 文件，存放于数据目录下。
///
/// 与其他 Store 一致：原子写入 + 损坏自动回退上一版 + 单条坏数据只跳过该条。
class TransferStore {
  TransferStore({String? dir}) : _dir = dir ?? AppDataDir.path;

  static const String _tag = 'transfer_tasks';

  final String _dir;

  String get _filePath => '$_dir${Platform.pathSeparator}transfer_tasks.json';

  List<TransferTask> load() {
    final result = JsonStoreIo.read(_filePath, tag: _tag);
    if (result.error != null) backupCorruptJsonFile(_filePath, result.error!);
    final data = result.data;
    if (data is! List) return [];
    return JsonStoreIo.parseList(data, TransferTask.fromJson, tag: _tag);
  }

  bool save(List<TransferTask> tasks) => JsonStoreIo.write(
    _filePath,
    tasks.map((e) => e.toJson()).toList(),
    tag: _tag,
  );
}
