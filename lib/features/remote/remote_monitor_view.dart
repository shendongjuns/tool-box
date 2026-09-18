part of 'remote_view.dart';

// 监控视图（状态卡片 / 实时折线 / TOP 进程）。
//
// 从 remote_view.dart 拆出：远程页原本 2700+ 行，混着连接面板、会话、终端、
// 文件、监控五层职责；监控这一块自成体系（含自绘折线图），单独成文件便于定位。
// 用 part 而不是独立库：这些类都是库私有的（`_` 前缀），part 能保持封装不被扩大。

class _MonitorView extends ConsumerStatefulWidget {
  const _MonitorView({required this.controller, required this.handle});

  final MonitorController controller;
  final SshSessionHandle handle;

  @override
  ConsumerState<_MonitorView> createState() => _MonitorViewState();
}

class _MonitorViewState extends ConsumerState<_MonitorView> {
  @override
  void initState() {
    super.initState();
    widget.handle.status.addListener(_maybeStart);
    // 延迟到帧后启动：initState 期间同步 notifyListeners 会触发
    // "setState() called during build"（标题栏 ListenableBuilder 正被构建）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
  }

  @override
  void dispose() {
    widget.handle.status.removeListener(_maybeStart);
    // 收起/隐藏监控面板时本视图销毁，同时停止采集（显示时重建自动重启）。
    // 用静默停止：dispose 期间 notify 会触发 "widget tree was locked" 断言。
    widget.controller.stopSilently();
    super.dispose();
  }

  /// 连接就绪后自动开始监控（只启动一次）。
  void _maybeStart() {
    if (!widget.handle.isConnected) return;
    if (widget.controller.state.running) return;
    final client = widget.handle.client;
    if (client == null) return;
    widget.controller.startWithClient(client);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        final latest = state.latest;

        return ListView(
          padding: const EdgeInsets.all(AppLayout.gapMd),
          children: [
            // 采集异常/诊断：醒目提示条。
            if (state.error != null) ...[
              const SizedBox(height: AppLayout.gapSm),
              Container(
                padding: const EdgeInsets.all(AppLayout.gapSm),
                decoration: BoxDecoration(
                  color: context.theme.colors.muted,
                  borderRadius: context.theme.style.borderRadius.sm,
                ),
                child: Text(
                  state.error!,
                  style: context.theme.typography.body.xs.copyWith(color: context.theme.colors.destructive),
                ),
              ),
            ],
            const SizedBox(height: AppLayout.gapSm),
            if (latest == null)
              SizedBox(
                height: 120,
                child: Center(
                  child: Text(
                    state.running ? '正在采集…' : '监控已停止',
                    style: context.theme.typography.body.xs.copyWith(color: context.theme.colors.mutedForeground),
                  ),
                ),
              )
            else ...[
              // 四张独立趋势图（CPU / 内存 / 下载 / 上传）。
              _TrendGrid(history: state.history),
              const SizedBox(height: AppLayout.gapSm),
              // GPU 状态卡（有 GPU 数据时显示）。
              if (latest.gpus.isNotEmpty) ...[
                _GpuRow(history: state.history),
                const SizedBox(height: AppLayout.gapSm),
              ],
              // 华为昇腾 NPU 趋势（有 NPU 数据时显示）。
              if (latest.npus.isNotEmpty) ...[
                _NpuRow(history: state.history),
                const SizedBox(height: AppLayout.gapSm),
              ],
              // TOP 进程（固定高度，内部滚动）。
              SizedBox(
                height: 210,
                child: _MonitorProcessList(
                  processes: latest.processes,
                  cpuCores: latest.cpuCores,
                  memTotalBytes: latest.memTotalBytes,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 服务器信息弹窗中的一行：标签 + 值。
class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppLayout.gapXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: context.theme.typography.body.xs.copyWith(color: p.mutedForeground),
            ),
          ),
          Expanded(
            child: Text(value, style: context.theme.typography.body.xs),
          ),
        ],
      ),
    );
  }
}

/// 四张独立实时趋势图：CPU / 内存 / 下载 / 上传（2×2）。
class _TrendGrid extends StatelessWidget {
  const _TrendGrid({required this.history});

  final List<MonitorMetrics> history;

