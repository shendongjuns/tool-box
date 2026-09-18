part of 'sftp_view.dart';

// 文件列表与传输面板的展示组件（列模型 / 表头 / 数据行 / 工具栏小件 / 传输记录面板）。
//
// 从 sftp_view.dart 拆出：该文件原本 1500 行，把「目录浏览逻辑」与
// 「列表/面板展示」混在一起。用 part 保持这些私有组件不扩大可见性。

/// 文件列表列宽（表头与数据行共用，保证跨行严格对齐）。
const double _kColIcon = 20;
const double _kColSize = 76;
const double _kColMode = 92;
const double _kColTime = 130;
const double _kColActions = 78;

/// 仅日期（无时分）时的时间列宽度。
const double _kColDateShort = 80;

/// 名称列的最小可读宽度，低于此值就继续隐藏元信息列。
const double _kColNameMin = 130;

/// 任何宽度下都保留的固定占位：行首留白 + 图标列 + 行尾留白 + 操作列。
const double _kRowFixed =
    AppLayout.gapSm * 2 + _kColIcon + AppLayout.gapXs + _kColActions;

/// 文件列表当前要显示哪些元信息列。
///
/// 文件面板宽度可被拖拽（占会话区 0.3~0.7），默认窗口下只有约 340px；
/// 若四列固定展开必然横向溢出。这里按可用宽度逐级降级——
/// 先放弃「大小」，再放弃「权限」，再把时间列收成「仅日期」，
/// 最后才放弃时间列；「名称」与「操作」永不隐藏
/// （列被收掉的信息由行上的悬停提示兜底）。
class _FileColumns {
  const _FileColumns({
    required this.size,
    required this.mode,
    required this.time,
    this.dateOnly = false,
  });

  final bool size;
  final bool mode;

  /// 是否显示时间列。
  final bool time;

  /// 时间列只显示日期（窄面板下省掉时分，把宽度让给名称列）。
  final bool dateOnly;

  /// 时间列宽度：完整格式较宽，仅日期较窄。
  double get timeWidth => dateOnly ? _kColDateShort : _kColTime;

  /// 是否隐藏了任何信息（用于决定是否给行加悬停提示）。
  bool get anyHidden => !size || !mode || !time || dateOnly;

  factory _FileColumns.of(double width) {
    const base = _kRowFixed + _kColNameMin;
    if (width >= base + _kColSize + _kColMode + _kColTime) {
      return const _FileColumns(size: true, mode: true, time: true);
    }
    if (width >= base + _kColMode + _kColTime) {
      return const _FileColumns(size: false, mode: true, time: true);
    }
    if (width >= base + _kColDateShort) {
      return const _FileColumns(
        size: false,
        mode: false,
        time: true,
        dateOnly: true,
      );
    }
    return const _FileColumns(size: false, mode: false, time: false);
  }
}

/// 文件列表表头。
class _FileListHeader extends StatelessWidget {
  const _FileListHeader({required this.columns});

  final _FileColumns columns;

