part of 'repo_view.dart';

// 仓库页的展示组件（分组面板 / 分组磁贴 / 仓库面板 / 卡片 / 仓库行 / 徽标）。
//
// 从 repo_view.dart 拆出：该文件原本 1900 行，把「页面状态（打开/拉取/弹窗）」
// 与「展示组件」分段阅读。用 part 保持这些私有组件不扩大可见性。

class _GroupPanel extends StatelessWidget {
  const _GroupPanel({
    required this.width,
    required this.groups,
    required this.selectedId,
    required this.compact,
    required this.onSelect,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  /// 面板宽度（紧凑模式传 double.infinity）。
  final double width;
  final List<RepoGroup> groups;
  final String? selectedId;
  final bool compact;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<RepoGroup> onEdit;
  final ValueChanged<RepoGroup> onDelete;

  @override
  Widget build(BuildContext context) {
    final p = context.theme.colors;
    return Container(
      width: width,
      height: compact ? 200 : null,
      padding: const EdgeInsets.all(AppLayout.gapLg),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: context.theme.style.borderRadius.xl,
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '我的分组',
                style: context.theme.typography.body.sm.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              FButton(
                mainAxisSize: MainAxisSize.min,
                variant: FButtonVariant.ghost,
                size: FButtonSizeVariant.sm,
                semanticsTooltip: '新增分组',
                onPress: onAdd,
                child: const Icon(FLucideIcons.plus, size: 18),
              ),
            ],
          ),
          const SizedBox(height: AppLayout.gapSm),
          Expanded(
            child: groups.isEmpty
                ? AppEmptyHint(
                    icon: FLucideIcons.folderOpen,
                    text: '暂无分组',
                    detail: '点击右上角新增',
                    compact: true,
                    onAction: onAdd,
                    actionLabel: '新建分组',
                  )
                : ListView.separated(
                    scrollDirection: compact ? Axis.horizontal : Axis.vertical,
                    itemCount: groups.length,
                    separatorBuilder: (_, _) => SizedBox(
                      width: compact ? AppLayout.gapSm : 0,
                      height: compact ? 0 : AppLayout.gapSm,
                    ),
                    itemBuilder: (_, i) {
                      final group = groups[i];
                      return _GroupTile(
                        group: group,
                        selected: group.id == selectedId,
                        compact: compact,
                        onTap: () => onSelect(group.id),
                        onEdit: () => onEdit(group),
                        onDelete: () => onDelete(group),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.group,
    required this.selected,
    required this.compact,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final RepoGroup group;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = context.theme.colors;
    return SizedBox(
      width: compact ? 190 : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? p.secondary : p.muted,
          borderRadius: context.theme.style.borderRadius.md,
        ),
        child: FTappable(
          onPress: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppLayout.gapMd,
              vertical: AppLayout.gapSm + 2,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: selected
                        ? p.primary
                        : p.mutedForeground.withValues(alpha: .3),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppLayout.gapMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.theme.typography.body.xs.copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected ? p.primary : p.foreground),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${group.version == null ? '未设置版本' : 'V${group.version}'}  ·  ${group.repos.length} 个仓库',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.theme.typography.body.xs2.copyWith(color: p.mutedForeground),
                      ),
                    ],
                  ),
                ),
                TileIconButton(
                  icon: FLucideIcons.pencil,
                  tooltip: '编辑分组',
                  onPress: onEdit,
                  iconSize: 14,
                  size: 26,
                ),
                const SizedBox(width: 2),
                TileIconButton(
                  icon: FLucideIcons.trash2,
                  tooltip: '删除分组',
                  onPress: onDelete,
                  destructive: true,
                  iconSize: 14,
                  size: 26,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RepoPanel extends StatefulWidget {
  const _RepoPanel({
    required this.group,
    required this.pullStatuses,
    required this.remotePulling,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onImport,
    required this.onEditVersion,
    required this.onPickPath,
    required this.onPull,
    required this.onCopy,
    required this.onSetupRemote,
    required this.onDeploy,
    required this.onLocalPullRepo,
    required this.onRemotePullRepo,
  });

  final RepoGroup group;
  final Map<String, PullStatus> pullStatuses;
  final bool remotePulling;
  final VoidCallback onAdd;
  final ValueChanged<Repo> onEdit;
  final ValueChanged<Repo> onDelete;
  final VoidCallback onImport;
  final VoidCallback onEditVersion;
  final VoidCallback onPickPath;
  final VoidCallback onPull;
  final ValueChanged<String> onCopy;
  final VoidCallback onSetupRemote;
  final VoidCallback onDeploy;
  final ValueChanged<Repo> onLocalPullRepo;
  final ValueChanged<Repo> onRemotePullRepo;

  @override
  State<_RepoPanel> createState() => _RepoPanelState();
}

class _RepoPanelState extends State<_RepoPanel> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void didUpdateWidget(covariant _RepoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group.id != widget.group.id) {
      _searchController.clear();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 分组操作按钮：由内容决定宽度（不再拉伸铺满整行）。
  Widget _actionButton(IconData icon, String label, VoidCallback? onPress) =>
      FButton(
        mainAxisSize: MainAxisSize.min,
        variant: FButtonVariant.outline,
        onPress: onPress,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.theme.colors;
    final keyword = _searchController.text.trim().toLowerCase();
    final filtered = widget.group.repos.where((repo) {
      final resolved = resolveUrl(repo.url, widget.group.version);
      final matchesKeyword =
          keyword.isEmpty ||
          repo.name.toLowerCase().contains(keyword) ||
          repo.url.toLowerCase().contains(keyword) ||
          resolved.toLowerCase().contains(keyword);
      return matchesKeyword;
    }).toList();
    final pulling = widget.pullStatuses.values.contains(PullStatus.pulling);

    return Container(
      padding: const EdgeInsets.all(AppLayout.gapXl),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: context.theme.style.borderRadius.xl,
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 分组信息：名称 + 版本标签
          Row(
            children: [
              Flexible(
                child: Text(
                  widget.group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.typography.body.md.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: AppLayout.gapSm),
              _VersionBadge(
                version: widget.group.version,
                onEdit: widget.onEditVersion,
              ),
            ],
          ),
          const SizedBox(height: AppLayout.gapLg),
          // 路径绑定
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _LocalPathCard(
                  localPath: widget.group.localPath,
                  onPick: widget.onPickPath,
                ),
              ),
              const SizedBox(width: AppLayout.gapMd),
              Expanded(
                child: _RemoteCard(group: widget.group, onEdit: widget.onSetupRemote),
              ),
            ],
          ),
          const SizedBox(height: AppLayout.gapLg),
          // 操作按钮：横向一行排布，宽度按内容自适应（`_actionButton` 里显式
          // `mainAxisSize: MainAxisSize.min`——ForUI 的 FButton 默认撑满可用宽度，
          // 放在 Wrap 里会每个按钮独占一行；放在 Row 里则不受影响）。
          // 极端窄宽度下才会折行，避免溢出。
          Wrap(
            spacing: AppLayout.gapSm,
            runSpacing: AppLayout.gapSm,
            children: [
              _actionButton(
                FLucideIcons.download,
                '本地拉取',
                pulling ? null : widget.onPull,
              ),
              _actionButton(
                FLucideIcons.cloudDownload,
                widget.remotePulling ? '远程拉取中…' : '远程拉取',
                widget.remotePulling
                    ? null
                    : widget.group.remotes.isEmpty
                    ? widget.onSetupRemote
                    : widget.onDeploy,
              ),
              _actionButton(FLucideIcons.plus, '新增仓库', widget.onAdd),
              _actionButton(FLucideIcons.listPlus, '批量导入', widget.onImport),
            ],
          ),
          const SizedBox(height: AppLayout.gapXl),
          // 仓库清单标题 + 搜索
          Row(
            children: [
              Text(
                '仓库清单',
                style: context.theme.typography.body.md.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: AppLayout.gapSm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppLayout.gapSm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: p.secondary,
                  borderRadius: context.theme.style.borderRadius.sm,
                ),
                child: Text(
                  '${filtered.length}/${widget.group.repos.length}',
                  style: context.theme.typography.body.xs2.copyWith(color: p.primary, fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 220,
                child: FTextField(
                  control: FTextFieldControl.managed(
                    controller: _searchController,
                    onChange: (_) => setState(() {}),
                  ),
                  hint: '搜索仓库名称或地址',
                  prefixBuilder: (context, style, variants) => const Icon(FLucideIcons.search, size: 17),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppLayout.gapMd),
          Expanded(
            child: filtered.isEmpty
                ? AppEmptyHint(
                    icon: widget.group.repos.isEmpty
                        ? FLucideIcons.package
                        : FLucideIcons.searchX,
                    text: widget.group.repos.isEmpty ? '这个分组还没有仓库' : '没有找到匹配仓库',
                    detail: widget.group.repos.isEmpty
                        ? '可以手动新增，或批量导入地址'
                        : '试试其他关键词或筛选条件',
                    onAction: widget.group.repos.isEmpty ? widget.onAdd : null,
                    actionLabel: widget.group.repos.isEmpty ? '新增仓库' : null,
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppLayout.gapSm),
                    itemBuilder: (_, index) {
                      final repo = filtered[index];
                      return _RepoTile(
                        repo: repo,
                        resolvedUrl: resolveUrl(repo.url, widget.group.version),
                        status: widget.pullStatuses[repo.id],
                        onCopy: widget.onCopy,
                        onEdit: () => widget.onEdit(repo),
                        onDelete: () => widget.onDelete(repo),
                        onLocalPull: () => widget.onLocalPullRepo(repo),
                        onRemotePull: () => widget.onRemotePullRepo(repo),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _VersionBadge extends StatelessWidget {
  const _VersionBadge({required this.version, required this.onEdit});

  final String? version;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colors;
    final textTheme = context.theme.typography.body;

    return FTappable(
      onPress: onEdit,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppLayout.gapSm,
          vertical: AppLayout.gapXs,
        ),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: .12),
          borderRadius: context.theme.style.borderRadius.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              version == null ? '未设置版本' : '版本 V$version',
              style: textTheme.sm.copyWith(color: scheme.primary),
            ),
            const SizedBox(width: AppLayout.gapXs),
            Icon(FLucideIcons.pencil, size: 14, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

class _LocalPathCard extends StatelessWidget {
  const _LocalPathCard({required this.localPath, required this.onPick});

  final String? localPath;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colors;
    final configured = localPath != null && localPath!.isNotEmpty;
    return _BindingCard(
      icon: FLucideIcons.folderOpen,
      title: '本地目录',
      value: configured ? localPath! : '尚未绑定本地目录',
      color: scheme.primary,
      onTap: onPick,
    );
  }
}

class _RemoteCard extends ConsumerWidget {
  const _RemoteCard({required this.group, required this.onEdit});

  final RepoGroup group;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(sshConnectionsProvider);
    final activeId =
        group.activeRemoteConnId != null &&
            group.remotes.containsKey(group.activeRemoteConnId)
        ? group.activeRemoteConnId
        : (group.remotes.isNotEmpty ? group.remotes.keys.first : null);
    String value = '点击设置远程拉取目标';
    if (activeId != null) {
      var connectionName = activeId;
      for (final connection in connections) {
        if (connection.id == activeId) {
          connectionName = connection.name;
          break;
        }
      }
      value = '$connectionName  ·  ${group.remotes[activeId]!.remotePath}';
    }
    return _BindingCard(
      icon: FLucideIcons.cloudDownload,
      title: '远程目标',
      value: value,
      color: context.theme.colors.primary,
      onTap: onEdit,
    );
  }
}

class _BindingCard extends StatelessWidget {
  const _BindingCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.theme.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.muted,
        borderRadius: context.theme.style.borderRadius.md,
      ),
      child: FTappable(
        onPress: onTap,
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(
            horizontal: AppLayout.gapMd,
            vertical: AppLayout.gapSm,
          ),
          decoration: BoxDecoration(
            borderRadius: context.theme.style.borderRadius.md,
            border: Border.all(color: p.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 19),
              const SizedBox(width: AppLayout.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: context.theme.typography.body.xs2.copyWith(color: p.mutedForeground),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.theme.typography.body.xs,
                    ),
                  ],
                ),
              ),
              Icon(FLucideIcons.chevronRight, size: 17, color: p.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepoTile extends StatelessWidget {
  const _RepoTile({
    required this.repo,
    required this.resolvedUrl,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
    required this.onLocalPull,
    required this.onRemotePull,
    this.status,
  });

  final Repo repo;
  final String resolvedUrl;
  final ValueChanged<String> onCopy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onLocalPull;
  final VoidCallback onRemotePull;
  final PullStatus? status;

  @override
  Widget build(BuildContext context) {
    final p = context.theme.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppLayout.gapMd),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: p.border.withValues(alpha: .8)),
        ),
      ),
      child: Row(
        children: [
          _TypeBadge(type: repo.type),
          const SizedBox(width: AppLayout.gapMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  repo.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.typography.body.sm.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                AppTooltip(
                  message: resolvedUrl,
                  child: Text(
                    resolvedUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.theme.typography.body.xs.copyWith(color: p.mutedForeground),
                  ),
                ),
              ],
            ),
          ),
          if (status != null) ...[
            const SizedBox(width: AppLayout.gapMd),
            _PullStatusLabel(status: status!),
          ],
          const SizedBox(width: AppLayout.gapSm),
          // 按钮间留 2px 间隙（与连接磁贴一致），悬停高亮互不相连。
          TileIconButton(
            icon: FLucideIcons.monitor,
            tooltip: '本地拉取 / 更新',
            onPress: onLocalPull,
          ),
          const SizedBox(width: 2),
          TileIconButton(
            icon: FLucideIcons.cloudDownload,
            tooltip: '远程拉取 / 更新',
            onPress: onRemotePull,
          ),
          const SizedBox(width: 2),
          TileIconButton(
            icon: FLucideIcons.copy,
            tooltip: '复制地址',
            onPress: () => onCopy(resolvedUrl),
          ),
          const SizedBox(width: 2),
          TileIconButton(
            icon: FLucideIcons.pencil,
            tooltip: '编辑仓库',
            onPress: onEdit,
          ),
          const SizedBox(width: 2),
          TileIconButton(
            icon: FLucideIcons.trash2,
            tooltip: '删除仓库',
            onPress: onDelete,
            destructive: true,
          ),
        ],
      ),
    );
  }
}

class _PullStatusLabel extends StatelessWidget {
  const _PullStatusLabel({required this.status});

  final PullStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, text) = switch (status) {
      PullStatus.pending => (context.theme.colors.mutedForeground, '待处理'),
      PullStatus.success => (context.theme.colors.primary, '已完成'),
      PullStatus.skipped => (context.theme.colors.mutedForeground, '已跳过'),
      PullStatus.failed => (context.theme.colors.destructive, '失败'),
      PullStatus.pulling => (context.theme.colors.primary, '拉取中…'),
    };
    if (status == PullStatus.pulling) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: FCircularProgress(),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: context.theme.typography.body.xs.copyWith(color: color, fontWeight: FontWeight.w500),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: context.theme.typography.body.xs.copyWith(color: color, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final RepoType type;

  @override
  Widget build(BuildContext context) {
    // 类型徽标的配色属于「数据编码」（区分 Git / SVN），并非主题样式；
    // 与监控趋势图 4 色同理保留局部常量。
    final (bg, fg) = type == RepoType.git
        ? (const Color(0xFFFFF0EA), const Color(0xFFE1774D))
        : (const Color(0xFFEDF4FF), const Color(0xFF5282D8));
    return Container(
      width: 46,
      padding: const EdgeInsets.symmetric(
        horizontal: AppLayout.gapSm,
        vertical: AppLayout.gapXs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: context.theme.style.borderRadius.xs,
      ),
      child: Text(
        type.label,
        textAlign: TextAlign.center,
        style: context.theme.typography.body.xs2.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
