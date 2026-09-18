/// 字节数的可读化格式（B / KB / MB / GB / TB）。
///
/// 全应用**只有这一处实现**。此前备份体积、监控速率、进程内存、连接信息、SFTP 文件大小
/// 各自写了一份几乎相同的换算，口径已经开始漂移（有的一档只有一位小数、有的到 GB 就截断、
/// 有的空值返回空串）。统一在这里之后，改刻度只需动一个地方，各处显示也不会再打架。
library;

/// 把字节数格式化成人类可读的文本。
///
/// - 小于 1 KB 按整数显示（`512 B`，不显示 `.0`）；
/// - 其余每档保留 [decimals] 位小数（默认 1 位）；
/// - 传入 `num` 是为了同时支持整数体积（文件大小）与浮点速率（网络上下行）。
String formatBytes(num bytes, {int decimals = 1}) {
  if (bytes < 1024) return '${bytes.round()} B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(decimals)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(decimals)} MB';
  }
  if (bytes < 1024 * 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(decimals)} GB';
  }
  return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(decimals)} TB';
}
