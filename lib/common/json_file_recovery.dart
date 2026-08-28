import 'dart:io';

import 'package:flutter/foundation.dart';

/// 读取 JSON 数据文件失败时的兜底：把损坏文件改名为 `*.corrupt-bak`
/// 留底（不静默覆盖/删除用户数据），便于事后找回或排查；下次启动
/// 按新文件缺失处理，不会反复在同一坏文件上失败。
void backupCorruptJsonFile(String path, Object error) {
  try {
    final file = File(path);
    if (file.existsSync()) {
      file.rename('$path.corrupt-bak');
    }
    debugPrint('数据文件损坏，已备份为 $path.corrupt-bak：$error');
  } catch (_) {
    // 备份失败不影响"回退为空数据"的主流程。
  }
}