  @override
  Widget build(BuildContext context) {
    final latest = history.isEmpty ? null : history.last;
    final rxMax = history.fold<double>(
      0,
      (m, h) => m > h.netRxBytesPerSec ? m : h.netRxBytesPerSec,
    );
    final txMax = history.fold<double>(
      0,
      (m, h) => m > h.netTxBytesPerSec ? m : h.netTxBytesPerSec,
    );

    return Row(
      children: [
        Expanded(
          child: _TrendCard(
            label: 'CPU',
            color: _chartCpu,
            value: latest == null ? '-' : '${latest.cpuPercent.toStringAsFixed(1)}%',
            values: [for (final m in history) m.cpuPercent],
            unitMax: 100,
          ),
        ),
        const SizedBox(width: AppLayout.gapSm),
        Expanded(
          child: _TrendCard(
            label: '内存',
            color: _chartMemory,
            value: latest == null
                ? '-'
                : '${(latest.memPercent * 100).toStringAsFixed(0)}%',
            values: [for (final m in history) m.memPercent * 100],
            unitMax: 100,
          ),
        ),
        const SizedBox(width: AppLayout.gapSm),
        Expanded(
          child: _TrendCard(
            label: '下载',
            color: _chartDownload,
            value: latest == null ? '-' : '${formatBytes(latest.netRxBytesPerSec)}/s',
            values: [
              for (final m in history)
                rxMax > 0 ? m.netRxBytesPerSec / rxMax * 100 : 0,
            ],
            unitMax: 100,
          ),
        ),
        const SizedBox(width: AppLayout.gapSm),
        Expanded(
          child: _TrendCard(
            label: '上传',
            color: _chartUpload,
            value: latest == null ? '-' : '${formatBytes(latest.netTxBytesPerSec)}/s',
            values: [
              for (final m in history)
                txMax > 0 ? m.netTxBytesPerSec / txMax * 100 : 0,
            ],
            unitMax: 100,
          ),
        ),
      ],
    );
  }

}

/// GPU 趋势：每个 GPU 一张利用率趋势卡（含温度/功耗）。
class _GpuRow extends StatelessWidget {
  const _GpuRow({required this.history});

  final List<MonitorMetrics> history;

  @override
  Widget build(BuildContext context) {
    final latest = history.isEmpty ? null : history.last;
    if (latest == null || latest.gpus.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < latest.gpus.length; i++) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppLayout.gapSm),
            child: Text(
              'GPU ${i + 1}：${latest.gpus[i].name}'
              '${latest.gpus[i].tempC > 0 ? ' · ${latest.gpus[i].tempC.toStringAsFixed(0)}°C' : ''}',
              style: context.theme.typography.body.xs.copyWith(fontWeight: FontWeight.w600, color: context.theme.colors.mutedForeground),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _GpuTrend(
                  label: '利用率',
                  color: const Color(0xFF9C27B0),
                  value:
                      '${latest.gpus[i].utilPercent.toStringAsFixed(0)}%',
                  series: [
                    for (final m in history)
                      if (i < m.gpus.length) m.gpus[i].utilPercent,
                  ],
                  unitMax: 100,
                ),
              ),
              const SizedBox(width: AppLayout.gapSm),
              Expanded(
                child: _GpuTrend(
                  label: '功耗',
                  color: const Color(0xFFEF6C00),
                  value: latest.gpus[i].powerWatts > 0
                      ? '${latest.gpus[i].powerWatts.toStringAsFixed(0)} W'
                      : '-',
                  series: [
                    for (final m in history)
                      if (i < m.gpus.length) m.gpus[i].powerWatts,
                  ],
                  unitMax: _maxOf([
                    for (final m in history)
                      if (i < m.gpus.length) m.gpus[i].powerWatts,
                  ]),
                ),
              ),
              const SizedBox(width: AppLayout.gapSm),
              Expanded(
                child: _GpuTrend(
                  label: '显存',
                  color: const Color(0xFF00897B),
                  value:
                      '${latest.gpus[i].memUsedMiB.toStringAsFixed(0)}/'
                      '${latest.gpus[i].memTotalMiB.toStringAsFixed(0)} MiB',
                  series: [
                    for (final m in history)
                      if (i < m.gpus.length && m.gpus[i].memTotalMiB > 0)
                        m.gpus[i].memUsedMiB / m.gpus[i].memTotalMiB * 100,
                  ],
                  unitMax: 100,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppLayout.gapSm),
        ],
      ],
    );
  }

  double _maxOf(List<double> values) {
    var max = 0.0;
    for (final v in values) {
      if (v > max) max = v;
    }
    return max > 0 ? max : 100;
  }
}

/// 华为昇腾 NPU 趋势：每芯片 AI Core / HBM / 功耗 三卡并排。
class _NpuRow extends StatelessWidget {
  const _NpuRow({required this.history});

  final List<MonitorMetrics> history;

