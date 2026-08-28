import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/features/remote/transfer_store.dart';

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'direction': direction.name,
        'totalBytes': totalBytes,
        'transferredBytes': transferredBytes,
        'status': status.name,
        'error': error,
      };

  factory TransferTask.fromJson(Map<String, dynamic> json) => TransferTask(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        direction: _directionFrom(json['direction'] as String?),
        totalBytes: json['totalBytes'] as int? ?? 0,
        transferredBytes: json['transferredBytes'] as int? ?? 0,
        status: _statusFrom(json['status'] as String?),
        error: json['error'] as String?,
      );

  static TransferDirection _directionFrom(String? name) =>
      TransferDirection.values.asNameMap()[name] ?? TransferDirection.upload;

  static TransferStatus _statusFrom(String? name) =>
      TransferStatus.values.asNameMap()[name] ?? TransferStatus.failed;
}

/// 传输任务列表（全局，跨会话共享）。
final transferTasksProvider =
    NotifierProvider<TransferController, List<TransferTask>>(
  TransferController.new,
);

int _transferSeq = 0;

class TransferController extends Notifier<List<TransferTask>> {
  /// 任务 id -> 取消通道（传输 worker 的 cancelPort）。
  final Map<String, SendPort> _cancelPorts = {};

  @override
  List<TransferTask> build() {
    final loaded = ref.watch(transferStoreProvider).load();
    if (loaded.isEmpty) return const [];
    // 重启后无 worker 运行：把未完成任务标为失败，避免出现永远"传输中"。
    return [
      for (final t in loaded)
        if (t.status == TransferStatus.pending ||
            t.status == TransferStatus.running)
          t.copyWith(status: TransferStatus.failed, error: '应用重启，传输中断')
        else
          t,
    ];
  }

  void _persist() => ref.read(transferStoreProvider).save(state);

  /// 注册任务的取消通道。
  void setCancelPort(String id, SendPort port) {
    _cancelPorts[id] = port;
  }

  /// 标记任务开始（worker 开始传输时调用，状态置 running）。
  void start(String id) {
    state = [
      for (final t in state)
        if (t.id == id) t.copyWith(status: TransferStatus.running) else t,
    ];
    _persist();
  }

  /// 终止任务：立即标记为取消 + 通知 worker 中断传输。
  void cancel(String id) {
    // 立即标记状态（用户取消即时生效，不依赖 worker 响应）。
    state = [
      for (final t in state)
        if (t.id == id)
          t.copyWith(status: TransferStatus.cancelled)
        else
          t,
    ];
    // 通知 worker 中断（若还在运行）。
    _cancelPorts[id]?.send(['cancel']);
    _cancelPorts.remove(id);
    _persist();
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
    _persist();
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
            // 已结束（取消/失败）的任务不被迟到的进度消息复活为 running。
            status: t.status == TransferStatus.pending ||
                    t.status == TransferStatus.running
                ? TransferStatus.running
                : t.status,
          )
        else
          t,
    ];
    _persist();
  }

  /// 设置任务总量（下载时由 worker 回报文件大小）。
  void updateTotal(String id, int totalBytes) {
    state = [
      for (final t in state)
        if (t.id == id) t.copyWith(totalBytes: totalBytes) else t,
    ];
    _persist();
  }

  /// 标记完成/失败/取消。
  void finish(String id, TransferStatus status, {String? error}) {
    state = [
      for (final t in state)
        if (t.id == id) t.copyWith(status: status, error: error) else t,
    ];
    // 任务结束后清理取消通道（不再需要）。
    _cancelPorts.remove(id);
    _persist();
  }

  /// 移除单个任务。
  void remove(String id) {
    state = state.where((t) => t.id != id).toList();
    _persist();
  }

  /// 清空已完成/失败任务。
  void clearFinished() {
    state = state
        .where((t) =>
            t.status == TransferStatus.pending ||
            t.status == TransferStatus.running)
        .toList();
    _persist();
  }
}
