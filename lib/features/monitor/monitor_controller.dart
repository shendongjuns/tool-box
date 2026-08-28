import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:toolbox/features/monitor/monitor_collector.dart';
import 'package:toolbox/features/monitor/monitor_models.dart';

/// 监控状态。
class MonitorState {
  const MonitorState({
    required this.running,
    required this.connectionId,
    required this.error,
    required this.latest,
    required this.history,
    this.serverInfo,
  });

  final bool running;
  final String? connectionId;
  final String? error;
  final MonitorMetrics? latest;
  final List<MonitorMetrics> history;

  /// 服务器基本信息（一次性查询结果）。
  final Map<String, String>? serverInfo;

  static const empty = MonitorState(
    running: false,
    connectionId: null,
    error: null,
    latest: null,
    history: [],
  );

  MonitorState copyWith({
    bool? running,
    String? connectionId,
    String? error,
    MonitorMetrics? latest,
    List<MonitorMetrics>? history,
    Map<String, String>? serverInfo,
  }) =>
      MonitorState(
        running: running ?? this.running,
        connectionId: connectionId ?? this.connectionId,
        error: error ?? this.error,
        latest: latest ?? this.latest,
        history: history ?? this.history,
        serverInfo: serverInfo ?? this.serverInfo,
      );
}

/// 系统监控控制器：每秒采集一次，保留最近 60 条历史。
///
/// 非 Riverpod Notifier（避免在未初始化的 provider 容器中使用抛错），
/// 作为普通 ChangeNotifier 由页面持有生命周期，与 SshSessionHandle 同模式。
class MonitorController extends ChangeNotifier {
  static const _historyLimit = 60;

  Timer? _timer;
  MonitorCollector? _collector;
  MonitorState _state = MonitorState.empty;

  /// 采集互斥锁：上次采集未完成时跳过本次，避免并发采集
  /// 在同一 SSH 连接上叠出大量 channel 导致服务器拒绝/超时。
  bool _collecting = false;

  MonitorState get state => _state;

  void _update(MonitorState next) {
    _state = next;
    notifyListeners();
  }

  /// 用已建立的 SSH 客户端开始监控（复用会话连接，不重复建连）。
  void startWithClient(SSHClient client) {
    if (_state.running) return;
    _collector = MonitorCollector(client);
    _update(_state.copyWith(running: true, error: null));
    _collect();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _collect());
  }

  /// 查询服务器基本信息，结果存入 state。
  Future<void> fetchServerInfo() async {
    final collector = _collector;
    if (collector == null) return;
    final info = await collector.fetchServerInfo();
    if (info == null) {
      _update(_state.copyWith(error: '服务器信息查询失败'));
      return;
    }
    _update(_state.copyWith(serverInfo: info));
  }

  /// 停止监控：只停止定时采集，**不断开会话连接**（连接由会话持有）。
  void stop() {
    _timer?.cancel();
    _timer = null;
    _collector = null;
    _update(MonitorState.empty);
  }

  /// 静默停止：清理定时器与采集器，**不触发通知**。
  ///
  /// 供监听者自身 dispose 期间调用（此时 notifyListeners 会对正在销毁的
  /// 元素触发 "widget tree was locked" 断言）。
  void stopSilently() {
    _timer?.cancel();
    _timer = null;
    _collector = null;
    _state = MonitorState.empty;
  }

  Future<void> _collect() async {
    if (_collecting || _collector == null) return;
    _collecting = true;
    try {
      final metrics = await _collector!.collect();
      if (!_state.running) return;
      // 若采集器记录了命令失败，展示诊断信息帮助排查。
      final diag = _collector!.lastError;
      final history = [..._state.history, metrics];
      if (history.length > _historyLimit) {
        history.removeRange(0, history.length - _historyLimit);
      }
      _update(_state.copyWith(
        latest: metrics,
        history: history,
        error: diag == null ? null : '采集异常：$diag',
      ));
    } catch (e) {
      _update(_state.copyWith(error: '采集失败：$e'));
    } finally {
      _collecting = false;
    }
  }
}
