import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 传输方向。
enum TransferDirection { upload, download }

/// 传输状态。
enum TransferStatus { pending, running, done, failed, cancelled }

/// 单个传输任务。
class TransferTask {
  const TransferTask({
    required this.id,
    required this.fileName,
    required this.direction,
    required this.totalBytes,
    required this.transferredBytes,
    required this.status,
    this.error,
  });

  final String id;
  final String fileName;
  final TransferDirection direction;
  final int totalBytes;
  final int transferredBytes;
  final TransferStatus status;
  final String? error;

  /// 进度 0-1。
  double get progress =>
      totalBytes <= 0 ? 0 : (transferredBytes / totalBytes).clamp(0, 1);

  TransferTask copyWith({
    String? fileName,
    TransferDirection? direction,
    int? totalBytes,
    int? transferredBytes,
    TransferStatus? status,
    String? error,
  }) =>
      TransferTask(
        id: id,
        fileName: fileName ?? this.fileName,
        direction: direction ?? this.direction,
        totalBytes: totalBytes ?? this.totalBytes,
        transferredBytes: transferredBytes ?? this.transferredBytes,
        status: status ?? this.status,
        error: error ?? this.error,
      );
}

/// 传输任务列表（全局，跨会话共享）。
final transferTasksProvider =
    NotifierProvider<TransferController, List<TransferTask>>(
  TransferController.new,
);

int _transferSeq = 0;

class TransferController extends Notifier<List<TransferTask>> {
  /// 任务 id -> 取消通道（scp worker 的 cancelPort）。
  final Map<String, SendPort> _cancelPorts = {};

  @override
  List<TransferTask> build() => const [];

  /// 注册任务的取消通道。
  void setCancelPort(String id, SendPort port) {
    _cancelPorts[id] = port;
  }

  /// 终止任务（向 worker 发取消消息）。
  void cancel(String id) {
    _cancelPorts.remove(id)?.send(['cancel']);
  }

  /// 新增任务，返回任务 id。
  String add(
    String fileName,
    TransferDirection direction, {
    int totalBytes = 0,
  }) {
    final id = 't${DateTime.now().millisecondsSinceEpoch}-${_transferSeq++}';
    state = [
      ...state,
      TransferTask(
        id: id,
        fileName: fileName,
        direction: direction,
        totalBytes: totalBytes,
        transferredBytes: 0,
        status: TransferStatus.pending,
      ),
    ];
    return id;
  }

  /// 更新任务进度。
  void updateProgress(String id, int transferredBytes, {int? totalBytes}) {
    state = [
      for (final t in state)
        if (t.id == id)
          t.copyWith(
            transferredBytes: transferredBytes,
            totalBytes: totalBytes ?? t.totalBytes,
            status: TransferStatus.running,
          )
        else
          t,
    ];
  }

  /// 设置任务总量（下载时由 worker 回报文件大小）。
  void updateTotal(String id, int totalBytes) {
    state = [
      for (final t in state)
        if (t.id == id) t.copyWith(totalBytes: totalBytes) else t,
    ];
  }

  /// 标记完成/失败/取消。
  void finish(String id, TransferStatus status, {String? error}) {
    state = [
      for (final t in state)
        if (t.id == id) t.copyWith(status: status, error: error) else t,
    ];
  }

  /// 移除单个任务。
  void remove(String id) {
    state = state.where((t) => t.id != id).toList();
  }

  /// 清空已完成/失败任务。
  void clearFinished() {
    state = state
        .where((t) =>
            t.status == TransferStatus.pending ||
            t.status == TransferStatus.running)
        .toList();
  }
}
