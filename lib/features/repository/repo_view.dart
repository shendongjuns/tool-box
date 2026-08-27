import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/features/remote/remote_controller.dart';
import 'package:toolbox/features/remote/remote_models.dart';
import 'package:toolbox/features/repository/pull_controller.dart';
import 'package:toolbox/features/repository/repo_controller.dart';
import 'package:toolbox/features/repository/repo_deploy.dart';
import 'package:toolbox/features/repository/repo_detection.dart';
import 'package:toolbox/features/repository/repo_models.dart';
import 'package:toolbox/features/repository/svn_client.dart';
import 'package:toolbox/ui/theme/app_icons.dart';
import 'package:toolbox/ui/theme/appflowy_colors.dart';
import 'package:toolbox/ui/theme/mochi_cat_tokens.dart';
import 'package:toolbox/ui/widgets/mochi_widgets.dart';

/// 代码仓库管理页：左侧分组列表，右侧仓库列表。
class RepositoryView extends ConsumerStatefulWidget {
  const RepositoryView({super.key});

  @override
  ConsumerState<RepositoryView> createState() => _RepositoryViewState();
}

class _RepositoryViewState extends ConsumerState<RepositoryView> {
  String? _selectedGroupId;

  /// 远程拉取进行中（控制远程拉取按钮的加载动画）。
  bool _remotePulling = false;

