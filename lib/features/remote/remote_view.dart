import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/features/monitor/monitor_controller.dart';
import 'package:toolbox/features/monitor/monitor_models.dart';
import 'package:toolbox/features/remote/remote_controller.dart';
import 'package:toolbox/features/remote/remote_models.dart';
import 'package:toolbox/features/remote/sftp_view.dart';
import 'package:toolbox/features/remote/ssh_session.dart';
import 'package:toolbox/ui/theme/app_icons.dart';
import 'package:toolbox/ui/theme/mochi_cat_tokens.dart';
import 'package:toolbox/ui/widgets/mochi_widgets.dart';
import 'package:xterm/xterm.dart';

/// 远程管理页：左侧连接列表，右侧多开 SSH 会话。
///
/// 布局（糯米猫设计稿）：上半区终端与文件永久并排各占 50%，
/// 下半区服务器监控默认展开、可折叠；终端/文件/监控状态同时保活。
class RemoteView extends ConsumerStatefulWidget {
  const RemoteView({super.key});

  @override
  ConsumerState<RemoteView> createState() => _RemoteViewState();
}

class _RemoteViewState extends ConsumerState<RemoteView> {
  String? _activeSessionId;
  bool _panelVisible = true;

  @override
  Widget build(BuildContext context) {
    final connections = ref.watch(sshConnectionsProvider);
    final sessions = ref.watch(sshSessionsProvider);

    // 当前会话（若已被关闭则清空选中）。
    String? activeId = _activeSessionId;
    if (activeId != null && !sessions.containsKey(activeId)) {
      activeId = sessions.isNotEmpty ? sessions.keys.last : null;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(MochiCatSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_panelVisible) ...[
              _ConnectionPanel(
                connections: connections,
                activeId: activeId,
                onSelect: (id) => setState(() => _activeSessionId = id),
                onAdd: _showConnectionDialog,
                onEdit: (conn) => _showConnectionDialog(connection: conn),
                onDelete: (conn) => _deleteConnection(conn),
                onConnect: (conn) => _openSession(conn),
                onToggle: () => setState(() => _panelVisible = false),
              ),
              const SizedBox(width: MochiCatSpacing.md),
            ],
            Expanded(
              child: sessions.isEmpty
                  ? Stack(
                      children: [
                        if (!_panelVisible)
                          Positioned(
                            top: 0,
                            left: 0,
                            child: IconButton(
                              icon: const Icon(AppIcons.menuOpen),
                              tooltip: '显示连接面板',
                              onPressed: () =>
                                  setState(() => _panelVisible = true),
                            ),
                          ),
                        Center(
                          child: _EmptyHint(
                            icon: AppIcons.pets,
                            text: '还没有打开的会话',
                            detail: '在左侧选择连接，或点击连接按钮打开 SSH 会话',
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SessionTabBar(
                          sessions: sessions,
                          activeId: activeId,
                          onActivate: (id) =>
                              setState(() => _activeSessionId = id),
                          onClose: (id) => _closeSession(id),
                          onAdd: _showConnectionDialog,
                          onTogglePanel: () =>
                              setState(() => _panelVisible = true),
                          panelVisible: _panelVisible,
                        ),
                        if (sessions.isNotEmpty)
                          Expanded(
                            child: IndexedStack(
                              // 有会话但未选中时默认激活最后一个，避免 index -1。
                              index: sessions.keys
                                  .toList()
                                  .indexOf(activeId ?? sessions.keys.last),
                              children: [
                                for (final entry in sessions.entries)
                                  _SessionContent(
                                    key: ValueKey(entry.value.connection.id),
                                    handle: entry.value,
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSession(SshConnection connection) async {
    setState(() => _activeSessionId = connection.id);
    await ref.read(sshSessionsProvider.notifier).open(connection);
  }

  void _closeSession(String id) {
    ref.read(sshSessionsProvider.notifier).close(id);
    setState(() {
      if (_activeSessionId == id) _activeSessionId = null;
    });
  }

  Future<void> _showConnectionDialog({SshConnection? connection}) async {
    final nameController = TextEditingController(text: connection?.name ?? '');
    final hostController = TextEditingController(text: connection?.host ?? '');
    final portController = TextEditingController(
      text: connection?.port.toString() ?? '22',
    );
    final usernameController =
        TextEditingController(text: connection?.username ?? '');
    final passwordController =
        TextEditingController(text: connection?.password ?? '');
    final keyPathController =
        TextEditingController(text: connection?.privateKeyPath ?? '');
    final passphraseController =
        TextEditingController(text: connection?.keyPassphrase ?? '');
    var useKeyAuth = connection?.useKeyAuth ?? false;
    // 弹窗内测试连接状态：必须在 StatefulBuilder 内部管理，
    // 外层 setState 不会重建弹窗内容（否则按钮 loading/结果无反馈）。
    var testing = false;
    String? testResult;

    final saved = await showMochiDialog<bool>(
      context: context,
      title: connection == null ? '新建 SSH 连接' : '编辑 SSH 连接',
      subtitle: '填写服务器信息，小猫会帮你先测试连接。',
      emoji: '🐱',
      content: SingleChildScrollView(
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            final textTheme = Theme.of(context).textTheme;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: connection == null,
                  decoration: const InputDecoration(labelText: '连接名称'),
                ),
                const SizedBox(height: MochiCatSpacing.md),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: hostController,
                        decoration: const InputDecoration(labelText: '主机地址'),
                      ),
                    ),
                    const SizedBox(width: MochiCatSpacing.md),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: portController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(labelText: '端口'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MochiCatSpacing.md),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(labelText: '用户名'),
                ),
                const SizedBox(height: MochiCatSpacing.md),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '密码（密钥认证时可留空）',
                  ),
                ),
                const SizedBox(height: MochiCatSpacing.md),
                // 认证方式：密码 / 私钥
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('密码')),
                    ButtonSegment(value: true, label: Text('私钥')),
                  ],
                  selected: {useKeyAuth},
                  onSelectionChanged: (s) =>
                      setDialogState(() => useKeyAuth = s.first),
                ),
                const SizedBox(height: MochiCatSpacing.md),
                if (useKeyAuth) ...[
                  TextField(
                    controller: keyPathController,
                    decoration: const InputDecoration(
                      labelText: '私钥文件（OpenSSH / RSA / EC PEM）',
                    ),
                  ),
                  const SizedBox(height: MochiCatSpacing.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(AppIcons.folderOpen, size: 16),
                      label: const Text('选择私钥文件'),
                      onPressed: () async {
                        final picked = await FilePicker.pickFiles(
                          dialogTitle: '选择 SSH 私钥文件',
                        );
                        if (picked.isEmpty) return;
                        final path = picked.first.path;
                        if (path != null) {
                          setDialogState(
                            () => keyPathController.text = path,
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: MochiCatSpacing.md),
                  TextField(
                    controller: passphraseController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '私钥口令（可选）'),
                  ),
                  const SizedBox(height: MochiCatSpacing.md),
                ],
                if (testResult != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: MochiCatSpacing.sm),
                    child: Row(
                      children: [
                        Icon(
                          testResult!.startsWith('连接成功')
                              ? AppIcons.check
                              : AppIcons.info,
                          size: 15,
                          color: testResult!.startsWith('连接成功')
                              ? const Color(0xFF43AA8B)
                              : const Color(0xFFDF6D7D),
                        ),
                        const SizedBox(width: MochiCatSpacing.sm),
                        Expanded(
                          child: Text(
                            testResult!,
                            style: textTheme.bodySmall?.copyWith(
                              color: testResult!.startsWith('连接成功')
                                  ? const Color(0xFF43AA8B)
                                  : const Color(0xFFDF6D7D),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: MochiCatSpacing.md),
                Align(
                  alignment: Alignment.centerLeft,
                  child: MochiButton(
                    label: '测试连接',
                    icon: AppIcons.sparkles,
                    loading: testing,
                    onPressed: testing
                        ? null
                        : () async {
                            setDialogState(() {
                              testing = true;
                              testResult = null;
                            });
                            final result = await _testConnection(
                              nameController.text,
                              hostController.text,
                              portController.text,
                              usernameController.text,
                              passwordController.text,
                              useKeyAuth: useKeyAuth,
                              keyPath: keyPathController.text,
                              passphrase: passphraseController.text,
                            );
                            if (!mounted) return;
                            setDialogState(() {
                              testing = false;
                              testResult = result;
                            });
                          },
                  ),
                ),
              ],
            );
          },
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

    if (saved == true) {
      final name = nameController.text.trim();
      final host = hostController.text.trim();
      final port = int.tryParse(portController.text) ?? 22;
      final username = usernameController.text.trim();
      final password = passwordController.text;
      final keyPath = keyPathController.text.trim();
      final passphrase = passphraseController.text;
      if (name.isEmpty || host.isEmpty || username.isEmpty) {
        _showMessage('名称、主机、用户名不能为空');
      } else if (useKeyAuth && keyPath.isEmpty) {
        _showMessage('请选择私钥文件');
      } else {
        final notifier = ref.read(sshConnectionsProvider.notifier);
        if (connection == null) {
          notifier.add(SshConnection(
            id: newRemoteId(),
            name: name,
            host: host,
            port: port,
            username: username,
            password: password,
            useKeyAuth: useKeyAuth,
            privateKeyPath: useKeyAuth ? keyPath : null,
            keyPassphrase: useKeyAuth ? passphrase : null,
          ));
        } else {
          notifier.update(connection.copyWith(
            name: name,
            host: host,
            port: port,
            username: username,
            password: password,
            useKeyAuth: useKeyAuth,
            privateKeyPath: useKeyAuth ? keyPath : null,
            keyPassphrase: useKeyAuth ? passphrase : null,
          ));
        }
      }
    }
    await disposeAfterDialog([
      nameController,
      hostController,
      portController,
      usernameController,
      passwordController,
      keyPathController,
      passphraseController,
    ]);
  }

  Future<void> _deleteConnection(SshConnection connection) async {
    final ok = await showDeleteConfirm(
      context,
      title: '确认删除？',
      description: '连接「${connection.name}」将从列表移除。',
    );
    if (ok) {
      _closeSession(connection.id);
      ref.read(sshConnectionsProvider.notifier).delete(connection.id);
    }
  }

  /// 用弹窗中的输入做一次真实连接测试，成功/失败返回结果文本。
  Future<String> _testConnection(
    String name,
    String host,
    String portText,
    String username,
    String password, {
    bool useKeyAuth = false,
    String keyPath = '',
    String passphrase = '',
  }) async {
    if (name.trim().isEmpty || host.trim().isEmpty || username.trim().isEmpty) {
      return '请先填写名称、主机、用户名';
    }
    try {
      final client = await defaultSshConnector(SshConnection(
        id: newRemoteId(),
        name: name.trim(),
        host: host.trim(),
        port: int.tryParse(portText) ?? 22,
        username: username.trim(),
        password: password,
        useKeyAuth: useKeyAuth,
        privateKeyPath: useKeyAuth ? keyPath.trim() : null,
        keyPassphrase: useKeyAuth ? passphrase : null,
      ));
      await client.close();
      return '连接成功';
    } catch (e) {
      return '连接失败：$e';
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

/// 左侧连接面板（固定 205px，白底右边框）。
class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({
    required this.connections,
    required this.activeId,
    required this.onSelect,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onConnect,
    required this.onToggle,
  });

  final List<SshConnection> connections;
  final String? activeId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<SshConnection> onEdit;
  final ValueChanged<SshConnection> onDelete;
  final ValueChanged<SshConnection> onConnect;

  /// 收起面板。
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);

    return Container(
      width: MochiCatSize.connectionPanelWidth,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(MochiCatRadius.xl),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MochiCatSpacing.lg,
              MochiCatSpacing.md,
              MochiCatSpacing.sm,
              MochiCatSpacing.sm,
            ),
            child: Row(
              children: [
                const Text(
                  '连接',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(AppIcons.arrowDown, size: 18),
                  tooltip: '收起连接面板',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: MochiCatSize.iconButton,
                    height: MochiCatSize.iconButton,
                  ),
                  onPressed: onToggle,
                ),
                IconButton(
                  icon: const Icon(AppIcons.add, size: 20),
                  tooltip: '新建连接',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: MochiCatSize.iconButton,
                    height: MochiCatSize.iconButton,
                  ),
                  onPressed: onAdd,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: connections.isEmpty
                ? const _EmptyHint(
                    icon: AppIcons.server,
                    text: '暂无连接',
                    detail: '点击右上角 + 新建 SSH 连接',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(MochiCatSpacing.sm),
                    itemCount: connections.length,
                    itemBuilder: (_, i) {
                      final conn = connections[i];
                      return _ConnectionTile(
                        connection: conn,
                        active: conn.id == activeId,
                        onTap: () => onSelect(conn.id),
                        onConnect: () => onConnect(conn),
                        onEdit: () => onEdit(conn),
                        onDelete: () => onDelete(conn),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(MochiCatSpacing.md),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: MochiCatSpacing.md,
                vertical: MochiCatSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: p.creamSoft,
                borderRadius: BorderRadius.circular(MochiCatRadius.md),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.shield, size: 14, color: p.orange),
                  const SizedBox(width: MochiCatSpacing.sm),
                  Expanded(
                    child: Text(
                      '连接信息仅保存在本机',
                      style: TextStyle(fontSize: 11, color: p.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({
    required this.connection,
    required this.active,
    required this.onTap,
    required this.onConnect,
    required this.onEdit,
    required this.onDelete,
  });

  final SshConnection connection;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onConnect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);
    final connection = this.connection;

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: active ? p.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(MochiCatRadius.md),
        child: InkWell(
          onTap: onTap,
          onDoubleTap: onConnect,
          borderRadius: BorderRadius.circular(MochiCatRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MochiCatSpacing.md,
              vertical: MochiCatSpacing.sm + 2,
            ),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: active
                        ? p.mint
                        : p.textSecondary.withValues(alpha: .4),
                    shape: BoxShape.circle,
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: p.mint.withValues(alpha: .35),
                              blurRadius: 0,
                              spreadRadius: 4,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: MochiCatSpacing.sm + 2),
                // 只显示连接名；IP 地址在 hover 时以 Tooltip 展示。
                Expanded(
                  child: Tooltip(
                    message: '${connection.username}@${connection.hostLabel}',
                    child: Text(
                      connection.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        color: active ? p.primary : p.textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: MochiCatSpacing.xs),
                IconButton(
                  icon: const Icon(AppIcons.terminal, size: 15),
                  tooltip: '连接',
                  visualDensity: VisualDensity.compact,
                  onPressed: onConnect,
                ),
                IconButton(
                  icon: const Icon(AppIcons.edit, size: 15),
                  tooltip: '编辑连接',
                  visualDensity: VisualDensity.compact,
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(AppIcons.delete, size: 15),
                  tooltip: '删除连接',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 会话子标签条：每个已打开会话一个标签，可关闭、可切换；右侧显示当前会话状态。
class _SessionTabBar extends ConsumerWidget {
  const _SessionTabBar({
    required this.sessions,
    required this.activeId,
    required this.onActivate,
    required this.onClose,
    required this.onAdd,
    required this.onTogglePanel,
    required this.panelVisible,
  });

  final Map<String, SshSessionHandle> sessions;
  final String? activeId;
  final ValueChanged<String> onActivate;
  final ValueChanged<String> onClose;
  final VoidCallback onAdd;
  final VoidCallback onTogglePanel;
  final bool panelVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = MochiCatPalette.of(context);

    final activeHandle = activeId == null ? null : sessions[activeId];

    return Padding(
      padding: const EdgeInsets.only(bottom: MochiCatSpacing.sm),
      child: Row(
        children: [
          if (!panelVisible)
            IconButton(
              icon: const Icon(AppIcons.menuOpen, size: 17),
              tooltip: '显示连接面板',
              onPressed: onTogglePanel,
            ),
          Expanded(
            child: SizedBox(
              height: 30,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: sessions.length,
                itemBuilder: (_, i) {
                  final entry = sessions.entries.elementAt(i);
                  final active = entry.key == activeId;
                  return Padding(
                    padding: const EdgeInsets.only(right: MochiCatSpacing.sm),
                    child: _SessionTab(
                      label: entry.value.connection.name,
                      active: active,
                      onTap: () => onActivate(entry.key),
                      onClose: () => onClose(entry.key),
                    ),
                  );
                },
              ),
            ),
          ),
          // 当前会话连接状态
          if (activeHandle != null)
            ValueListenableBuilder<SshSessionStatus>(
              valueListenable: activeHandle.status,
              builder: (context, status, _) {
                final (label, color) = switch (status) {
                  SshSessionStatus.connecting => ('连接中…', p.orange),
                  SshSessionStatus.connected => ('已连接', p.mint),
                  SshSessionStatus.error => ('连接失败', p.danger),
                  SshSessionStatus.closed => ('已断开', p.textSecondary),
                };
                return Padding(
                  padding: const EdgeInsets.only(right: MochiCatSpacing.sm),
                  child: StatusDot(label: label, color: color),
                );
              },
            ),
          IconButton(
            icon: const Icon(AppIcons.add, size: 20),
            tooltip: '新建连接',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(
              width: MochiCatSize.iconButton,
              height: MochiCatSize.iconButton,
            ),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _SessionTab extends StatefulWidget {
  const _SessionTab({
    required this.label,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  State<_SessionTab> createState() => _SessionTabState();
}

class _SessionTabState extends State<_SessionTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);
    final bg = widget.active
        ? p.primarySoft
        : (_hovered ? p.background : Colors.transparent);
    final fg = widget.active ? p.primary : p.textSecondary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(MochiCatRadius.sm),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(MochiCatRadius.sm),
          child: Container(
            height: 30,
            padding: const EdgeInsets.only(left: MochiCatSpacing.md),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: fg,
                    fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                InkWell(
                  onTap: widget.onClose,
                  borderRadius: BorderRadius.circular(MochiCatRadius.xs),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Icon(
                      AppIcons.close,
                      size: 13,
                      color: p.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 单个会话内容：上半区终端/文件并排，下半区可折叠监控面板。
class _SessionContent extends ConsumerStatefulWidget {
  const _SessionContent({super.key, required this.handle});

  final SshSessionHandle handle;

  @override
  ConsumerState<_SessionContent> createState() => _SessionContentState();
}

class _SessionContentState extends ConsumerState<_SessionContent> {
  final FocusNode _terminalFocus = FocusNode();
  late final TerminalController _controller;
  bool _lastSelectionWasNonNull = false;

  /// 监控是否展开（默认展开，只收起内容区，标题栏保留）。
  bool _monitorVisible = true;

  /// 监控面板高度（px），可上下拖拽调整；收起时标题栏 40px。
  double _monitorHeight = 280;

  /// 终端面板是否显示（隐藏后文件面板占满；两者都隐藏时监控占满）。
  bool _terminalVisible = true;

  /// 文件面板是否显示。
  bool _filesVisible = true;

  /// 终端宽度占比（0.3~0.7），通过中间拖拽条左右调整。
  double _splitRatio = 0.5;

  /// 监控控制器（页面常驻，启动/停止由显示状态决定）。
  final MonitorController _monitorController = MonitorController();

  @override
  void initState() {
    super.initState();
    _controller = TerminalController();
    // 选中变化 → 自动复制选中文本到剪切板。
    _controller.addListener(_onSelectionChanged);
    // 会话打开时终端自动聚焦，可直接键入命令；
    // 之后由 MouseRegion 悬停聚焦，不随 build 反复抢焦点。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _terminalFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onSelectionChanged);
    _controller.dispose();
    _terminalFocus.dispose();
    _monitorController.stopSilently();
    super.dispose();
  }

  /// 切换监控显隐：隐藏时停止采集，显示时由 _MonitorView 重建自动重启。
  void _toggleMonitor() {
    setState(() => _monitorVisible = !_monitorVisible);
    if (!_monitorVisible) {
      _monitorController.stop();
    }
  }

  /// 拖拽调整监控面板高度（向上拖增大，向下拖减小）。
  void _resizeMonitor(double dy, double maxHeight) {
    setState(() {
      _monitorHeight = (_monitorHeight - dy).clamp(120.0, maxHeight * 0.72);
    });
  }

  void _onSelectionChanged() {
    final hasSelection = _controller.selection != null;
    if (hasSelection && !_lastSelectionWasNonNull) {
      _copySelection();
    }
    _lastSelectionWasNonNull = hasSelection;
  }

  /// 将终端当前选中文本复制到剪切板。
  Future<void> _copySelection() async {
    final selection = _controller.selection;
    if (selection == null) return;
    final text = widget.handle.terminal.buffer.getText(selection);
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// 粘贴剪切板文本到终端（→ SSH）。
  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      widget.handle.terminal.paste(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final handle = widget.handle;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 可用高度不足时自动收起监控：确保终端/文件面板（各占一半）
        // 至少有约 200px 操作空间，否则文件面板会被压到几像素高而溢出。
        final effMonitorVisible =
            _monitorVisible && constraints.maxHeight - 52 >= 320;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 上半区：终端与文件并排（中间拖拽条可左右调宽，各自可彻底隐藏）。
            Expanded(
              child: Row(
                children: [
                  if (_terminalVisible) ...[
                    Expanded(
                      flex: _filesVisible
                          ? (10000 * _splitRatio).round()
                          : 10000,
                      child: _TerminalPane(
                        handle: handle,
                        focusNode: _terminalFocus,
                        controller: _controller,
                        onCopy: _copySelection,
                        onPaste: _paste,
                        onToggle: () => setState(() {
                          _terminalVisible = false;
                        }),
                      ),
                    ),
                    if (_filesVisible) ...[
                      _ResizeHandle(
                        onDrag: (dx) => setState(() {
                          final w = constraints.maxWidth - MochiCatSpacing.md;
                          _splitRatio =
                              (_splitRatio + dx / (w <= 0 ? 1 : w)).clamp(
                            0.3,
                            0.7,
                          );
                        }),
                      ),
                    ],
                  ],
                  if (_filesVisible)
                    Expanded(
                      flex: _terminalVisible
                          ? (10000 * (1 - _splitRatio)).round()
                          : 10000,
                      child: _FilePane(
                        handle: handle,
                        onToggle: () => setState(() {
                          _filesVisible = false;
                        }),
                      ),
                    ),
                ],
              ),
            ),
            // 下半区：监控面板。
            // 展开时：拖拽条 + 固定高度监控面板（可上下拖动调整高度）；
            // 收起时仅保留标题栏（40px），终端/文件获得全部空间。
            if (effMonitorVisible) ...[
              _MonitorResizeHandle(
                onDrag: (dy) => _resizeMonitor(dy, constraints.maxHeight),
              ),
              SizedBox(
                height: _monitorHeight,
                child: _MonitorPanel(
                  controller: _monitorController,
                  handle: handle,
                  visible: true,
                  onToggle: _toggleMonitor,
                  showTerminal: !_terminalVisible,
                  showFiles: !_filesVisible,
                  onShowTerminal: () =>
                      setState(() => _terminalVisible = true),
                  onShowFiles: () => setState(() => _filesVisible = true),
                ),
              ),
            ] else
              _MonitorPanel(
                controller: _monitorController,
                handle: handle,
                visible: false,
                onToggle: _toggleMonitor,
                showTerminal: !_terminalVisible,
                showFiles: !_filesVisible,
                onShowTerminal: () =>
                    setState(() => _terminalVisible = true),
                onShowFiles: () => setState(() => _filesVisible = true),
              ),
          ],
        );
      },
    );
  }
}

/// 终端面板：标题栏 + xterm 终端。
class _TerminalPane extends StatelessWidget {
  const _TerminalPane({
    required this.handle,
    required this.focusNode,
    required this.controller,
    required this.onCopy,
    required this.onPaste,
    required this.onToggle,
  });

  final SshSessionHandle handle;
  final FocusNode focusNode;
  final TerminalController controller;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(MochiCatRadius.lg),
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PaneHeader(
            icon: AppIcons.terminal,
            title: '终端',
            actions: [
              IconButton(
                icon: const Icon(AppIcons.hide, size: 15),
                tooltip: '隐藏终端',
                visualDensity: VisualDensity.compact,
                onPressed: onToggle,
              ),
            ],
          ),
          Expanded(
            child: Container(
              color: p.terminal,
              child: _TerminalHost(
                handle: handle,
                focusNode: focusNode,
                controller: controller,
                onCopy: onCopy,
                onPaste: onPaste,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 文件面板：标题栏 + SFTP 文件浏览（新建目录/上传等操作在 SftpView 工具栏内）。
class _FilePane extends StatelessWidget {
  const _FilePane({
    required this.handle,
    required this.onToggle,
  });

  final SshSessionHandle handle;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MochiCatPalette.of(context).surface,
        borderRadius: BorderRadius.circular(MochiCatRadius.lg),
        border: Border.all(color: MochiCatPalette.of(context).border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PaneHeader(
            icon: AppIcons.folder,
            title: '文件',
            actions: [
              IconButton(
                icon: const Icon(AppIcons.hide, size: 15),
                tooltip: '隐藏文件',
                visualDensity: VisualDensity.compact,
                onPressed: onToggle,
              ),
            ],
          ),
          Expanded(child: SftpView(handle: handle)),
        ],
      ),
    );
  }
}

/// 面板标题栏（终端/文件共用）。
class _PaneHeader extends StatelessWidget {
  const _PaneHeader({
    required this.icon,
    required this.title,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: MochiCatSpacing.md),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: p.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

/// 监控高度拖拽条：上下拖动调整监控面板高度（上拖变高，下拖变矮）。
class _MonitorResizeHandle extends StatefulWidget {
  const _MonitorResizeHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  State<_MonitorResizeHandle> createState() => _MonitorResizeHandleState();
}

class _MonitorResizeHandleState extends State<_MonitorResizeHandle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: (d) => widget.onDrag(d.delta.dy),
        child: Container(
          height: 14,
          color: _hovered ? p.primarySoft : Colors.transparent,
          alignment: Alignment.center,
          child: Container(
            width: 40,
            height: 3,
            decoration: BoxDecoration(
              color: _hovered ? p.primary : p.border,
              borderRadius: BorderRadius.circular(MochiCatRadius.pill),
            ),
          ),
        ),
      ),
    );
  }
}

/// 左右拖拽条：拖动调整终端/文件面板宽度（左拖变宽，右拖变窄）。
class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        child: Container(
          width: 14,
          color: _hovered ? p.primarySoft : Colors.transparent,
          alignment: Alignment.center,
          child: Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: _hovered ? p.primary : p.border,
              borderRadius: BorderRadius.circular(MochiCatRadius.pill),
            ),
          ),
        ),
      ),
    );
  }
}

/// 监控面板：标题栏（指示灯 + 服务器信息 + 隐藏/显示）+ 可折叠内容。
class _MonitorPanel extends StatelessWidget {
  const _MonitorPanel({
    required this.controller,
    required this.handle,
    required this.visible,
    required this.onToggle,
    required this.showTerminal,
    required this.showFiles,
    required this.onShowTerminal,
    required this.onShowFiles,
  });

  final MonitorController controller;
  final SshSessionHandle handle;
  final bool visible;
  final VoidCallback onToggle;

  /// 终端/文件面板当前是否处于隐藏状态（隐藏时标题栏显示恢复按钮）。
  final bool showTerminal;
  final bool showFiles;
  final VoidCallback onShowTerminal;
  final VoidCallback onShowFiles;

  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(MochiCatRadius.lg),
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final running = controller.state.running;
              return Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: MochiCatSpacing.md),
                decoration: BoxDecoration(
                  color: p.surface,
                  border: visible
                      ? Border(bottom: BorderSide(color: p.border))
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(AppIcons.monitor, size: 16, color: p.primary),
                    const SizedBox(width: 6),
                    const Text(
                      '服务器监控',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: MochiCatSpacing.sm),
                    StatusDot(
                      label: running ? '监控中' : '已停止',
                      color: running ? p.mint : p.textSecondary,
                      size: 7,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(AppIcons.info, size: 15),
                      label: const Text('服务器信息'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: MochiCatSpacing.sm),
                      ),
                      onPressed: () => _showServerInfo(context),
                    ),
                    // 终端/文件被隐藏时的恢复按钮（彻底隐藏，无残留条）。
                    if (showTerminal) ...[
                      const SizedBox(width: MochiCatSpacing.sm),
                      TextButton.icon(
                        icon: const Icon(AppIcons.terminal, size: 15),
                        label: const Text('显示终端'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: MochiCatSpacing.sm),
                        ),
                        onPressed: onShowTerminal,
                      ),
                    ],
                    if (showFiles) ...[
                      const SizedBox(width: MochiCatSpacing.sm),
                      TextButton.icon(
                        icon: const Icon(AppIcons.folder, size: 15),
                        label: const Text('显示文件'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: MochiCatSpacing.sm),
                        ),
                        onPressed: onShowFiles,
                      ),
                    ],
                    const SizedBox(width: MochiCatSpacing.sm),
                    InkWell(
                      onTap: onToggle,
                      borderRadius: BorderRadius.circular(MochiCatRadius.sm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: MochiCatSpacing.sm,
                          vertical: 5,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              visible
                                  ? AppIcons.arrowUp
                                  : AppIcons.arrowDown,
                              size: 17,
                              color: p.textSecondary,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              visible ? '隐藏监控' : '显示监控',
                              style: TextStyle(
                                fontSize: 12,
                                color: p.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // 内容（可折叠）。监控数据保存在父级 _monitorController，
          // 收起时视图销毁但采集不中断（_MonitorView 重建后自动恢复显示）。
          if (visible)
            Expanded(
              child: _MonitorView(controller: controller, handle: handle),
            ),
        ],
      ),
    );
  }

  Future<void> _showServerInfo(BuildContext context) async {
    final wasRunning = controller.state.running;
    if (!wasRunning) {
      final client = handle.client;
      if (client == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先连接会话')),
        );
        return;
      }
      controller.startWithClient(client);
    }
    await controller.fetchServerInfo();
    if (!wasRunning) controller.stop();

    final info = controller.state.serverInfo;
    if (!context.mounted) return;
    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('服务器信息查询失败')),
      );
      return;
    }

    await showMochiDialog<void>(
      context: context,
      title: '服务器信息',
      emoji: '🖥️',
      width: 400,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InfoRow('主机名', info['HOST'] ?? '-'),
          _InfoRow('操作系统', info['OS'] ?? '-'),
          _InfoRow('内核', info['KERNEL'] ?? '-'),
          _InfoRow('CPU 型号', info['CPU_MODEL'] ?? '-'),
          _InfoRow('CPU 核心数', info['CPU_CORES'] ?? '-'),
          _InfoRow(
            '内存',
            info['MEM_TOTAL'] == null
                ? '-'
                : _fmtBytes((int.tryParse(info['MEM_TOTAL']!) ?? 0) * 1024),
          ),
          _InfoRow(
            '磁盘总量',
            info['DISK_TOTAL'] == null
                ? '-'
                : _fmtBytes((int.tryParse(info['DISK_TOTAL']!) ?? 0) * 1024),
          ),
          _InfoRow('IP 地址', info['IP'] ?? '-'),
        ],
      ),
      actions: [
        MochiButton(
          label: '关闭',
          type: MochiButtonType.ghost,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// 终端视图：渲染 xterm 终端。
class _TerminalHost extends StatelessWidget {
  const _TerminalHost({
    required this.handle,
    required this.focusNode,
    required this.controller,
    required this.onCopy,
    required this.onPaste,
  });

  final SshSessionHandle handle;
  final FocusNode focusNode;
  final TerminalController controller;
  final VoidCallback onCopy;
  final VoidCallback onPaste;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // 只拦截 Ctrl+C 复制；字符/中文输入交给 xterm 的 TextInput 通道
    // （支持 IME 合成输入）。
    if (event is KeyDownEvent &&
        HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyC) {
      if (controller.selection != null) {
        onCopy();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // ClipRect：窗口尺寸变化时裁剪超出容器的内容，防止溢出到标题栏。
    // MouseRegion：鼠标进入终端区域即请求焦点（无需点击/双击）。
    return ClipRect(
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        onEnter: (_) {
          if (!focusNode.hasFocus) focusNode.requestFocus();
        },
        child: TerminalView(
          handle.terminal,
          focusNode: focusNode,
          autofocus: true,
          // 走硬件键盘监听路径：CustomKeyboardListener 在 onKeyEvent
          // 返回 ignored 且带字符时自动 textInput 送达终端。
          // 普通字符/中文 IME 上屏都能输入；Windows 下 TextInput 通道
          // attach 不稳定，故不用默认的 CustomTextEdit 通道。
          hardwareKeyboardOnly: true,
          controller: controller,
          onKeyEvent: _handleKeyEvent,
      onSecondaryTapUp: (details, cell) async {
        final selection = controller.selection;
        final rect = Rect.fromLTWH(
          details.globalPosition.dx,
          details.globalPosition.dy,
          1,
          1,
        );
        final overlay =
            Overlay.of(context).context.findRenderObject() as RenderBox?;
        final offset = overlay == null
            ? details.globalPosition
            : overlay.globalToLocal(details.globalPosition);

        final action = await showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(
            offset.dx,
            offset.dy,
            offset.dx + rect.width,
            offset.dy + rect.height,
          ),
          items: [
            PopupMenuItem(
              value: 'copy',
              enabled: selection != null,
              child: Row(
                children: [
                  const Icon(AppIcons.copy, size: 16),
                  const SizedBox(width: 8),
                  Text(selection != null ? '复制' : '复制（无选中）'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'paste',
              child: Row(
                children: [
                  Icon(AppIcons.paste, size: 16),
                  SizedBox(width: 8),
                  Text('粘贴'),
                ],
              ),
            ),
          ],
        );
        if (action == 'copy') {
          onCopy();
        } else if (action == 'paste') {
          onPaste();
        }
      },
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
  });

  final IconData icon;
  final String text;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final p = MochiCatPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: p.primary.withValues(alpha: .55)),
          const SizedBox(height: MochiCatSpacing.md),
          Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: MochiCatSpacing.xs),
          Text(
            detail,
            style: TextStyle(fontSize: 12, color: p.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 嵌入会话的监控视图：四张独立趋势图 + GPU/NPU + TOP 进程。
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
          padding: const EdgeInsets.all(MochiCatSpacing.md),
          children: [
            // 采集异常/诊断：醒目提示条。
            if (state.error != null) ...[
              const SizedBox(height: MochiCatSpacing.sm),
              Container(
                padding: const EdgeInsets.all(MochiCatSpacing.sm),
                decoration: BoxDecoration(
                  color: MochiCatColors.dangerSoft,
                  borderRadius: BorderRadius.circular(MochiCatRadius.sm),
                ),
                child: Text(
                  state.error!,
                  style: TextStyle(
                    fontSize: 12,
                    color: MochiCatColors.danger,
                  ),
                ),
              ),
            ],
            const SizedBox(height: MochiCatSpacing.sm),
            if (latest == null)
              SizedBox(
                height: 120,
                child: Center(
                  child: Text(
                    state.running ? '正在采集…' : '监控已停止',
                    style: TextStyle(
                      fontSize: 13,
                      color: MochiCatPalette.of(context).textSecondary,
                    ),
                  ),
                ),
              )
            else ...[
              // 四张独立趋势图（CPU / 内存 / 下载 / 上传）。
              _TrendGrid(history: state.history),
              const SizedBox(height: MochiCatSpacing.sm),
              // GPU 状态卡（有 GPU 数据时显示）。
              if (latest.gpus.isNotEmpty) ...[
                _GpuRow(history: state.history),
                const SizedBox(height: MochiCatSpacing.sm),
              ],
              // 华为昇腾 NPU 趋势（有 NPU 数据时显示）。
              if (latest.npus.isNotEmpty) ...[
                _NpuRow(history: state.history),
                const SizedBox(height: MochiCatSpacing.sm),
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
    final p = MochiCatPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MochiCatSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: p.textSecondary),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
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
            color: MochiCatColors.cpu,
            value: latest == null ? '-' : '${latest.cpuPercent.toStringAsFixed(1)}%',
            values: [for (final m in history) m.cpuPercent],
            unitMax: 100,
          ),
        ),
        const SizedBox(width: MochiCatSpacing.sm),
        Expanded(
          child: _TrendCard(
            label: '内存',
            color: MochiCatColors.memory,
            value: latest == null
                ? '-'
                : '${(latest.memPercent * 100).toStringAsFixed(0)}%',
            values: [for (final m in history) m.memPercent * 100],
            unitMax: 100,
          ),
        ),
        const SizedBox(width: MochiCatSpacing.sm),
        Expanded(
          child: _TrendCard(
            label: '下载',
            color: MochiCatColors.download,
            value: latest == null ? '-' : '${_fmtRate(latest.netRxBytesPerSec)}/s',
            values: [
              for (final m in history)
                rxMax > 0 ? m.netRxBytesPerSec / rxMax * 100 : 0,
            ],
            unitMax: 100,
          ),
        ),
        const SizedBox(width: MochiCatSpacing.sm),
        Expanded(
          child: _TrendCard(
            label: '上传',
            color: MochiCatColors.upload,
            value: latest == null ? '-' : '${_fmtRate(latest.netTxBytesPerSec)}/s',
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

  String _fmtRate(double bytesPerSec) {
    if (bytesPerSec < 1024) return '${bytesPerSec.toStringAsFixed(0)} B';
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB';
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
            padding: const EdgeInsets.only(bottom: MochiCatSpacing.sm),
            child: Text(
              'GPU ${i + 1}：${latest.gpus[i].name}'
              '${latest.gpus[i].tempC > 0 ? ' · ${latest.gpus[i].tempC.toStringAsFixed(0)}°C' : ''}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: MochiCatPalette.of(context).textSecondary,
              ),
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
              const SizedBox(width: MochiCatSpacing.sm),
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
              const SizedBox(width: MochiCatSpacing.sm),
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
          const SizedBox(height: MochiCatSpacing.sm),
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
            padding: const EdgeInsets.only(bottom: MochiCatSpacing.sm),
            child: Text(
              'NPU ${i + 1}：${latest.npus[i].name}'
              '${latest.npus[i].tempC > 0 ? ' · ${latest.npus[i].tempC.toStringAsFixed(0)}°C' : ''}'
              ' · ${latest.npus[i].health.isEmpty ? 'OK' : latest.npus[i].health}',
              style: TextStyle(
                fontSize: 12,
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
              const SizedBox(width: MochiCatSpacing.sm),
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
              const SizedBox(width: MochiCatSpacing.sm),
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
          const SizedBox(height: MochiCatSpacing.sm),
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
    final p = MochiCatPalette.of(context);
    return Container(
      height: 152,
      padding: const EdgeInsets.all(MochiCatSpacing.sm + 2),
      decoration: BoxDecoration(
        color: p.surfaceMuted,
        borderRadius: BorderRadius.circular(MochiCatRadius.md),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: p.textSecondary),
              ),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: MochiCatSpacing.xs),
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
String _processMemText(int memTotalBytes, double memPercent) {
  final bytes = (memTotalBytes * memPercent / 100).round();
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

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
    final p = MochiCatPalette.of(context);
    final keyword = _searchController.text.trim().toLowerCase();
    final filtered = keyword.isEmpty
        ? widget.processes
        : widget.processes
            .where((proc) => proc.name.toLowerCase().contains(keyword))
            .toList();

    return Container(
      decoration: BoxDecoration(
        color: p.surfaceMuted,
        borderRadius: BorderRadius.circular(MochiCatRadius.md),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MochiCatSpacing.md,
              MochiCatSpacing.sm,
              MochiCatSpacing.sm,
              MochiCatSpacing.sm,
            ),
            child: Row(
              children: [
                const Text(
                  'TOP 进程',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                SizedBox(
                  width: 190,
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '按命令搜索',
                      prefixIcon: const Icon(
                        AppIcons.search,
                        size: 15,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: MochiCatSpacing.sm,
                        vertical: 6,
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
          ),
          const Divider(height: 1),
          // 表头
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MochiCatSpacing.md,
              MochiCatSpacing.sm,
              MochiCatSpacing.md,
              MochiCatSpacing.xs,
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
                      style: TextStyle(fontSize: 12, color: p.textSecondary),
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final proc = filtered[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: MochiCatSpacing.md,
                          vertical: MochiCatSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 52,
                              child: Text(
                                '${proc.pid}',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            Expanded(
                              child: Tooltip(
                                message: proc.name,
                                child: Text(
                                  proc.name,
                                  style: const TextStyle(fontSize: 11),
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
                                style: TextStyle(
                                  fontSize: 11,
                                  color: p.textSecondary,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 72,
                              child: Tooltip(
                                message: _processMemText(
                                  widget.memTotalBytes,
                                  proc.memPercent,
                                ),
                                child: Text(
                                  '${proc.memPercent.toStringAsFixed(1)}%',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: p.textSecondary,
                                  ),
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

class _HeadText extends StatelessWidget {
  const _HeadText(this.text, {this.right = false});

  final String text;
  final bool right;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: right ? TextAlign.right : TextAlign.left,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: MochiCatPalette.of(context).textSecondary,
      ),
    );
  }
}