  @override
  Widget build(BuildContext context) {
    final latest = history.isEmpty ? null : history.last;
    if (latest == null || latest.npus.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < latest.npus.length; i++) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppLayout.gapSm),
            child: Text(
              'NPU ${i + 1}：${latest.npus[i].name}'
              '${latest.npus[i].tempC > 0 ? ' · ${latest.npus[i].tempC.toStringAsFixed(0)}°C' : ''}'
              ' · ${latest.npus[i].health.isEmpty ? 'OK' : latest.npus[i].health}',
              style: context.theme.typography.body.xs.copyWith(
                fontWeight: FontWeight.w600,
                color: _healthColor(latest.npus[i].health),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _GpuTrend(
                  label: 'AI Core',
                  color: const Color(0xFF7B1FA2),
                  value: '${latest.npus[i].aiCorePercent.toStringAsFixed(0)}%',
                  series: [
                    for (final m in history)
                      if (i < m.npus.length) m.npus[i].aiCorePercent,
                  ],
                  unitMax: 100,
                ),
              ),
              const SizedBox(width: AppLayout.gapSm),
              Expanded(
                child: _GpuTrend(
                  label: 'HBM',
                  color: const Color(0xFF00897B),
                  value: '${latest.npus[i].hbmPercent.toStringAsFixed(0)}%',
                  series: [
                    for (final m in history)
                      if (i < m.npus.length) m.npus[i].hbmPercent,
                  ],
                  unitMax: 100,
                ),
              ),
              const SizedBox(width: AppLayout.gapSm),
              if (latest.npus[i].powerWatts > 0)
                Expanded(
                  child: _GpuTrend(
                    label: '功耗',
                    color: const Color(0xFFEF6C00),
                    value: '${latest.npus[i].powerWatts.toStringAsFixed(0)} W',
                    series: [
                      for (final m in history)
                        if (i < m.npus.length) m.npus[i].powerWatts,
                    ],
                    unitMax: _maxOf([
                      for (final m in history)
                        if (i < m.npus.length) m.npus[i].powerWatts,
                    ]),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppLayout.gapSm),
        ],
      ],
    );
  }

  double _maxOf(List<double> values) {
    var max = 0.0;
    for (final v in values) {
      if (v > max) max = v;
    }
    return max > 0 ? max : 100;
  }

  /// 健康状态颜色：OK 绿、Warning 橙、Alarm/Critical 红。
  Color _healthColor(String health) {
    final h = health.toLowerCase();
    if (h.contains('warning')) return const Color(0xFFEF6C00);
    if (h.contains('alarm') || h.contains('critical')) {
      return const Color(0xFFC62828);
    }
    return const Color(0xFF2E7D32);
  }
}

/// 单个 GPU/NPU 指标趋势卡。
class _GpuTrend extends StatelessWidget {
  const _GpuTrend({
    required this.label,
    required this.color,
    required this.value,
    required this.series,
    required this.unitMax,
  });

  final String label;
  final Color color;
  final String value;
  final List<double> series;
  final double unitMax;

  @override
  Widget build(BuildContext context) {
    return _TrendCard(
      label: label,
      color: color,
      value: value,
      values: series,
      unitMax: unitMax,
    );
  }
}