  /// 左侧分组栏宽度（px），可拖拽调整。
  double _groupPanelWidth = 250;

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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 820;
          final padding = compact ? AppflowySpacing.xl : 28.0;
          return Padding(
            padding: EdgeInsets.fromLTRB(padding, 20, padding, padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _RepositoryHeader(),
                const SizedBox(height: AppflowySpacing.xl),
                Expanded(
                  child: Flex(
                    direction: compact ? Axis.vertical : Axis.horizontal,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _GroupPanel(
                        width: compact ? double.infinity : _groupPanelWidth,
                        groups: groups,
                        selectedId: selected?.id,
                        compact: compact,
                        onSelect: (id) => setState(() => _selectedGroupId = id),
                        onAdd: _showGroupDialog,
                        onEdit: (group) => _showGroupDialog(group: group),
                        onDelete: _deleteGroup,
                      ),
                      if (!compact) ...[
                        _ResizeHandle(
                          onDrag: (dx) => setState(
                            () => _groupPanelWidth =
                                (_groupPanelWidth + dx).clamp(190.0, 420.0),
                          ),
                        ),
                        const SizedBox(width: MochiCatSpacing.sm),
                      ],
                      Expanded(
                        child: selected == null
                            ? const _EmptyHint(
                                icon: AppIcons.folderOpen,
                                text: '还没有仓库分组',
                                detail: '创建一个分组，把相关项目集中管理',
                              )
                            : _RepoPanel(
                                group: selected,
                                pullStatuses: pullStatuses,
                                remotePulling: _remotePulling,
                                onAdd: () => _showRepoDialog(selected),
                                onEdit: (repo) =>
                                    _showRepoDialog(selected, repo: repo),
                                onDelete: (repo) => _deleteRepo(selected, repo),
                                onImport: () => _showImportDialog(selected),
                                onEditVersion: () =>
                                    _showVersionDialog(selected),
                                onPickPath: () => _pickLocalPath(selected),
                                onPull: () => _pullGroup(selected),
                                onSetupRemote: () => _setupRemote(selected),
                                onDeploy: () => _deployGroup(selected),
                                onLocalPullRepo: (repo) =>
                                    _pullOneLocal(selected, repo),
                                onRemotePullRepo: (repo) =>
                                    _pullOneRemote(selected, repo),
                                onCopy: _copyRepo,
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
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
    final actionLabel = {'checkout': '首次拉取(checkout)', 'update': '更新(update)'};
    final detail = summary.results
        .map(
          (r) =>
              '${r.repoName}：${actionLabel[r.action] ?? r.action} '
              '${r.ok ? '成功' : '失败'}',
        )
        .join('\n');
    _showMessage(
      '本地拉取完成：成功 ${summary.success} 个，跳过 ${summary.skipped} 个，'
      '失败 ${summary.failed} 个\n$detail',
    );
  }

  /// 单仓库本地拉取/更新（已有代码 → update，否则 checkout）。
  Future<void> _pullOneLocal(RepoGroup group, Repo repo) async {
    final localPath = group.localPath;
    if (localPath == null || localPath.isEmpty) {
      _showMessage('请先绑定本地文件夹');
      return;
    }
    if (repo.type != RepoType.svn) {
      _showMessage('${repo.name}：Git 仓库不支持本地 svn 拉取');
      return;
    }
    final controller = ref.read(repoPullControllerProvider.notifier);
    final url = resolveUrl(repo.url, group.version);
    final target =
        '$localPath${Platform.pathSeparator}${deriveRepoDirName(url)}';
    final dir = Directory(target);
    final exists = dir.existsSync() && dir.listSync().isNotEmpty;
    controller.setRepoStatus(repo.id, PullStatus.pulling);
    try {
      if (exists) {
        await ref.read(svnRunnerProvider)([
          'update',
          '--non-interactive',
          target,
        ]);
      } else {
        await ref.read(svnRunnerProvider)([
          'checkout',
          '--non-interactive',
          url,
          target,
        ]);
      }
      controller.setRepoStatus(repo.id, PullStatus.success);
      _showMessage('${repo.name}：${exists ? '更新' : '首次拉取'}成功');
    } on Exception {
      controller.setRepoStatus(repo.id, PullStatus.failed);
      _showMessage('${repo.name}：${exists ? '更新' : '首次拉取'}失败');
    }
  }

  /// 单仓库远程拉取/更新（远程已有工作副本 → update，否则 checkout）。
  Future<void> _pullOneRemote(RepoGroup group, Repo repo) async {
    // 用当前绑定的 SSH 连接（无绑定则提示先设置）。
    // 用当前远程拉取目标连接（上次设置的），无则第一个绑定。
    final connId =
        group.activeRemoteConnId != null &&
            group.remotes.containsKey(group.activeRemoteConnId)
        ? group.activeRemoteConnId
        : (group.remotes.isNotEmpty ? group.remotes.keys.first : null);
    final binding = connId == null ? null : group.remotes[connId];
    if (connId == null || binding == null) {
      _setupRemote(group);
      return;
    }
    if (repo.type != RepoType.svn) {
      _showMessage('${repo.name}：Git 仓库不支持远程 svn 拉取');
      return;
    }
    final remotePath = binding.remotePath;
    final controller = ref.read(repoPullControllerProvider.notifier);
    controller.setRepoStatus(repo.id, PullStatus.pulling);
    try {
      final connection = ref
          .read(sshConnectionsProvider)
          .firstWhere((c) => c.id == connId);
      final client = await connectForDeploy(connection);
      await remoteExec(client, 'mkdir -p "$remotePath"');
      final url = resolveUrl(repo.url, group.version);
      final dir = '$remotePath/${deriveRepoDirName(url)}';
      final isWorkingCopy = await isSvnWorkingCopy(client, dir);
      var result = isWorkingCopy
          ? await remoteSvnUpdate(client, dir)
          : await remoteSvnCheckout(client, url, dir);
      if (!result.success && isSvnAuthError(result)) {
        final cred = binding.svnUsername != null
            ? (binding.svnUsername!, binding.svnPassword ?? '')
            : await _promptSvnCredentials();
        if (cred != null) {
          result = isWorkingCopy
              ? await remoteSvnUpdate(
                  client,
                  dir,
                  username: cred.$1,
                  password: cred.$2,
                )
              : await remoteSvnCheckout(
                  client,
                  url,
                  dir,
                  username: cred.$1,
                  password: cred.$2,
                );
        }
      }
      await client.close();
      if (result.success) {
        controller.setRepoStatus(repo.id, PullStatus.success);
        _showMessage('${repo.name}：${isWorkingCopy ? '更新' : '首次拉取'}成功 → $dir');
      } else {
        controller.setRepoStatus(repo.id, PullStatus.failed);
        _showMessage(
          '${repo.name}：${isWorkingCopy ? '更新' : '首次拉取'}失败\n'
          '${result.output}',
        );
      }
    } catch (e) {
      controller.setRepoStatus(repo.id, PullStatus.failed);
      _showMessage('${repo.name}：远程拉取失败 $e');
    }
  }

  /// 配置远程拉取绑定（选 SSH 连接 + 该连接的远程目录/SVN 账号）。
  Future<void> _setupRemote(RepoGroup group) async {
    final connections = ref.read(sshConnectionsProvider);
    if (connections.isEmpty) {
      _showMessage('请先在「远程管理」中创建 SSH 连接');
      return;
    }
    // 默认选中当前远程拉取目标连接（上次设置），否则第一个绑定/第一个连接。
    late String connectionId;
    if (group.activeRemoteConnId != null &&
        connections.any((c) => c.id == group.activeRemoteConnId)) {
      connectionId = group.activeRemoteConnId!;
    } else if (group.remotes.isNotEmpty) {
      connectionId = group.remotes.keys.first;
    } else {
      connectionId = connections.first.id;
    }
    // 用当前默认连接加载绑定到输入框。
    final initBinding = group.remotes[connectionId];
    String connName() {
      for (final c in connections) {
        if (c.id == connectionId) return c.name;
      }
      return connectionId;
    }

    final pathController = TextEditingController(
      text: initBinding?.remotePath ?? '',
    );
    final svnUserController = TextEditingController(
      text: initBinding?.svnUsername ?? '',
    );
    final svnPassController = TextEditingController(
      text: initBinding?.svnPassword ?? '',
    );

    final saved = await showMochiDialog<bool>(
      context: context,
      title: '远程拉取设置：${connName()}',
      subtitle: '选择 SSH 连接并填写远程目录与 SVN 账号。',
      emoji: '🛰️',
      width: 460,
      content: StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MochiSelectField<String>(
              value: connectionId,
              items: [
                for (final c in connections) (c.id, '${c.name} (${c.hostLabel})'),
              ],
              label: 'SSH 连接',
              onChanged: (v) {
                if (v == null) return;
                // 切换连接时加载该连接已保存的绑定。
                final b = group.remotes[v];
                setDialogState(() {
                  connectionId = v;
                  pathController.text = b?.remotePath ?? '';
                  svnUserController.text = b?.svnUsername ?? '';
                  svnPassController.text = b?.svnPassword ?? '';
                });
              },
            ),
            const SizedBox(height: MochiCatSpacing.md),
            TextField(
              controller: pathController,
              decoration: const InputDecoration(
                labelText: '远程目录（如 /home/user/code）',
              ),
            ),
            const SizedBox(height: MochiCatSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: MochiCatSpacing.md),
            TextField(
              controller: svnUserController,
              decoration: const InputDecoration(
                labelText: 'SVN 账号（可选，远程拉取共用）',
              ),
            ),
            const SizedBox(height: MochiCatSpacing.md),
            TextField(
              controller: svnPassController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'SVN 密码（可选）'),
            ),
          ],
        ),
      ),
      actions: [
        MochiButton(
          label: '取消',
          type: MochiButtonType.ghost,
          onPressed: () => Navigator.pop(context, false),
        ),
        MochiButton(
          label: '保存',
          icon: AppIcons.save,
          type: MochiButtonType.primary,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    // 先取值再释放（controller 在 await 后仍可读，但应在 dispose 前取）。
    final remotePathText = pathController.text;
    final svnUserText = svnUserController.text.trim();
    final svnPassText = svnPassController.text;
    // 等待弹窗退出动画结束后再释放，避免 "used after being disposed"。
    await disposeAfterDialog([pathController, svnUserController, svnPassController]);

    if (saved == true) {
      ref
          .read(repoGroupsProvider.notifier)
          .setGroupRemote(
            group.id,
            connectionId,
            remotePath: remotePathText,
            svnUsername: svnUserText,
            svnPassword: svnPassText,
          );
      // 记住本次使用的连接（持久化到分组的 activeRemoteConnId）。
      // 下次打开弹窗默认选中、远程拉取用它。
      // 保存后确认写入，便于用户感知。
      String connName = connectionId;
      try {
        connName = ref
            .read(sshConnectionsProvider)
            .firstWhere((c) => c.id == connectionId)
            .name;
      } catch (_) {}
      _showMessage(
        '已保存「$connName」的远程拉取设置'
        '${remotePathText.isEmpty ? '（目录为空，已移除绑定）' : ''}',
      );
    }
  }

  /// 一键远程拉取：在远程服务器 svn checkout 分组仓库。
  /// 一键远程拉取：通过 SSH 在服务器上对每个 SVN 仓库执行 checkout。
  Future<void> _deployGroup(RepoGroup group) async {
    setState(() => _remotePulling = true);
    try {
      await _doDeploy(group);
    } finally {
      if (mounted) setState(() => _remotePulling = false);
    }
  }

  Future<void> _doDeploy(RepoGroup group) async {
    // 用当前远程拉取目标连接（上次设置的），无则第一个绑定。
    final connId =
        group.activeRemoteConnId != null &&
            group.remotes.containsKey(group.activeRemoteConnId)
        ? group.activeRemoteConnId
        : (group.remotes.isNotEmpty ? group.remotes.keys.first : null);
    final binding = connId == null ? null : group.remotes[connId];
    if (connId == null || binding == null) {
      _setupRemote(group);
      return;
    }
    if (group.repos.isEmpty) {
      _showMessage('分组内没有仓库');
      return;
    }
    final remotePath = binding.remotePath;

    SshConnection? connection;
    try {
      connection = ref
          .read(sshConnectionsProvider)
          .firstWhere((c) => c.id == connId);
    } catch (_) {
      connection = null;
    }
    if (connection == null) {
      _showMessage('找不到绑定的 SSH 连接');
      return;
    }

    final SSHClient client;
    try {
      client = await connectForDeploy(connection);
    } catch (e) {
      _showMessage('SSH 连接失败：$e');
      return;
    }

    // 确保远程目录存在（svn checkout 目标父目录需存在）。
    await remoteExec(client, 'mkdir -p "$remotePath"');

    // SVN 账号密码：优先用该连接绑定里填的；未填且需要认证时弹窗输入。
    String? svnUser = binding.svnUsername;
    String? svnPass = binding.svnPassword;
    Future<(String, String)?> ensureCred() async {
      if (svnUser != null) return (svnUser!, svnPass ?? '');
      final cred = await _promptSvnCredentials();
      if (cred != null) {
        svnUser = cred.$1;
        svnPass = cred.$2;
      }
      return cred;
    }

    var success = 0;
    var failed = 0;
    final results = <String>[];
    final pullCtrl = ref.read(repoPullControllerProvider.notifier);
    for (final repo in group.repos) {
      if (repo.type != RepoType.svn) {
        results.add('${repo.name}：Git 仓库跳过');
        continue;
      }
      pullCtrl.setRepoStatus(repo.id, PullStatus.pulling);
      final url = resolveUrl(repo.url, group.version);
      final dir = '$remotePath/${deriveRepoDirName(url)}';
      final isWorkingCopy = await isSvnWorkingCopy(client, dir);

      // 已有工作副本 → update；否则 → checkout。
      var result = isWorkingCopy
          ? await remoteSvnUpdate(client, dir)
          : await remoteSvnCheckout(client, url, dir);
      // svn 仓库需要认证时，弹框输入账号密码重试一次（共用凭据）。
      if (!result.success && isSvnAuthError(result)) {
        final cred = await ensureCred();
        if (cred != null) {
          result = isWorkingCopy
              ? await remoteSvnUpdate(
                  client,
                  dir,
                  username: cred.$1,
                  password: cred.$2,
                )
              : await remoteSvnCheckout(
                  client,
                  url,
                  dir,
                  username: cred.$1,
                  password: cred.$2,
                );
        }
      }
      if (result.success) {
        success++;
        pullCtrl.setRepoStatus(repo.id, PullStatus.success);
        results.add(
          '${repo.name}：'
          '${isWorkingCopy ? 'update' : 'checkout'} 成功 → $dir',
        );
      } else {
        failed++;
        pullCtrl.setRepoStatus(repo.id, PullStatus.failed);
        results.add(
          '${repo.name}：'
          '${isWorkingCopy ? 'update' : 'checkout'} 失败\n${result.output}',
        );
      }
    }
    try {
      await client.close();
    } catch (_) {}
    if (!mounted) return;
    _showMessage(
      '远程拉取完成：成功 $success 个，失败 $failed 个\n'
      '${results.join('\n')}',
    );
  }

  /// 弹框输入 SVN 仓库账号密码。
  Future<(String, String)?> _promptSvnCredentials() async {
    final userController = TextEditingController();
    final passController = TextEditingController();
    final saved = await showMochiDialog<bool>(
      context: context,
      title: 'SVN 仓库需要认证',
      emoji: '🔐',
      width: 400,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: userController,
            decoration: const InputDecoration(labelText: '用户名'),
          ),
          const SizedBox(height: MochiCatSpacing.md),
          TextField(
            controller: passController,
            obscureText: true,
            decoration: const InputDecoration(labelText: '密码'),
          ),
        ],
      ),
      actions: [
        MochiButton(
          label: '取消',
          type: MochiButtonType.ghost,
          onPressed: () => Navigator.pop(context, false),
        ),
        MochiButton(
          label: '确认',
          icon: AppIcons.check,
          type: MochiButtonType.primary,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    final cred = saved == true
        ? (userController.text.trim(), passController.text)
        : null;
    await disposeAfterDialog([userController, passController]);
    return cred;
  }

  Future<void> _showGroupDialog({RepoGroup? group}) async {
    final nameController = TextEditingController(text: group?.name ?? '');
    final versionController = TextEditingController(text: group?.version ?? '');
    final saved = await showMochiDialog<bool>(
      context: context,
      title: group == null ? '新建分组' : '编辑分组',
      emoji: '📁',
      width: 420,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: nameController,
            autofocus: group == null,
            decoration: const InputDecoration(labelText: '分组名'),
          ),
          const SizedBox(height: MochiCatSpacing.md),
          TextField(
            controller: versionController,
            decoration: const InputDecoration(
              labelText: '版本号（可选，如 2.8）',
            ),
          ),
        ],
      ),
      actions: [
        MochiButton(
          label: '取消',
          type: MochiButtonType.ghost,
          onPressed: () => Navigator.pop(context, false),
        ),
        MochiButton(
          label: '保存',
          icon: AppIcons.save,
          type: MochiButtonType.primary,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
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
    await disposeAfterDialog([nameController, versionController]);
  }

  Future<void> _showVersionDialog(RepoGroup group) async {
    final controller = TextEditingController(text: group.version ?? '');
    final saved = await showMochiDialog<bool>(
      context: context,
      title: '设置版本号',
      emoji: '🏷️',
      width: 400,
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: '版本号（如 2.8）'),
      ),
      actions: [
        MochiButton(
          label: '取消',
          type: MochiButtonType.ghost,
          onPressed: () => Navigator.pop(context, false),
        ),
        MochiButton(
          label: '保存',
          icon: AppIcons.save,
          type: MochiButtonType.primary,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (saved == true) {
      ref
          .read(repoGroupsProvider.notifier)
          .setGroupVersion(group.id, controller.text);
    }
    await disposeAfterDialog([controller]);
  }

  Future<void> _showRepoDialog(RepoGroup group, {Repo? repo}) async {
    final nameController = TextEditingController(text: repo?.name ?? '');
    final urlController = TextEditingController(text: repo?.url ?? '');
    var type = repo?.type ?? RepoType.svn;

    final saved = await showMochiDialog<bool>(
      context: context,
      title: repo == null ? '新增仓库' : '编辑仓库',
      emoji: '🗂️',
      width: 480,
      content: StatefulBuilder(
        builder: (context, setDialogState) {
          final resolved = resolveUrl(urlController.text.trim(), group.version);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '仓库名'),
              ),
              const SizedBox(height: MochiCatSpacing.md),
              SegmentedButton<RepoType>(
                segments: [
                  for (final t in RepoType.values)
                    ButtonSegment(value: t, label: Text(t.label)),
                ],
                selected: {type},
                onSelectionChanged: (s) => setDialogState(() => type = s.first),
              ),
              const SizedBox(height: MochiCatSpacing.md),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: '地址（SVN 可用 {version} 占位版本）',
                ),
                onChanged: (_) => setDialogState(() {}),
              ),
              const SizedBox(height: MochiCatSpacing.md),
              Text(
                '预览：$resolved',
                style: TextStyle(
                  fontSize: 12,
                  color: MochiCatPalette.of(context).textSecondary,
                ),
              ),
            ],
          );
        },
      ),
      actions: [
        MochiButton(
          label: '取消',
          type: MochiButtonType.ghost,
          onPressed: () => Navigator.pop(context, false),
        ),
        MochiButton(
          label: '保存',
          icon: AppIcons.save,
          type: MochiButtonType.primary,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );

    if (saved == true) {
      final name = nameController.text.trim();
      final url = urlController.text.trim();
      if (url.isEmpty) {
        _showMessage('地址不能为空');
      } else {
        final newRepo = Repo(
          id: repo?.id ?? newId(),
          name: name.isEmpty
              ? deriveRepoName(url, version: group.version)
              : name,
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
    await disposeAfterDialog([nameController, urlController]);
  }

  Future<void> _showImportDialog(RepoGroup group) async {
    final textController = TextEditingController();
    final versionController = TextEditingController();
    var versionTouched = false;
    final groups = ref.read(repoGroupsProvider);
    var targetGroupId = group.id;

    final saved = await showMochiDialog<bool>(
      context: context,
      title: '批量导入仓库',
      subtitle: '粘贴地址，小猫帮你识别并排重。',
      emoji: '📥',
      width: 540,
      content: StatefulBuilder(
        builder: (context, setDialogState) {
          final version = versionController.text.trim();
          final preview = parseBatch(
            textController.text,
            version: version.isEmpty ? null : version,
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MochiSelectField<String>(
                value: targetGroupId,
                items: [
                  for (final g in groups) (g.id, g.name),
                ],
                label: '导入到分组',
                onChanged: (v) =>
                    setDialogState(() => targetGroupId = v ?? group.id),
              ),
              const SizedBox(height: MochiCatSpacing.md),
              TextField(
                controller: textController,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '粘贴地址（每行一个）',
                  alignLabelWithHint: true,
                ),
                onChanged: (_) => setDialogState(() {
                  if (!versionTouched) {
                    final detected = detectVersion(
                      _nonEmptyLines(textController.text),
                    );
                    versionController.text = detected ?? '';
                  }
                }),
              ),
              const SizedBox(height: MochiCatSpacing.md),
              TextField(
                controller: versionController,
                decoration: const InputDecoration(
                  labelText: '版本号（自动识别，可修改）',
                ),
                onChanged: (_) =>
                    setDialogState(() => versionTouched = true),
              ),
              const SizedBox(height: MochiCatSpacing.md),
              if (preview.isNotEmpty) ...[
                Text(
                  '识别到 ${preview.length} 个仓库：',
                  style: TextStyle(
                    fontSize: 12,
                    color: MochiCatPalette.of(context).textSecondary,
                  ),
                ),
                const SizedBox(height: MochiCatSpacing.sm),
                SizedBox(
                  height: 130,
                  child: ListView.builder(
                    itemCount: preview.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '${preview[i].type.label}  ${preview[i].name}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
      actions: [
        MochiButton(
          label: '取消',
          type: MochiButtonType.ghost,
          onPressed: () => Navigator.pop(context, false),
        ),
        MochiButton(
          label: '导入',
          icon: AppIcons.importExport,
          type: MochiButtonType.primary,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
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
    await disposeAfterDialog([textController, versionController]);
  }

  Future<void> _deleteGroup(RepoGroup group) async {
    final ok = await showDeleteConfirm(
      context,
      title: '确认删除分组？',
      description: '分组「${group.name}」及其下所有仓库将一并删除。',
    );
    if (ok) {
      ref.read(repoGroupsProvider.notifier).deleteGroup(group.id);
    }
  }

  Future<void> _deleteRepo(RepoGroup group, Repo repo) async {
    final ok = await showDeleteConfirm(
      context,
      title: '确认删除仓库？',
      description: '仓库「${repo.name}」将从分组中移除。',
    );
    if (ok) {
      ref.read(repoGroupsProvider.notifier).deleteRepo(group.id, repo.id);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  List<String> _nonEmptyLines(String text) => text
      .split(RegExp(r'\r?\n'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

/// 面板右侧拖拽分隔条：拖动调整左侧分组栏宽度。
class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: const SizedBox(width: 6),
      ),
    );
  }
}

class _RepositoryHeader extends StatelessWidget {
  const _RepositoryHeader();

  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);
    return Row(
      children: [
        // 猫咪徽标（页面标题图形）
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: p.creamSoft,
            borderRadius: BorderRadius.circular(MochiCatRadius.lg),
          ),
          alignment: Alignment.center,
          child: const Text('😺', style: TextStyle(fontSize: 23)),
        ),
        const SizedBox(width: MochiCatSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '代码仓库管理',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                '把项目收进小抽屉，清清爽爽地管理每一次拉取。',
                style: TextStyle(fontSize: 12, color: p.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

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
    final p = MochiCatPalette.of(context);
    return Container(
      width: width,
      height: compact ? 200 : null,
      padding: const EdgeInsets.all(MochiCatSpacing.lg),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(MochiCatRadius.xl),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                '我的分组',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '新增分组',
                icon: const Icon(AppIcons.add, size: 18),
                onPressed: onAdd,
              ),
            ],
          ),
          const SizedBox(height: MochiCatSpacing.sm),
          Expanded(
            child: groups.isEmpty
                ? _EmptyHint(
                    icon: AppIcons.folderOpen,
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
                      width: compact ? MochiCatSpacing.sm : 0,
                      height: compact ? 0 : MochiCatSpacing.sm,
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
    final p = MochiCatPalette.of(context);
    return SizedBox(
      width: compact ? 190 : null,
      child: Material(
        color: selected ? p.primarySoft : p.surfaceMuted,
        borderRadius: BorderRadius.circular(MochiCatRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(MochiCatRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MochiCatSpacing.md,
              vertical: MochiCatSpacing.sm + 2,
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
                        : p.textSecondary.withValues(alpha: .3),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: MochiCatSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected ? p.primary : p.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${group.version == null ? '未设置版本' : 'V${group.version}'}  ·  ${group.repos.length} 个仓库',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: p.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '分组操作',
                  padding: EdgeInsets.zero,
                  iconSize: 17,
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑分组')),
                    PopupMenuItem(value: 'delete', child: Text('删除分组')),
                  ],
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

  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);
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
      padding: const EdgeInsets.all(MochiCatSpacing.xl),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(MochiCatRadius.xl),
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
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: MochiCatSpacing.sm),
              _VersionBadge(
                version: widget.group.version,
                onEdit: widget.onEditVersion,
              ),
            ],
          ),
          const SizedBox(height: MochiCatSpacing.lg),
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
              const SizedBox(width: MochiCatSpacing.md),
              Expanded(
                child: _RemoteCard(group: widget.group, onEdit: widget.onSetupRemote),
              ),
            ],
          ),
          const SizedBox(height: MochiCatSpacing.lg),
          // 操作按钮：本地拉取 / 远程拉取 / 新增仓库 / 批量导入
          // 强制同一行（Row + 等宽均分），颜色统一协调。
          Row(
            children: [
              Expanded(
                child: MochiButton(
                  label: '本地拉取',
                  icon: AppIcons.download,
                  expanded: true,
                  loading: pulling,
                  onPressed: pulling ? null : widget.onPull,
                ),
              ),
              const SizedBox(width: MochiCatSpacing.sm),
              Expanded(
                child: MochiButton(
                  label: widget.remotePulling ? '远程拉取中…' : '远程拉取',
                  icon: AppIcons.cloudDownload,
                  expanded: true,
                  loading: widget.remotePulling,
                  onPressed: widget.remotePulling
                      ? null
                      : widget.group.remotes.isEmpty
                      ? widget.onSetupRemote
                      : widget.onDeploy,
                ),
              ),
              const SizedBox(width: MochiCatSpacing.sm),
              Expanded(
                child: MochiButton(
                  label: '新增仓库',
                  icon: AppIcons.add,
                  expanded: true,
                  onPressed: widget.onAdd,
                ),
              ),
              const SizedBox(width: MochiCatSpacing.sm),
              Expanded(
                child: MochiButton(
                  label: '批量导入',
                  icon: AppIcons.playlistAdd,
                  expanded: true,
                  onPressed: widget.onImport,
                ),
              ),
            ],
          ),
          const SizedBox(height: MochiCatSpacing.xl),
          // 仓库清单标题 + 搜索
          Row(
            children: [
              const Text(
                '仓库清单',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: MochiCatSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: MochiCatSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: p.primarySoft,
                  borderRadius: BorderRadius.circular(MochiCatRadius.sm),
                ),
                child: Text(
                  '${filtered.length}/${widget.group.repos.length}',
                  style: TextStyle(
                    fontSize: 11,
                    color: p.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '搜索仓库名称或地址',
                    prefixIcon: const Icon(AppIcons.search, size: 17),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: MochiCatSpacing.md,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MochiCatRadius.sm),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: MochiCatSpacing.md),
          Expanded(
            child: filtered.isEmpty
                ? _EmptyHint(
                    icon: widget.group.repos.isEmpty
                        ? AppIcons.transferBox
                        : AppIcons.noSearchResult,
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
                        const SizedBox(height: MochiCatSpacing.sm),
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
          color: scheme.primary.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(AppflowyRadius.s),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              version == null ? '未设置版本' : '版本 V$version',
              style: textTheme.bodySmall?.copyWith(color: scheme.primary),
            ),
            const SizedBox(width: AppflowySpacing.xs),
            Icon(AppIcons.edit, size: 14, color: scheme.primary),
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
    final scheme = Theme.of(context).colorScheme;
    final configured = localPath != null && localPath!.isNotEmpty;
    return _BindingCard(
      icon: AppIcons.folderOpen,
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
      icon: AppIcons.cloudDownload,
      title: '远程目标',
      value: value,
      color: const Color(0xFF2D9B7D),
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
    final p = MochiCatPalette.of(context);
    return Material(
      color: p.surfaceMuted,
      borderRadius: BorderRadius.circular(MochiCatRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MochiCatRadius.md),
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(
            horizontal: MochiCatSpacing.md,
            vertical: MochiCatSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MochiCatRadius.md),
            border: Border.all(color: p.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 19),
              const SizedBox(width: MochiCatSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 11, color: p.textSecondary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(AppIcons.chevronRight, size: 17, color: p.textSecondary),
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
    final p = MochiCatPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: MochiCatSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: p.border.withValues(alpha: .8)),
        ),
      ),
      child: Row(
        children: [
          _TypeBadge(type: repo.type),
          const SizedBox(width: MochiCatSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  repo.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Tooltip(
                  message: resolvedUrl,
                  child: Text(
                    resolvedUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          if (status != null) ...[
            const SizedBox(width: MochiCatSpacing.md),
            _PullStatusLabel(status: status!),
          ],
          const SizedBox(width: MochiCatSpacing.sm),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '本地拉取 / 更新',
            icon: const Icon(AppIcons.computer, size: 17),
            onPressed: onLocalPull,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '远程拉取 / 更新',
            icon: const Icon(AppIcons.cloudDownload, size: 17),
            onPressed: onRemotePull,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '复制地址',
            icon: const Icon(AppIcons.copy, size: 17),
            onPressed: () => onCopy(resolvedUrl),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '编辑仓库',
            icon: const Icon(AppIcons.edit, size: 17),
            onPressed: onEdit,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '删除仓库',
            icon: const Icon(AppIcons.delete, size: 17),
            onPressed: onDelete,
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
      PullStatus.pending => (MochiCatColors.textSecondary, '待处理'),
      PullStatus.success => (MochiCatColors.mint, '已完成'),
      PullStatus.skipped => (MochiCatColors.textSecondary, '已跳过'),
      PullStatus.failed => (MochiCatColors.danger, '失败'),
      PullStatus.pulling => (MochiCatColors.orange, '拉取中…'),
    };
    if (status == PullStatus.pulling) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
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
          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
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
    final (bg, fg) = type == RepoType.git
        ? (const Color(0xFFFFF0EA), const Color(0xFFE1774D))
        : (const Color(0xFFEDF4FF), const Color(0xFF5282D8));
    return Container(
      width: 46,
      padding: const EdgeInsets.symmetric(
        horizontal: MochiCatSpacing.sm,
        vertical: MochiCatSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MochiCatRadius.xs),
      ),
      child: Text(
        type.label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({
    required this.icon,
    required this.text,
    required this.detail,
    this.onAction,
    this.actionLabel,
    this.compact = false,
  });

  final IconData icon;
  final String text;
  final String detail;
  final VoidCallback? onAction;
  final String? actionLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MochiCatSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: compact ? 26 : 40,
              color: p.primary.withValues(alpha: .55),
            ),
            const SizedBox(height: MochiCatSpacing.md),
            Text(
              text,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: MochiCatSpacing.xs),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: p.textSecondary),
            ),
            if (onAction != null) ...[
              const SizedBox(height: MochiCatSpacing.md),
              MochiButton(
                label: actionLabel ?? '开始',
                type: MochiButtonType.primary,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
