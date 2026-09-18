import 'dart:async';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:toolbox/features/remote/remote_controller.dart';
import 'package:toolbox/features/remote/remote_models.dart';
import 'package:toolbox/features/repository/pull_controller.dart';
import 'package:toolbox/features/repository/repo_controller.dart';
import 'package:toolbox/features/repository/repo_deploy.dart';
import 'package:toolbox/features/repository/repo_detection.dart';
import 'package:toolbox/features/repository/repo_models.dart';
import 'package:toolbox/features/repository/svn_client.dart';
import 'package:toolbox/ui/theme/app_layout.dart';
import 'package:toolbox/ui/widgets/app_dialog.dart';
import 'package:toolbox/ui/widgets/app_empty_hint.dart';
import 'package:toolbox/ui/widgets/app_form_row.dart';
import 'package:toolbox/ui/widgets/app_resize_handle.dart';
import 'package:toolbox/ui/widgets/app_toast.dart';
import 'package:toolbox/ui/widgets/app_tooltip.dart';
import 'package:toolbox/ui/widgets/tile_icon_button.dart';

part 'repo_panels.dart';
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
          final padding = compact ? AppLayout.gapLg : 28.0;
          return Padding(
            padding: EdgeInsets.fromLTRB(padding, 20, padding, padding),
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
                  AppResizeHandle(
                    onDrag: (dx) => setState(
                      () => _groupPanelWidth =
                          (_groupPanelWidth + dx).clamp(190.0, 420.0),
                    ),
                  ),
                  const SizedBox(width: AppLayout.gapSm),
                ],
                Expanded(
                  child: selected == null
                      ? const AppEmptyHint(
                          icon: FLucideIcons.folderOpen,
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
                          onEditVersion: () => _showVersionDialog(selected),
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
          );
        },
      ),
    );
  }

  Future<void> _copyRepo(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showAppToast(context, '已复制：$text');
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
      unawaited(_setupRemote(group));
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

    final saved = await showAppDialog<bool>(
      context: context,
      title: '远程拉取设置：${connName()}',
      subtitle: '选择 SSH 连接并填写远程目录与 SVN 账号。',
      width: dialogWidthMedium,
      content: StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppFormRow(
              label: 'SSH 连接',
              description: '远程拉取时使用哪台服务器执行 svn 命令',
              child: FSelect<String>(
                control: FSelectControl<String>.lifted(
                  value: connectionId,
                  onChange: (v) {
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
                items: {
                  for (final c in connections) '${c.name} (${c.hostLabel})': c.id,
                },
              ),
            ),
            const SizedBox(height: AppLayout.gapMd),
            AppFormRow(
              label: '远程目录',
              description: '服务器上存放代码的目录，例如 /home/user/code',
              child: FTextField(
                control: FTextFieldControl.managed(
                  controller: pathController,
                ),
              ),
            ),
            const SizedBox(height: AppLayout.gapMd),
            const FDivider(),
            const SizedBox(height: AppLayout.gapMd),
            AppFormRow(
              label: 'SVN 账号',
              description: '可选。SVN 检出/更新的账号，本地与远程拉取共用',
              child: FTextField(
                control: FTextFieldControl.managed(
                  controller: svnUserController,
                ),
              ),
            ),
            const SizedBox(height: AppLayout.gapMd),
            AppFormRow(
              label: 'SVN 密码',
              description: '可选。SVN 账号对应的密码，仅保存在本机',
              child: FTextField(
                control: FTextFieldControl.managed(
                  controller: svnPassController,
                ),
                obscureText: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        FButton(
          mainAxisSize: MainAxisSize.min,
          variant: FButtonVariant.ghost,
          onPress: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FButton(
          mainAxisSize: MainAxisSize.min,
          variant: FButtonVariant.primary,
          onPress: () => Navigator.pop(context, true),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FLucideIcons.save, size: 16),
              SizedBox(width: 6),
              Text('保存'),
            ],
          ),
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
      unawaited(_setupRemote(group));
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
    final saved = await showAppDialog<bool>(
      context: context,
      title: 'SVN 仓库需要认证',
      width: dialogWidthSmall,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppFormRow(
            label: '用户名',
            description: 'SVN 认证用户名',
            child: FTextField(
              control: FTextFieldControl.managed(
                controller: userController,
              ),
            ),
          ),
          const SizedBox(height: AppLayout.gapMd),
          AppFormRow(
            label: '密码',
            description: 'SVN 认证密码，仅保存在本机',
            child: FTextField(
              control: FTextFieldControl.managed(
                controller: passController,
              ),
              obscureText: true,
            ),
          ),
        ],
      ),
      actions: [
        FButton(
          mainAxisSize: MainAxisSize.min,
          variant: FButtonVariant.ghost,
          onPress: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FButton(
          mainAxisSize: MainAxisSize.min,
          variant: FButtonVariant.primary,
          onPress: () => Navigator.pop(context, true),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FLucideIcons.check, size: 16),
              SizedBox(width: 6),
              Text('确认'),
            ],
          ),
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
    // 校验前移：分组名必填，不合法时「保存」置灰。
    final form = DialogFormState();
    void revalidate() => form.check(
      () => nameController.text.trim().isEmpty ? '请填写分组名' : null,
    );

    final saved = await showAppDialog<bool>(
      context: context,
      title: group == null ? '新建分组' : '编辑分组',
      width: dialogWidthSmall,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppFormRow(
            label: '分组名',
            description: '用于归集相关仓库，例如按项目或版本命名',
            child: FTextField(
              control: FTextFieldControl.managed(
                controller: nameController,
                onChange: (_) => revalidate(),
              ),
              autofocus: group == null,
            ),
          ),
          const SizedBox(height: AppLayout.gapMd),
          AppFormRow(
            label: '版本号',
            description: '可选。用于替换仓库地址里的 {version} 占位符，如 2.8',
            child: FTextField(
              control: FTextFieldControl.managed(
                controller: versionController,
              ),
            ),
          ),
          DialogFormHint(state: form),
        ],
      ),
      actions: [
        FButton(
          mainAxisSize: MainAxisSize.min,
          variant: FButtonVariant.ghost,
          onPress: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        ListenableBuilder(
          listenable: form,
          builder: (context, _) => FButton(
            mainAxisSize: MainAxisSize.min,
            variant: FButtonVariant.primary,
            // 校验未通过时置灰：不再「保存后弹窗关闭、刚填的内容全丢」。
            onPress: form.canSubmit
                ? () => Navigator.pop(context, true)
                : null,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FLucideIcons.save, size: 16),
                SizedBox(width: 6),
                Text('保存'),
              ],
            ),
          ),
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
    final saved = await showAppDialog<bool>(
      context: context,
      title: '设置版本号',
      width: dialogWidthSmall,
      content: AppFormRow(
        label: '版本号',
        description: '用于替换仓库地址里的 {version} 占位符，如 2.8',
        child: FTextField(
          control: FTextFieldControl.managed(
            controller: controller,
          ),
          autofocus: true,
        ),
      ),
      actions: [
        FButton(
          mainAxisSize: MainAxisSize.min,
          variant: FButtonVariant.ghost,
          onPress: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FButton(
          mainAxisSize: MainAxisSize.min,
          variant: FButtonVariant.primary,
          onPress: () => Navigator.pop(context, true),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FLucideIcons.save, size: 16),
              SizedBox(width: 6),
              Text('保存'),
            ],
          ),
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

    // 校验前移：仓库地址必填。
    final form = DialogFormState();
    void revalidate() => form.check(
      () => urlController.text.trim().isEmpty ? '请填写仓库地址' : null,
    );

    final saved = await showAppDialog<bool>(
      context: context,
      title: repo == null ? '新增仓库' : '编辑仓库',
      width: dialogWidthMedium,
      content: StatefulBuilder(
        builder: (context, setDialogState) {
          final resolved = resolveUrl(urlController.text.trim(), group.version);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppFormRow(
                label: '仓库名',
                description: '列表中显示的仓库名称，留空时自动从地址推导',
                child: FTextField(
                  control: FTextFieldControl.managed(
                    controller: nameController,
                  ),
                ),
              ),
              const SizedBox(height: AppLayout.gapMd),
              AppFormRow(
                label: '仓库类型',
                description: 'Git / SVN 仓库',
                child: FSelect<RepoType>(
                  control: FSelectControl<RepoType>.lifted(
                    value: type,
                    onChange: (v) =>
                        setDialogState(() => type = v ?? RepoType.git),
                  ),
                  items: {for (final t in RepoType.values) t.label: t},
                ),
              ),
              const SizedBox(height: AppLayout.gapMd),
              AppFormRow(
                label: '仓库地址',
                description: 'Git/SVN 仓库地址；可用 {version} 占位分组版本号',
                child: FTextField(
                  control: FTextFieldControl.managed(
                    controller: urlController,
                    onChange: (_) {
                      setDialogState(() {});
                      revalidate();
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppLayout.gapMd),
              Text(
                '预览：$resolved',
                style: context.theme.typography.body.sm.copyWith(
                  color: context.theme.colors.mutedForeground,
                ),
              ),
              DialogFormHint(state: form),
            ],
          );
        },
      ),
      actions: [
        FButton(
          mainAxisSize: MainAxisSize.min,
          variant: FButtonVariant.ghost,
          onPress: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        ListenableBuilder(
          listenable: form,
          builder: (context, _) => FButton(
            mainAxisSize: MainAxisSize.min,
            variant: FButtonVariant.primary,
            // 校验未通过时置灰：不再「保存后弹窗关闭、刚填的内容全丢」。
            onPress: form.canSubmit
                ? () => Navigator.pop(context, true)
                : null,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FLucideIcons.save, size: 16),
                SizedBox(width: 6),
                Text('保存'),
              ],
            ),
          ),
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
    // 校验前移：至少粘一个能被识别出来的地址，否则「导入」置灰。
    final form = DialogFormState();
    void revalidate() => form.check(
      () => parseBatch(
        textController.text,
        version: versionController.text.trim().isEmpty
            ? null
            : versionController.text.trim(),
      ).isEmpty
          ? '请粘贴至少一个仓库地址'
          : null,
    );

    final saved = await showAppDialog<bool>(
      context: context,
      title: '批量导入仓库',
      // 入口就在某个分组里，因此不再让用户选分组（导入目标即当前分组）。
      subtitle: '粘贴地址，自动识别并排重后导入「${group.name}」。',
      width: dialogWidthLarge,
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
              AppFormRow(
                label: '粘贴地址',
                description: '每行一个仓库地址，会自动识别 Git/SVN 并去重',
                child: FTextField(
                  control: FTextFieldControl.managed(
                    controller: textController,
                    onChange: (_) {
                      revalidate();
                      setDialogState(() {
                        if (!versionTouched) {
                          final detected = detectVersion(
                            _nonEmptyLines(textController.text),
                          );
                          versionController.text = detected ?? '';
                        }
                      });
                    },
                  ),
                  maxLines: 6,
                ),
              ),
              const SizedBox(height: AppLayout.gapMd),
              AppFormRow(
                label: '版本号',
                description: '从粘贴的地址中自动识别，可手动修改',
                child: FTextField(
                  control: FTextFieldControl.managed(
                    controller: versionController,
                    onChange: (_) => setDialogState(() => versionTouched = true),
                  ),
                ),
              ),
              const SizedBox(height: AppLayout.gapMd),
              if (preview.isNotEmpty) ...[
                Text(
                  '识别到 ${preview.length} 个仓库：',
                  style: context.theme.typography.body.xs.copyWith(color: context.theme.colors.mutedForeground),
                ),
                const SizedBox(height: AppLayout.gapSm),
                SizedBox(
                  height: 130,
                  child: ListView.builder(
                    itemCount: preview.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '${preview[i].type.label}  ${preview[i].name}',
                        style: context.theme.typography.body.sm,
                      ),
                    ),
                  ),
                ),
                DialogFormHint(state: form),
              ],
            ],
          );
        },
      ),
      actions: [
        FButton(
          mainAxisSize: MainAxisSize.min,
          variant: FButtonVariant.ghost,
          onPress: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        ListenableBuilder(
          listenable: form,
          builder: (context, _) => FButton(
            mainAxisSize: MainAxisSize.min,
            variant: FButtonVariant.primary,
            // 校验未通过时置灰：不再「保存后弹窗关闭、刚填的内容全丢」。
            onPress: form.canSubmit
                ? () => Navigator.pop(context, true)
                : null,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FLucideIcons.arrowUpDown, size: 16),
                SizedBox(width: 6),
                Text('导入'),
              ],
            ),
          ),
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
            .importRepos(group.id, repos, version: v);
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
    showAppToast(context, message);
  }

  List<String> _nonEmptyLines(String text) => text
      .split(RegExp(r'\r?\n'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}
