import 'dart:convert';
import 'dart:io';

import 'package:toolbox/common/app_data.dart';
import 'package:toolbox/features/remote/remote_models.dart';

/// SSH 连接信息持久化：JSON 文件，存放于安装目录 `data/` 下。
class RemoteStore {
  RemoteStore({String? dir}) : _dir = dir ?? AppDataDir.path;

  final String _dir;

  String get _filePath => '$_dir${Platform.pathSeparator}ssh_connections.json';

  List<SshConnection> load() {
    try {
      final file = File(_filePath);
      if (!file.existsSync()) return [];
      final content = file.readAsStringSync();
      if (content.trim().isEmpty) return [];
      final decoded = jsonDecode(content);
      if (decoded is! List) return [];
      return decoded
          .map((e) => SshConnection.fromJson(e as Map<String, dynamic>))
          .toList();
    } on Exception {
      // 文件缺失/损坏时回退为空列表，避免阻断启动。
      return [];
    }
  }

  void save(List<SshConnection> connections) {
    try {
      final dir = Directory(_dir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File(_filePath).writeAsStringSync(
        const JsonEncoder.withIndent('  ')
            .convert(connections.map((e) => e.toJson()).toList()),
      );
    } on Exception {
      // 写入失败不阻断界面（数据仅丢失于本次会话）。
    }
  }
}