  @override
  Widget build(BuildContext context) {
    final style = context.theme.typography.body.xs.copyWith(
      color: context.theme.colors.mutedForeground,
    );
    Widget cell(String text, double width) => SizedBox(
      width: width,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );

    return SizedBox(
      height: 22,
      child: Row(
        children: [
          const SizedBox(width: AppLayout.gapSm + _kColIcon + AppLayout.gapSm),
          // 名称列表头也强制单行省略：即使极端窄宽度下也不会竖排换行。
          Expanded(
            child: Text(
              '名称',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (columns.size) cell('大小', _kColSize),
          if (columns.mode) cell('权限', _kColMode),
          if (columns.time)
            cell(columns.dateOnly ? '日期' : '最后修改', columns.timeWidth),
          const SizedBox(width: _kColActions),
          const SizedBox(width: AppLayout.gapXs),
        ],
      ),
    );
  }
}

/// 文件列表单行（紧凑单行：名称 / 大小 / 权限 / 最后修改 + 行内操作）。
class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.entry,
    required this.isDir,
    required this.columns,
    required this.onOpen,
    required this.onDetails,
    required this.onDownload,
    required this.onDelete,
  });

  final SftpName entry;
  final bool isDir;
  final _FileColumns columns;
  final VoidCallback onOpen;
  final VoidCallback onDetails;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final valueStyle = context.theme.typography.body.sm.copyWith(
      color: colors.foreground,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    Widget cell(String text, double width, {TextStyle? style}) => SizedBox(
      width: width,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style ?? valueStyle,
      ),
    );

    Widget action(IconData icon, String tooltip, VoidCallback onPress) =>
        FTappable(
          onPress: onPress,
          semanticsTooltip: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(icon, size: 15, color: colors.mutedForeground),
          ),
        );

    final mode = _fmtMode(entry.attr.mode?.value ?? 0);
    final size = isDir ? '—' : _fmtSize(entry.attr.size);
    final mtime = _fmtMtime(entry.attr.modifyTime);
    final mdate = _fmtDate(entry.attr.modifyTime);

    final row = SizedBox(
      height: 30,
      child: Row(
        children: [
          const SizedBox(width: AppLayout.gapSm),
          SizedBox(
            width: _kColIcon,
            child: Icon(
              isDir ? FLucideIcons.folder : FLucideIcons.fileText,
              size: 15,
              color: isDir ? colors.primary : colors.mutedForeground,
            ),
          ),
          const SizedBox(width: AppLayout.gapSm),
          Expanded(
            child: Text(
              entry.filename,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: valueStyle,
            ),
          ),
          if (columns.size) cell(size, _kColSize),
          if (columns.mode)
            cell(mode, _kColMode, style: valueStyle.copyWith(
              fontFamily: 'monospace',
            )),
          if (columns.time)
            cell(columns.dateOnly ? mdate : mtime, columns.timeWidth),
          SizedBox(
            width: _kColActions,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isDir) action(FLucideIcons.download, '下载', onDownload),
                action(FLucideIcons.info, '详情', onDetails),
                action(FLucideIcons.trash2, '删除', onDelete),
              ],
            ),
          ),
          const SizedBox(width: AppLayout.gapXs),
        ],
      ),
    );

    return FTappable(
      onPress: onOpen,
      onSecondaryPress: onDetails,
      // 窄面板下会隐藏部分列，用悬停提示补齐大小 / 权限 / 修改时间。
      child: columns.anyHidden
          ? AppTooltip(message: '${entry.filename}\n$size  ·  $mode  ·  $mtime', child: row)
          : row,
    );
  }
}

String _fmtSize(int? size) {
  if (size == null) return '';
  if (size < 1024) return '$size B';
  if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
  if (size < 1024 * 1024 * 1024) {
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

String _fmtMtime(int? unixSeconds) {
  if (unixSeconds == null) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000).toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}

/// 仅日期（窄面板下让出宽度给名称列）。
String _fmtDate(int? unixSeconds) {
  if (unixSeconds == null) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000).toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
}

String _fmtMode(int mode) {
  if (mode < 0) return '----------';
  const read = 0x4;
  const write = 0x2;
  const exec = 0x1;
  final sb = StringBuffer((mode & 0x4000) != 0 ? 'd' : '-');
  for (final shift in const [6, 3, 0]) {
    final bits = mode >> shift;
    sb.write((bits & read) != 0 ? 'r' : '-');
    sb.write((bits & write) != 0 ? 'w' : '-');
    sb.write((bits & exec) != 0 ? 'x' : '-');
  }
  return sb.toString();
}

/// 带文字的工具栏按钮（用于「新建目录 / 上传」这类主要操作）。
class _LabeledTool extends StatelessWidget {
  const _LabeledTool({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FButton(
    mainAxisSize: MainAxisSize.min,
    variant: FButtonVariant.ghost,
    size: FButtonSizeVariant.sm,
    onPress: onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        Text(label),
      ],
    ),
  );
}

/// 工具栏紧凑图标按钮：32px 内边距，节省横向空间。
class _ToolIcon extends StatelessWidget {
  const _ToolIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FButton(
      mainAxisSize: MainAxisSize.min,
      variant: FButtonVariant.ghost,
      size: FButtonSizeVariant.sm,
      semanticsTooltip: tooltip,
      onPress: onPressed,
      child: Icon(icon, size: 18),
    );
  }
}

/// 路径补全建议项。
class _PathSuggestion {
  const _PathSuggestion({
    required this.fullPath,
    required this.label,
    required this.isDir,
  });

  final String fullPath;
  final String label;
  final bool isDir;
}

/// 路径补全建议列表。
class _SuggestionList extends StatelessWidget {
  const _SuggestionList({
    required this.suggestions,
    required this.onSelect,
  });

