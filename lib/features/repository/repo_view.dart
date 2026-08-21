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
import 'package:toolbox/ui/theme/appflowy_colors.dart';

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
                      remotePulling: _remotePulling,
                      onAdd: () => _showRepoDialog(selected),
                      onEdit: (repo) => _showRepoDialog(selected, repo: repo),
                      onDelete: (repo) => _deleteRepo(selected, repo),
                      onImport: () => _showImportDialog(selected),
                      onEditVersion: () => _showVersionDialog(selected),
                      onPickPath: () => _pickLocalPath(selected),
                      onPull: () => _pullGroup(selected),
                      onSetupRemote: () => _setupRemote(selected),
                      onDeploy: () => _deployGroup(selected),
                      onLocalPullRepo: (repo) => _pullOneLocal(selected, repo),
                      onRemotePullRepo: (repo) =>
                          _pullOneRemote(selected, repo),
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
    final actionLabel = {
      'checkout': '首次拉取(checkout)',
      'update': '更新(update)',
    };
    final detail = summary.results
        .map((r) => '${r.repoName}：${actionLabel[r.action] ?? r.action} '
            '${r.ok ? '成功' : '失败'}')
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
        await ref.read(svnRunnerProvider)(
          ['update', '--non-interactive', target],
        );
      } else {
        await ref.read(svnRunnerProvider)(
          ['checkout', '--non-interactive', url, target],
        );
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
    final connId = group.activeRemoteConnId != null &&
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
              ? await remoteSvnUpdate(client, dir,
                  username: cred.$1, password: cred.$2)
              : await remoteSvnCheckout(client, url, dir,
                  username: cred.$1, password: cred.$2);
        }
      }
      await client.close();
      if (result.success) {
        controller.setRepoStatus(repo.id, PullStatus.success);
        _showMessage('${repo.name}：${isWorkingCopy ? '更新' : '首次拉取'}成功 → $dir');
      } else {
        controller.setRepoStatus(repo.id, PullStatus.failed);
        _showMessage('${repo.name}：${isWorkingCopy ? '更新' : '首次拉取'}失败\n'
            '${result.output}');
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
    final pathController =
        TextEditingController(text: initBinding?.remotePath ?? '');
    final svnUserController =
        TextEditingController(text: initBinding?.svnUsername ?? '');
    final svnPassController =
        TextEditingController(text: initBinding?.svnPassword ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('远程拉取设置：${connName()}'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButton<String>(
                  value: connectionId,
                  isExpanded: true,
                  items: [
                    for (final c in connections)
                      DropdownMenuItem(
                        value: c.id,
                        child: Text('${c.name} (${c.hostLabel})'),
                      ),
                  ],
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
                const SizedBox(height: AppflowySpacing.m),
                TextField(
                  controller: pathController,
                  decoration: const InputDecoration(
                    labelText: '远程目录（如 /home/user/code）',
                  ),
                ),
                const SizedBox(height: AppflowySpacing.m),
                const Divider(height: 1),
                const SizedBox(height: AppflowySpacing.m),
                TextField(
                  controller: svnUserController,
                  decoration: const InputDecoration(
                    labelText: 'SVN 账号（可选，远程拉取共用）',
                  ),
                ),
                const SizedBox(height: AppflowySpacing.m),
                TextField(
                  controller: svnPassController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'SVN 密码（可选）',
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
      ),
    );
    // 先取值再 dispose（controller 在 await 后仍可读，但应在 dispose 前取）。
    final remotePathText = pathController.text;
    final svnUserText = svnUserController.text.trim();
    final svnPassText = svnPassController.text;
    pathController.dispose();
    svnUserController.dispose();
    svnPassController.dispose();

    if (saved == true) {
      ref.read(repoGroupsProvider.notifier).setGroupRemote(
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
    final connId = group.activeRemoteConnId != null &&
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
              ? await remoteSvnUpdate(client, dir,
                  username: cred.$1, password: cred.$2)
              : await remoteSvnCheckout(client, url, dir,
                  username: cred.$1, password: cred.$2);
        }
      }
      if (result.success) {
        success++;
        pullCtrl.setRepoStatus(repo.id, PullStatus.success);
        results.add('${repo.name}：'
            '${isWorkingCopy ? 'update' : 'checkout'} 成功 → $dir');
      } else {
        failed++;
        pullCtrl.setRepoStatus(repo.id, PullStatus.failed);
        results.add('${repo.name}：'
            '${isWorkingCopy ? 'update' : 'checkout'} 失败\n${result.output}');
      }
    }
    try {
      await client.close();
    } catch (_) {}
    if (!mounted) return;
    _showMessage('远程拉取完成：成功 $success 个，失败 $failed 个\n'
        '${results.join('\n')}');
  }

  /// 弹框输入 SVN 仓库账号密码。
  Future<(String, String)?> _promptSvnCredentials() async {
    final userController = TextEditingController();
    final passController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('SVN 仓库需要认证'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: userController,
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              const SizedBox(height: AppflowySpacing.m),
              TextField(
                controller: passController,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密码'),
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
            child: const Text('确认'),
          ),
        ],
      ),
    );
    final cred = saved == true
        ? (userController.text.trim(), passController.text)
        : null;
    userController.dispose();
    passController.dispose();
    return cred;
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

  /// 远程拉取进行中（控制远程按钮加载动画）。
  final bool remotePulling;
  final VoidCallback onAdd;
  final ValueChanged<Repo> onEdit;
  final ValueChanged<Repo> onDelete;
  final VoidCallback onImport;
  final VoidCallback onEditVersion;
  final VoidCallback onPickPath;
  final VoidCallback onPull;
  final ValueChanged<String> onCopy;

  /// 配置远程拉取绑定（SSH 连接 + 远程目录）。
  final VoidCallback onSetupRemote;

  /// 一键远程拉取。
  final VoidCallback onDeploy;

  /// 单仓库本地拉取/更新。
  final ValueChanged<Repo> onLocalPullRepo;

  /// 单仓库远程拉取/更新。
  final ValueChanged<Repo> onRemotePullRepo;

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
            const Spacer(),
            OutlinedButton.icon(
              icon: pulling
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download, size: 18),
              label: const Text('本地拉取'),
              onPressed: pulling ? null : onPull,
            ),
            const SizedBox(width: AppflowySpacing.s),
            OutlinedButton.icon(
              icon: remotePulling
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_outlined, size: 18),
              label: const Text('远程拉取'),
              onPressed: remotePulling
                  ? null
                  : group.remotes.isEmpty
                      ? onSetupRemote
                      : onDeploy,
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
        // 本地 / 远程徽标并排同一行，分别标注。
        const SizedBox(height: AppflowySpacing.s),
        Row(
          children: [
            _LocalPathBadge(localPath: group.localPath, onPick: onPickPath),
            const SizedBox(width: AppflowySpacing.s),
            _RemoteBadge(group: group, onEdit: onSetupRemote),
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
                      onLocalPull: () => onLocalPullRepo(repo),
                      onRemotePull: () => onRemotePullRepo(repo),
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

    // 徽标显示「本地：」+ 文件夹末段，完整路径放 tooltip。
    final display = localPath == null
        ? '未绑定'
        : '本地：${localPath!.split(RegExp(r'[/\\]')).last}';

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

/// 远程拉取绑定徽标：显示绑定的 SSH 连接与远程目录。
class _RemoteBadge extends ConsumerWidget {
  const _RemoteBadge({required this.group, required this.onEdit});

  final RepoGroup group;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    // 显示当前远程拉取目标连接名（activeRemoteConnId，无则第一个绑定）。
    final connections = ref.watch(sshConnectionsProvider);
    final activeId = group.activeRemoteConnId != null &&
            group.remotes.containsKey(group.activeRemoteConnId)
        ? group.activeRemoteConnId
        : (group.remotes.isNotEmpty ? group.remotes.keys.first : null);
    String connName = '未设置';
    if (activeId != null) {
      connName = activeId;
      for (final c in connections) {
        if (c.id == activeId) {
          connName = c.name;
          break;
        }
      }
    }

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(AppflowyRadius.s),
      child: Tooltip(
        message: '远程拉取：$connName',
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppflowySpacing.m,
            vertical: AppflowySpacing.xs,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF00897B).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppflowyRadius.s),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_outlined, size: 14, color: const Color(0xFF00897B)),
              const SizedBox(width: AppflowySpacing.xs),
              Text(
                '远程：$connName',
                style: textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF00897B),
                ),
              ),
              const SizedBox(width: AppflowySpacing.xs),
              Icon(Icons.edit_outlined, size: 14, color: const Color(0xFF00897B)),
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

  /// 单仓库本地拉取/更新。
  final VoidCallback onLocalPull;

  /// 单仓库远程拉取/更新。
  final VoidCallback onRemotePull;

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
          // 单仓库操作：本地 / 远程。
          IconButton(
            icon: const Icon(Icons.computer, size: 18),
            tooltip: '本地拉取/更新',
            onPressed: onLocalPull,
          ),
          IconButton(
            icon: const Icon(Icons.cloud_download_outlined, size: 18),
            tooltip: '远程拉取/更新',
            onPressed: onRemotePull,
          ),
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