/// 单指标趋势卡片：大数值 + Y 轴刻度 + 网格 + 最近 60 秒折线。
class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.label,
    required this.color,
    required this.value,
    required this.values,
    required this.unitMax,
  });

  final String label;
  final Color color;
  final String value;
  final List<double> values;
  final double unitMax;

  @override
  Widget build(BuildContext context) {
    final p = context.theme.colors;
    return Container(
      height: 152,
      padding: const EdgeInsets.all(AppLayout.gapSm + 2),
      decoration: BoxDecoration(
        color: p.muted,
        borderRadius: context.theme.style.borderRadius.md,
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: context.theme.typography.body.xs2.copyWith(color: p.mutedForeground),
              ),
              const Spacer(),
              Text(
                value,
                style: context.theme.typography.body.md.copyWith(fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
          const SizedBox(height: AppLayout.gapXs),
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: CustomPaint(
                painter: _TrendChartPainter(
                  values: values,
                  unitMax: unitMax,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单指标折线绘制（Y 轴刻度 + 网格线 + 折线）。
class _TrendChartPainter extends CustomPainter {
  _TrendChartPainter({
    required this.values,
    required this.unitMax,
    required this.color,
  });

  final List<double> values;
  final double unitMax;
  final Color color;

  static const _axisWidth = 30.0;
  static const _pad = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plotLeft = _axisWidth;
    final plotRight = size.width - _pad;
    final plotTop = _pad;
    final plotBottom = size.height - _pad;
    final plotWidth = plotRight - plotLeft;
    final plotHeight = plotBottom - plotTop;

    final gridPaint = Paint()
      ..strokeWidth = 1
      ..color = color.withValues(alpha: 0.15);
    final labelPaint = TextPainter(textDirection: TextDirection.ltr);

    const steps = 4;
    for (var s = 0; s < steps; s++) {
      final ratio = s / (steps - 1);
      final y = plotBottom - plotHeight * ratio;
      canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), gridPaint);
      final label = _fmtTick(unitMax * ratio);
      labelPaint.text = TextSpan(
        text: label,
        // 图表刻度：CustomPainter 里取不到 theme（没有 context），
        // 与图表 4 条曲线的配色同属「数据标注」而非 UI 样式，故保留局部常量。
        style: TextStyle(fontSize: 8.5, color: color.withValues(alpha: 0.8)),
      );
      labelPaint.layout();
      labelPaint.paint(canvas, Offset(_pad, y - labelPaint.height / 2));
    }

    if (values.length < 2) {
      canvas.drawLine(
        Offset(plotLeft, plotBottom),
        Offset(plotRight, plotBottom),
        Paint()
          ..strokeWidth = 2
          ..color = color,
      );
      return;
    }

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = plotLeft + plotWidth * i / (values.length - 1);
      final y = plotBottom - plotHeight * (values[i] / unitMax).clamp(0, 1);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  String _fmtTick(double v) {
    if (v == 0) return '0';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}k';
    return v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }

  @override
  bool shouldRepaint(_TrendChartPainter old) => old.values != values;
}

/// 进程内存占用文本（由总内存 + 百分比换算为 MB/GB）。
String _processMemText(int memTotalBytes, double memPercent) =>
    formatBytes((memTotalBytes * memPercent / 100).round());

/// TOP 进程列表：支持按 COMMAND 全称模糊搜索。
class _MonitorProcessList extends StatefulWidget {
  const _MonitorProcessList({
    required this.processes,
    required this.cpuCores,
    required this.memTotalBytes,
  });

  final List<TopProcess> processes;
  final int cpuCores;
  final int memTotalBytes;

  @override
  State<_MonitorProcessList> createState() => _MonitorProcessListState();
}

class _MonitorProcessListState extends State<_MonitorProcessList> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.theme.colors;
    final keyword = _searchController.text.trim().toLowerCase();
    final filtered = keyword.isEmpty
        ? widget.processes
        : widget.processes
            .where((proc) => proc.name.toLowerCase().contains(keyword))
            .toList();

    return Container(
      decoration: BoxDecoration(
        color: p.muted,
        borderRadius: context.theme.style.borderRadius.md,
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppLayout.gapMd,
              AppLayout.gapSm,
              AppLayout.gapSm,
              AppLayout.gapSm,
            ),
            child: Row(
              children: [
                Text(
                  'TOP 进程',
                  style: context.theme.typography.body.xs.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                SizedBox(
                  width: 190,
                  child: FTextField(
                    control: FTextFieldControl.managed(
                      controller: _searchController,
                      onChange: (_) => setState(() {}),
                    ),
                    hint: '按命令搜索',
                    prefixBuilder: (context, style, variants) => const Icon(
                        FLucideIcons.search,
                        size: 15,
                      ),
                  ),
                ),
              ],
            ),
          ),
          const FDivider(),
          // 表头
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppLayout.gapMd,
              AppLayout.gapSm,
              AppLayout.gapMd,
              AppLayout.gapXs,
            ),
            child: Row(
              children: [
                const SizedBox(width: 52, child: _HeadText('PID')),
                Expanded(child: _HeadText('命令')),
                const SizedBox(width: 72, child: _HeadText('CPU', right: true)),
                const SizedBox(width: 72, child: _HeadText('内存', right: true)),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      keyword.isEmpty ? '无数据' : '未匹配，试试其他关键词',
                      style: context.theme.typography.body.xs.copyWith(color: p.mutedForeground),
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const FDivider(),
                    itemBuilder: (_, i) {
                      final proc = filtered[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppLayout.gapMd,
                          vertical: AppLayout.gapSm,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 52,
                              child: Text(
                                '${proc.pid}',
                                style: context.theme.typography.body.xs2,
                              ),
                            ),
                            Expanded(
                              child: AppTooltip(
                                message: proc.name,
                                child: Text(
                                  proc.name,
                                  style: context.theme.typography.body.xs2,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 72,
                              child: Text(
                                '${proc.cpuPercent.toStringAsFixed(1)}%',
                                textAlign: TextAlign.right,
                                style: context.theme.typography.body.xs2.copyWith(color: p.mutedForeground),
                              ),
                            ),
                            SizedBox(
                              width: 72,
                              child: AppTooltip(
                                message: _processMemText(
                                  widget.memTotalBytes,
                                  proc.memPercent,
                                ),
                                child: Text(
                                  '${proc.memPercent.toStringAsFixed(1)}%',
                                  textAlign: TextAlign.right,
                                  style: context.theme.typography.body.xs2.copyWith(color: p.mutedForeground),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