  final List<_PathSuggestion> suggestions;
  final ValueChanged<_PathSuggestion> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppLayout.gapMd,
        0,
        AppLayout.gapMd,
        AppLayout.gapXs,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.muted,
          borderRadius: context.theme.style.borderRadius.md,
          border: Border.all(color: scheme.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 160),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: suggestions.length,
            itemBuilder: (_, i) {
              final s = suggestions[i];
              return FTile(
                prefix: Icon(
                  s.isDir
                      ? FLucideIcons.folder
                      : FLucideIcons.fileText,
                  size: 16,
                  color: s.isDir ? scheme.primary : scheme.mutedForeground,
                ),
                title: Text(s.label),
                onPress: () => onSelect(s),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 传输任务面板：显示上传/下载任务列表与进度条。
class _TransferPanel extends ConsumerWidget {
  const _TransferPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.theme.colors;
    final textTheme = context.theme.typography.body;
    // 内部监听任务列表，仅本面板 rebuild，不影响整个文件视图。
    final tasks = ref.watch(transferTasksProvider);
    if (tasks.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppLayout.gapMd,
        0,
        AppLayout.gapMd,
        AppLayout.gapSm,
      ),
      padding: const EdgeInsets.all(AppLayout.gapSm),
      decoration: BoxDecoration(
        color: scheme.muted,
        borderRadius: context.theme.style.borderRadius.md,
        border: Border.all(color: scheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('传输任务', style: textTheme.sm),
              const Spacer(),
              FButton(
                mainAxisSize: MainAxisSize.min,
                variant: FButtonVariant.ghost,
                onPress: () =>
                    ref.read(transferTasksProvider.notifier).clearFinished(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [const Icon(FLucideIcons.trash2, size: 14), const SizedBox(width: 6), const Text('清空已完成')],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppLayout.gapXs),
          // 任务列表可滚动，避免任务多时溢出。
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: tasks.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppLayout.gapXs),
              itemBuilder: (_, i) {
                final task = tasks[i];
                return Row(
                  children: [
                    Icon(
                      task.direction == TransferDirection.upload
                          ? FLucideIcons.upload
                          : FLucideIcons.download,
                      size: 14,
                      color: scheme.mutedForeground,
                    ),
                    const SizedBox(width: AppLayout.gapSm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 失败/取消时悬停显示具体原因。
                          AppTooltip(
                            message: task.error ?? task.fileName,
                            child: Text(
                              task.fileName,
                              style: textTheme.sm,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 2),
                          ClipRRect(
                            borderRadius:
                                context.theme.style.borderRadius.xs,
                            // 完成/取消/失败显示最终进度（done 满条），
                            // 传输中显示实时百分比。
                            child: FDeterminateProgress(
                              value: task.status == TransferStatus.done
                                  ? 1
                                  : task.progress,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppLayout.gapSm),
                    SizedBox(
                      width: 70,
                      child: Text(
                        _taskStatusText(task),
                        style: textTheme.sm.copyWith(
                          color: _taskStatusColor(task, scheme),
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    // 终止按钮（传输中显示）。
                    if (task.status == TransferStatus.running ||
                        task.status == TransferStatus.pending)
                      FButton(
                        mainAxisSize: MainAxisSize.min,
                        variant: FButtonVariant.ghost,
                        size: FButtonSizeVariant.sm,
                        semanticsTooltip: '终止',
                        onPress: () => ref
                            .read(transferTasksProvider.notifier)
                            .cancel(task.id),
                        child: const Icon(FLucideIcons.x, size: 16),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _taskStatusText(TransferTask task) {
    switch (task.status) {
      case TransferStatus.done:
        return '完成';
      case TransferStatus.failed:
        // 权限不足时明确显示"无权限"，其他错误显示"失败"。
        return (task.error ?? '').contains('无权限') ? '无权限' : '失败';
      case TransferStatus.cancelled:
        return '取消';
      case TransferStatus.pending:
        return '等待';
      case TransferStatus.running:
        // 传输中：有进度显示百分比，初始显示"传输中"。
        return task.progress > 0
            ? '${(task.progress * 100).toStringAsFixed(0)}%'
            : '传输中';
    }
  }

  Color _taskStatusColor(TransferTask task, FColors scheme) {
    switch (task.status) {
      case TransferStatus.done:
        return scheme.primary;
      case TransferStatus.failed:
      case TransferStatus.cancelled:
        return scheme.destructive;
      case TransferStatus.pending:
      case TransferStatus.running:
        return scheme.mutedForeground;
    }
  }
}
