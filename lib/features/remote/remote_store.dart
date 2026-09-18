import 'dart:io';

import 'package:toolbox/common/app_data.dart';
import 'package:toolbox/common/json_file_recovery.dart';
import 'package:toolbox/common/json_store_io.dart';
import 'package:toolbox/features/remote/remote_models.dart';

/// SSH 连接信息持久化：JSON 文件，存放于数据目录下。
///
/// - 写入走 [JsonStoreIo.write]：原子替换 + 保留上一版，进程被强杀也不会写坏；
/// - 读取走 [JsonStoreIo.read] + [JsonStoreIo.parseList]：
///   主文件损坏时自动回退上一版，**单条记录坏掉只跳过它**，不拖垮其余连接。
class RemoteStore {
  RemoteStore({String? dir}) : _dir = dir ?? AppDataDir.path;

  static const String _tag = 'ssh_connections';

  final String _dir;

  String get _filePath => '$_dir${Platform.pathSeparator}ssh_connections.json';

  List<SshConnection> load() {
    final result = JsonStoreIo.read(_filePath, tag: _tag);
    if (result.error != null) backupCorruptJsonFile(_filePath, result.error!);
    final data = result.data;
    if (data is! List) return [];
    return JsonStoreIo.parseList(data, SshConnection.fromJson, tag: _tag);
  }

  bool save(List<SshConnection> connections) => JsonStoreIo.write(
    _filePath,
    connections.map((e) => e.toJson()).toList(),
    tag: _tag,
  );
}
