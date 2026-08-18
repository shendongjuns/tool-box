import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/features/repository/pull_controller.dart';
import 'package:toolbox/features/repository/repo_controller.dart';
import 'package:toolbox/features/repository/repo_detection.dart';
import 'package:toolbox/features/repository/repo_models.dart';
import 'package:toolbox/ui/theme/appflowy_colors.dart';

/// 代码仓库管理页：左侧分组列表，右侧仓库列表。
class RepositoryView extends ConsumerStatefulWidget {
  const RepositoryView({super.key});

  @override
  ConsumerState<RepositoryView> createState() => _RepositoryViewState();
}

class _RepositoryViewState extends ConsumerState<RepositoryView> {
  String? _selectedGroupId;

  RepoGroup? _resolveSelected(List<RepoGroup> groups) {
    if (groups.isEmpty) return null;
    if (_selectedGroupId != null) {
      for (final g in groups) {
        if (g.id == _selectedGroupId) return g;
      }
    }
    return groups.first;
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(repoGroupsProvider);
    final selected = _resolveSelected(groups);
    final pullStatuses = ref.watch(repoPullControllerProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(AppflowySpacing.xl),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GroupPanel(
              groups: groups,
              selectedId: selected?.id,
              onSelect: (id) => setState(() => _selectedGroupId = id),
              onAdd: () => _showGroupDialog(),
              onEdit: (group) => _showGroupDialog(group: group),
              onDelete: _deleteGroup,
            ),
            const SizedBox(width: AppflowySpacing.xl),
            Expanded(
              child: selected == null
                  ? const _EmptyHint(text: '暂无分组，请先在左侧新建分组')
                  : _RepoPanel(
                      group: selected,
                      pullStatuses: pullStatuses,
                      onAdd: () => _showRepoDialog(selected),
                      onEdit: (repo) => _showRepoDialog(selected, repo: repo),
                      onDelete: (repo) => _deleteRepo(selected, repo),
                      onImport: () => _showImportDialog(selected),
                      onEditVersion: () => _showVersionDialog(selected),
                      onPickPath: () => _pickLocalPath(selected),
                      onPull: () => _pullGroup(selected),
                      onCopy: _copyRepo,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyRepo(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制：$text'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pickLocalPath(RepoGroup group) async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: '选择分组「${group.name}」的本地文件夹',
    );
    if (path == null || path.isEmpty) return;
    ref.read(repoGroupsProvider.notifier).setGroupLocalPath(group.id, path);
  }

  Future<void> _pullGroup(RepoGroup group) async {
    final summary = await ref
        .read(repoPullControllerProvider.notifier)
        .pullGroup(group);
    if (!mounted) return;
    if (summary == null) {
      _showMessage('请先为分组绑定本地文件夹');
      return;
    }
    _showMessage(
      '拉取完成：成功 ${summary.success} 个，跳过 ${summary.skipped} 个，'
      '失败 ${summary.failed} 个',
    );
  }

  Future<void> _showGroupDialog({RepoGroup? group}) async {
    final nameController = TextEditingController(text: group?.name ?? '');
    final versionController = TextEditingController(text: group?.version ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(group == null ? '新建分组' : '编辑分组'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: group == null,
                decoration: const InputDecoration(labelText: '分组名'),
              ),
              const SizedBox(height: AppflowySpacing.m),
              TextField(
                controller: versionController,
                decoration: const InputDecoration(
                  labelText: '版本号（可选，如 1.0）',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (saved == true) {
      final name = nameController.text.trim();
      final version = versionController.text.trim();
      if (name.isEmpty) {
        _showMessage('分组名不能为空');
      } else {
        final notifier = ref.read(repoGroupsProvider.notifier);
        if (group == null) {
          notifier.addGroup(name, version: version);
        } else {
          notifier.renameGroup(group.id, name);
          notifier.setGroupVersion(group.id, version);
        }
      }
    }
    nameController.dispose();
    versionController.dispose();
  }

  Future<void> _showVersionDialog(RepoGroup group) async {
    final controller = TextEditingController(text: group.version ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置版本号'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: '版本号（如 1.0）'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true) {
      ref
          .read(repoGroupsProvider.notifier)
          .setGroupVersion(group.id, controller.text);
    }
    controller.dispose();
  }

  Future<void> _showRepoDialog(RepoGroup group, {Repo? repo}) async {
    final nameController = TextEditingController(text: repo?.name ?? '');
    final urlController = TextEditingController(text: repo?.url ?? '');
    var type = repo?.type ?? RepoType.svn;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final resolved = resolveUrl(urlController.text.trim(), group.version);
          return AlertDialog(
            title: Text(repo == null ? '新增仓库' : '编辑仓库'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: '仓库名'),
                  ),
                  const SizedBox(height: AppflowySpacing.m),
                  SegmentedButton<RepoType>(
                    segments: [
                      for (final t in RepoType.values)
                        ButtonSegment(value: t, label: Text(t.label)),
                    ],
                    selected: {type},
                    onSelectionChanged: (s) =>
                        setDialogState(() => type = s.first),
                  ),
                  const SizedBox(height: AppflowySpacing.m),
                  TextField(
                    controller: urlController,
                    decoration: const InputDecoration(
                      labelText: '地址（SVN 可用 {version} 占位版本）',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: AppflowySpacing.m),
                  Text(
                    '预览：$resolved',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true) {
      final name = nameController.text.trim();
      final url = urlController.text.trim();
      if (url.isEmpty) {
        _showMessage('地址不能为空');
      } else {
        final newRepo = Repo(
          id: repo?.id ?? newId(),
          name: name.isEmpty ? deriveRepoName(url, version: group.version) : name,
          type: type,
          url: url,
        );
        final notifier = ref.read(repoGroupsProvider.notifier);
        if (repo == null) {
          notifier.addRepo(group.id, newRepo);
        } else {
          notifier.updateRepo(group.id, newRepo);
        }
      }
    }
    nameController.dispose();
    urlController.dispose();
  }

  Future<void> _showImportDialog(RepoGroup group) async {
    final textController = TextEditingController();
    final versionController = TextEditingController();
    var versionTouched = false;
    final groups = ref.read(repoGroupsProvider);
    var targetGroupId = group.id;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final version = versionController.text.trim();
          final preview = parseBatch(
            textController.text,
            version: version.isEmpty ? null : version,
          );
          return AlertDialog(
            title: const Text('批量导入仓库'),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButton<String>(
                    value: targetGroupId,
                    isExpanded: true,
                    items: [
                      for (final g in groups)
                        DropdownMenuItem(value: g.id, child: Text(g.name)),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => targetGroupId = v ?? group.id),
                  ),
                  const SizedBox(height: AppflowySpacing.m),
                  TextField(
                    controller: textController,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: '粘贴地址（每行一个）',
                      alignLabelWithHint: true,
                    ),
                    onChanged: (_) => setDialogState(() {
                      if (!versionTouched) {
                        final detected =
                            detectVersion(_nonEmptyLines(textController.text));
                        versionController.text = detected ?? '';
                      }
                    }),
                  ),
                  const SizedBox(height: AppflowySpacing.m),
                  TextField(
                    controller: versionController,
                    decoration: const InputDecoration(
                      labelText: '版本号（自动识别，可修改）',
                    ),
                    onChanged: (_) => setDialogState(() => versionTouched = true),
                  ),
                  const SizedBox(height: AppflowySpacing.m),
                  if (preview.isNotEmpty) ...[
                    Text(
                      '识别到 ${preview.length} 个仓库：',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: AppflowySpacing.s),
                    SizedBox(
                      height: 140,
                      child: ListView.builder(
                        itemCount: preview.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '${preview[i].type.label}  ${preview[i].name}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('导入'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true) {
      final version = versionController.text.trim();
      final v = version.isEmpty ? null : version;
      final repos = parseBatch(textController.text, version: v);
      if (repos.isNotEmpty) {
        final added = ref
            .read(repoGroupsProvider.notifier)
            .importRepos(targetGroupId, repos, version: v);
        final skipped = repos.length - added;
        _showMessage(
          skipped > 0 ? '已导入 $added 个仓库，跳过 $skipped 个重复' : '已导入 $added 个仓库',
        );
      }
    }
    textController.dispose();
    versionController.dispose();
  }

  Future<void> _deleteGroup(RepoGroup group) async {
    final ok = await _confirm('删除分组「${group.name}」？其下所有仓库将一并删除。');
    if (ok == true) {
      ref.read(repoGroupsProvider.notifier).deleteGroup(group.id);
    }
  }

  Future<void> _deleteRepo(RepoGroup group, Repo repo) async {
    final ok = await _confirm('删除仓库「${repo.name}」？');
    if (ok == true) {
      ref.read(repoGroupsProvider.notifier).deleteRepo(group.id, repo.id);
    }
  }

  Future<bool?> _confirm(String message) => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认删除'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  List<String> _nonEmptyLines(String text) => text
      .split(RegExp(r'\r?\n'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

class _GroupPanel extends StatelessWidget {
  const _GroupPanel({
    required this.groups,
    required this.selectedId,
    required this.onSelect,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<RepoGroup> groups;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<RepoGroup> onEdit;
  final ValueChanged<RepoGroup> onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppflowyRadius.m),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppflowySpacing.m,
              AppflowySpacing.s,
              AppflowySpacing.s,
              AppflowySpacing.s,
            ),
            child: Row(
              children: [
                Text('分组', style: textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: '新增分组',
                  onPressed: onAdd,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: groups.isEmpty
                ? const _EmptyHint(text: '暂无分组')
                : ListView.builder(
                    itemCount: groups.length,
                    itemBuilder: (_, i) {
                      final g = groups[i];
                      return _GroupTile(
                        group: g,
                        selected: g.id == selectedId,
                        onTap: () => onSelect(g.id),
                        onEdit: () => onEdit(g),
                        onDelete: () => onDelete(g),
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
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final RepoGroup group;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected
            ? scheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(
          horizontal: AppflowySpacing.m,
          vertical: AppflowySpacing.s,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (group.version != null)
                    Text(
                      '版本 ${group.version}',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 16),
              tooltip: '编辑分组',
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 16),
              tooltip: '删除分组',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _RepoPanel extends StatelessWidget {
  const _RepoPanel({
    required this.group,
    required this.pullStatuses,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onImport,
    required this.onEditVersion,
    required this.onPickPath,
    required this.onPull,
    required this.onCopy,
  });

  final RepoGroup group;
  final Map<String, PullStatus> pullStatuses;
  final VoidCallback onAdd;
  final ValueChanged<Repo> onEdit;
  final ValueChanged<Repo> onDelete;
  final VoidCallback onImport;
  final VoidCallback onEditVersion;
  final VoidCallback onPickPath;
  final VoidCallback onPull;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final pulling = pullStatuses.values.contains(PullStatus.pulling);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                group.name,
                style: textTheme.titleLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppflowySpacing.m),
            _VersionBadge(version: group.version, onEdit: onEditVersion),
            const SizedBox(width: AppflowySpacing.m),
            _LocalPathBadge(localPath: group.localPath, onPick: onPickPath),
            const Spacer(),
            OutlinedButton.icon(
              icon: pulling
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download, size: 18),
              label: const Text('一键拉取'),
              onPressed: pulling ? null : onPull,
            ),
            const SizedBox(width: AppflowySpacing.s),
            OutlinedButton.icon(
              icon: const Icon(Icons.playlist_add),
              label: const Text('批量导入'),
              onPressed: onImport,
            ),
            const SizedBox(width: AppflowySpacing.s),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('新增仓库'),
              onPressed: onAdd,
            ),
          ],
        ),
        const SizedBox(height: AppflowySpacing.m),
        Expanded(
          child: group.repos.isEmpty
              ? const _EmptyHint(text: '暂无仓库，点击右上角「新增仓库」或「批量导入」')
              : ListView.separated(
                  itemCount: group.repos.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppflowySpacing.s),
                  itemBuilder: (_, i) {
                    final repo = group.repos[i];
                    return _RepoTile(
                      repo: repo,
                      resolvedUrl: resolveUrl(repo.url, group.version),
                      status: pullStatuses[repo.id],
                      onCopy: onCopy,
                      onEdit: () => onEdit(repo),
                      onDelete: () => onDelete(repo),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _VersionBadge extends StatelessWidget {
  const _VersionBadge({required this.version, required this.onEdit});

  final String? version;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(AppflowyRadius.s),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppflowySpacing.m,
          vertical: AppflowySpacing.xs,
        ),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppflowyRadius.s),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              version == null ? '未设置版本' : '版本 $version',
              style: textTheme.bodySmall?.copyWith(color: scheme.primary),
            ),
            const SizedBox(width: AppflowySpacing.xs),
            Icon(Icons.edit_outlined, size: 14, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

class _LocalPathBadge extends StatelessWidget {
  const _LocalPathBadge({required this.localPath, required this.onPick});

  final String? localPath;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // 徽标显示本地文件夹最后一级目录名，完整路径放 tooltip。
    final display = localPath == null
        ? '绑定文件夹'
        : localPath!.split(RegExp(r'[/\\]')).last;

    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(AppflowyRadius.s),
      child: Tooltip(
        message: localPath ?? '点击选择本地文件夹',
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppflowySpacing.m,
            vertical: AppflowySpacing.xs,
          ),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppflowyRadius.s),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_outlined, size: 14, color: scheme.primary),
              const SizedBox(width: AppflowySpacing.xs),
              Text(
                display,
                style: textTheme.bodySmall?.copyWith(color: scheme.primary),
              ),
              const SizedBox(width: AppflowySpacing.xs),
              Icon(Icons.edit_outlined, size: 14, color: scheme.primary),
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
    this.status,
  });

  final Repo repo;
  final String resolvedUrl;
  final ValueChanged<String> onCopy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// 拉取状态（null 表示尚未拉取）。
  final PullStatus? status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppflowySpacing.m,
        vertical: AppflowySpacing.s,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppflowyRadius.m),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          _TypeBadge(type: repo.type),
          const SizedBox(width: AppflowySpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(repo.name, style: textTheme.bodyLarge),
                const SizedBox(height: 2),
                Text(
                  resolvedUrl,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (status != null) _PullStatusIcon(status: status!),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: '复制地址',
            onPressed: () => onCopy(resolvedUrl),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: '编辑仓库',
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: '删除仓库',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// 拉取状态图标：拉取中转圈，其余按状态显示图标与颜色。
class _PullStatusIcon extends StatelessWidget {
  const _PullStatusIcon({required this.status});

  final PullStatus status;

  @override
  Widget build(BuildContext context) {
    if (status == PullStatus.pulling) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppflowySpacing.s),
        child: Tooltip(
          message: status.label,
          child: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final (icon, color) = switch (status) {
      PullStatus.pending => (Icons.circle_outlined, Colors.grey),
      PullStatus.success => (Icons.check_circle, const Color(0xFF2E7D32)),
      PullStatus.skipped => (Icons.skip_next, Colors.grey),
      PullStatus.failed => (Icons.error_outline, const Color(0xFFC62828)),
      // 拉取中已在上面提前返回。
      PullStatus.pulling => (Icons.circle, Colors.transparent),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppflowySpacing.s),
      child: Tooltip(
        message: status.label,
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final RepoType type;

  @override
  Widget build(BuildContext context) {
    final color =
        type == RepoType.git ? const Color(0xFFF05033) : const Color(0xFF3F6AD8);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppflowySpacing.m,
        vertical: AppflowySpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppflowyRadius.xs),
      ),
      child: Text(
        type.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
