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
import 'package:toolbox/ui/theme/appflowy_colors.dart';
import 'package:xterm/xterm.dart';

/// 远程管理页：左侧连接列表，右侧多开 SSH 会话（终端 / 文件）。
class RemoteView extends ConsumerStatefulWidget {
  const RemoteView({super.key});

  @override
  ConsumerState<RemoteView> createState() => _RemoteViewState();
}

class _RemoteViewState extends ConsumerState<RemoteView> {
  String? _activeSessionId;
  bool _testing = false;
  String? _testResult;
  double _panelWidth = 240;
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
        padding: const EdgeInsets.all(AppflowySpacing.xl),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_panelVisible) ...[
              _ConnectionPanel(
                width: _panelWidth,
                connections: connections,
                activeId: activeId,
                onSelect: (id) => setState(() => _activeSessionId = id),
                onAdd: _showConnectionDialog,
                onEdit: (conn) => _showConnectionDialog(connection: conn),
                onDelete: (conn) => _deleteConnection(conn),
                onConnect: (conn) => _openSession(conn),
                onToggle: () => setState(() => _panelVisible = false),
              ),
              _ResizeHandle(
                onDrag: (dx) => setState(
                  () => _panelWidth = (_panelWidth + dx).clamp(180, 480),
                ),
              ),
              const SizedBox(width: AppflowySpacing.s),
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
                              icon: const Icon(Icons.menu_open),
                              tooltip: '显示连接面板',
                              onPressed: () =>
                                  setState(() => _panelVisible = true),
                            ),
                          ),
                        const Center(
                          child: _EmptyHint(
                            text: '双击左侧连接，或点击连接按钮打开 SSH 会话',
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
                        ),
                        if (!_panelVisible)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              icon: const Icon(Icons.menu_open),
                              tooltip: '显示连接面板',
                              onPressed: () =>
                                  setState(() => _panelVisible = true),
                            ),
                          ),
                        if (sessions.isNotEmpty)
                          Expanded(
                            child: IndexedStack(
                              index: sessions.keys.toList().indexOf(activeId!),
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

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final textTheme = Theme.of(context).textTheme;
          return AlertDialog(
            title: Text(connection == null ? '新建连接' : '编辑连接'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameController,
                      autofocus: connection == null,
                      decoration: const InputDecoration(labelText: '名称'),
                    ),
                    const SizedBox(height: AppflowySpacing.m),
                    TextField(
                      controller: hostController,
                    decoration: const InputDecoration(labelText: '主机'),
                  ),
                  const SizedBox(height: AppflowySpacing.m),
                  TextField(
                    controller: portController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: '端口（默认 22）'),
                  ),
                  const SizedBox(height: AppflowySpacing.m),
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(labelText: '用户名'),
                  ),
                  const SizedBox(height: AppflowySpacing.m),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: '密码（密钥认证时可留空）',
                    ),
                  ),
                  const SizedBox(height: AppflowySpacing.m),
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
                  const SizedBox(height: AppflowySpacing.m),
                  if (useKeyAuth) ...[
                    TextField(
                      controller: keyPathController,
                      decoration: const InputDecoration(
                        labelText: '私钥文件（OpenSSH / RSA / EC PEM）',
                      ),
                    ),
                    const SizedBox(height: AppflowySpacing.s),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.folder_open, size: 16),
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
                    const SizedBox(height: AppflowySpacing.m),
                    TextField(
                      controller: passphraseController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: '私钥口令（可选）',
                      ),
                    ),
                    const SizedBox(height: AppflowySpacing.m),
                  ],
                  if (_testResult != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _testResult!,
                        style: textTheme.bodySmall?.copyWith(
                          color: _testResult!.startsWith('连接成功')
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFC62828),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
            actions: [
              TextButton(
                onPressed: _testing
                    ? null
                    : () async {
                        setDialogState(() {
                          _testing = true;
                          _testResult = null;
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
                          _testing = false;
                          _testResult = result;
                        });
                      },
                child: _testing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('测试连接'),
              ),
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
    nameController.dispose();
    hostController.dispose();
    portController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    keyPathController.dispose();
    passphraseController.dispose();
  }

  Future<void> _deleteConnection(SshConnection connection) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('删除连接「${connection.name}」？'),
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
    if (ok == true) {
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

/// 左侧连接面板。
class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({
    required this.width,
    required this.connections,
    required this.activeId,
    required this.onSelect,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onConnect,
    required this.onToggle,
  });

  final double width;
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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: width,
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
                Text('连接', style: textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.keyboard_double_arrow_left, size: 18),
                  tooltip: '收起连接面板',
                  onPressed: onToggle,
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: '新建连接',
                  onPressed: onAdd,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: connections.isEmpty
                ? const _EmptyHint(text: '暂无连接')
                : ListView.builder(
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
        ],
      ),
    );
  }
}

/// 面板右侧的拖拽分隔条：拖动调整面板宽度。
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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      onDoubleTap: onConnect,
      child: Container(
        color: active
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
                    connection.name,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${connection.username}@${connection.hostLabel}',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.terminal, size: 16),
              tooltip: '连接',
              onPressed: onConnect,
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 16),
              tooltip: '编辑连接',
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 16),
              tooltip: '删除连接',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// 会话子标签条：每个已打开会话一个标签，可关闭、可切换。
class _SessionTabBar extends StatelessWidget {
  const _SessionTabBar({
    required this.sessions,
    required this.activeId,
    required this.onActivate,
    required this.onClose,
  });

  final Map<String, SshSessionHandle> sessions;
  final String? activeId;
  final ValueChanged<String> onActivate;
  final ValueChanged<String> onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 36,
      color: scheme.surface,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          AppflowySpacing.m,
          AppflowySpacing.xs,
          AppflowySpacing.m,
          AppflowySpacing.xs,
        ),
        itemCount: sessions.length,
        itemBuilder: (_, i) {
          final entry = sessions.entries.elementAt(i);
          final active = entry.key == activeId;
          return Padding(
            padding: const EdgeInsets.only(right: AppflowySpacing.s),
            child: _SessionTab(
              label: entry.value.connection.name,
              active: active,
              onTap: () => onActivate(entry.key),
              onClose: () => onClose(entry.key),
            ),
          );
        },
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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final palette = Theme.of(context).brightness == Brightness.dark
        ? AppflowyColors.dark
        : AppflowyColors.light;
    final bg = widget.active
        ? scheme.primary.withValues(alpha: 0.12)
        : (_hovered ? palette.layer01 : Colors.transparent);
    final fg = widget.active ? scheme.primary : scheme.onSurface;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppflowyRadius.s),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppflowyRadius.s),
          child: Padding(
            padding: const EdgeInsets.only(left: AppflowySpacing.m),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: textTheme.bodyMedium?.copyWith(
                    color: fg,
                    fontWeight:
                        widget.active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                const SizedBox(width: AppflowySpacing.xs),
                InkWell(
                  onTap: widget.onClose,
                  borderRadius: BorderRadius.circular(AppflowyRadius.xs),
                  child: Padding(
                    padding: const EdgeInsets.all(AppflowySpacing.xs),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: scheme.onSurfaceVariant,
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

/// 单个会话内容：状态提示 + 终端/文件视图切换。
class _SessionContent extends ConsumerStatefulWidget {
  const _SessionContent({super.key, required this.handle});

  final SshSessionHandle handle;

  @override
  ConsumerState<_SessionContent> createState() => _SessionContentState();
}

/// 会话视图状态：持有 TerminalController（选中/复制）、选中自动复制监听
/// 与右键菜单。在 IndexedStack 中常驻，切走再切回不丢。
/// 会话内容视图：终端 / 文件 / 监控。
enum _SessionView { terminal, files, monitor }

class _SessionContentState extends ConsumerState<_SessionContent> {
  _SessionView _view = _SessionView.terminal;
  final FocusNode _terminalFocus = FocusNode();
  late final TerminalController _controller;
  bool _lastSelectionWasNonNull = false;

  /// 监控控制器（页面常驻，启动/停止由用户控制）。
  final MonitorController _monitorController = MonitorController();

  @override
  void initState() {
    super.initState();
    _controller = TerminalController();
    // 选中变化 → 自动复制选中文本到剪切板。
    // 用 ChangeNotifier 监听：对比前后 selection 是否为 null，
    // 只在「从无选中变为有选中」时复制一次。
    _controller.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onSelectionChanged);
    _controller.dispose();
    _terminalFocus.dispose();
    _monitorController.stop();
    super.dispose();
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

  String _statusText(SshSessionStatus status) => switch (status) {
        SshSessionStatus.connecting => '连接中…',
        SshSessionStatus.connected => '已连接',
        SshSessionStatus.error => '连接失败',
        SshSessionStatus.closed => '已断开',
      };

  @override
  Widget build(BuildContext context) {
    final handle = widget.handle;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // 切到终端视图时确保终端获得焦点，可直接键入命令。
    if (_view == _SessionView.terminal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _terminalFocus.requestFocus();
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 状态条：实时监听会话状态，避免连接成功后仍显示「连接中」。
        ValueListenableBuilder<SshSessionStatus>(
          valueListenable: handle.status,
          builder: (context, status, _) => Padding(
            padding: const EdgeInsets.fromLTRB(
              AppflowySpacing.m,
              AppflowySpacing.xs,
              AppflowySpacing.m,
              AppflowySpacing.xs,
            ),
            child: Row(
              children: [
                if (status == SshSessionStatus.connecting)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    switch (status) {
                      SshSessionStatus.connected => Icons.check_circle,
                      SshSessionStatus.error => Icons.error_outline,
                      SshSessionStatus.closed => Icons.circle_outlined,
                      SshSessionStatus.connecting => Icons.circle,
                    },
                    size: 14,
                    color: switch (status) {
                      SshSessionStatus.connected => const Color(0xFF2E7D32),
                      SshSessionStatus.error => const Color(0xFFC62828),
                      _ => scheme.onSurfaceVariant,
                    },
                  ),
                const SizedBox(width: AppflowySpacing.s),
                Text(
                  _statusText(status),
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                // 视图切换：终端 / 文件 / 监控
                SegmentedButton<_SessionView>(
                  segments: const [
                    ButtonSegment(
                      value: _SessionView.terminal,
                      label: Text('终端'),
                    ),
                    ButtonSegment(
                      value: _SessionView.files,
                      label: Text('文件'),
                    ),
                    ButtonSegment(
                      value: _SessionView.monitor,
                      label: Text('监控'),
                    ),
                  ],
                  selected: {_view},
                  onSelectionChanged: (s) =>
                      setState(() => _view = s.first),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        // 三个视图同时保活（IndexedStack），来回切换不丢状态。
        Expanded(
          child: IndexedStack(
            index: _view.index,
            children: [
              _TerminalHost(
                handle: handle,
                focusNode: _terminalFocus,
                controller: _controller,
                onCopy: _copySelection,
                onPaste: _paste,
              ),
              SftpView(handle: handle),
              // 监控视图：使用当前会话已建立的 SSH 连接采集。
              _MonitorView(controller: _monitorController, handle: handle),
            ],
          ),
        ),
      ],
    );
  }
}

/// 终端视图：渲染 xterm 终端。
///
/// 键盘输入处理：可见字符通过 [TerminalView.onKeyEvent] 直接写入终端
/// （走 terminal.textInput → SSH），特殊键（回车/退格/方向键/Ctrl 组合等）
/// 返回 ignored 交给 xterm 默认处理；同时以 readOnly 关闭系统 TextInput
/// 通道，避免同一按键被处理两次。
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
    if (event is KeyDownEvent) {
      // Ctrl+C：有选中则复制（不发给远端），否则交回默认（SIGINT 中断）。
      if (HardwareKeyboard.instance.isControlPressed &&
          !HardwareKeyboard.instance.isAltPressed &&
          !HardwareKeyboard.instance.isShiftPressed &&
          event.logicalKey == LogicalKeyboardKey.keyC) {
        if (controller.selection != null) {
          onCopy();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
      final char = event.character;
      if (char != null && char.isNotEmpty) {
        final rune = char.runes.isNotEmpty ? char.runes.first : 0;
        // 只接管可见字符；控制字符（回车/制表等）交给 xterm 默认处理。
        final isVisible = rune >= 0x20 && rune != 0x7F;
        final hasModifier = HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isAltPressed ||
            HardwareKeyboard.instance.isMetaPressed;
        if (isVisible && !hasModifier) {
          handle.terminal.textInput(char);
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return TerminalView(
      handle.terminal,
      focusNode: focusNode,
      autofocus: true,
      // 桌面端禁用软键盘 TextInput 通道（Windows 下 attach 会报
      // view ID is null 并崩溃），改用纯硬件键盘事件，
      // 由 onKeyEvent 接管可见字符输入。
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
        final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
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
                  const Icon(Icons.copy, size: 16),
                  const SizedBox(width: 8),
                  Text(selection != null ? '复制' : '复制（无选中）'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'paste',
              child: Row(
                children: [
                  Icon(Icons.content_paste, size: 16),
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

/// 嵌入会话的监控视图：使用当前会话已建立的 SSH 连接采集。
///
/// 使用独立的 [MonitorController]（非全局 provider），随页面生命周期
/// 启动/停止；已连接时自动开始采集，断开/关闭会话时自动停止。
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
    // 会话已连接则立即开始监控；未连接则等待连接完成。
    _maybeStart();
    widget.handle.status.addListener(_maybeStart);
  }

  @override
  void dispose() {
    widget.handle.status.removeListener(_maybeStart);
    widget.controller.stop();
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

  /// 查询并弹窗展示服务器基本信息。
  Future<void> _showServerInfo() async {
    // 未监控时复用会话连接临时采集一次，随后停止（不断开连接）。
    final wasRunning = widget.controller.state.running;
    if (!wasRunning) {
      final client = widget.handle.client;
      if (client == null) {
        _showMessage('请先连接会话');
        return;
      }
      widget.controller.startWithClient(client);
    }

    await widget.controller.fetchServerInfo();
    if (!wasRunning) widget.controller.stop();

    final info = widget.controller.state.serverInfo;
    if (!mounted) return;
    if (info == null) {
      _showMessage('服务器信息查询失败');
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('服务器信息'),
        content: SizedBox(
          width: 380,
          child: Column(
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        final latest = state.latest;

        // 使用 ListView（垂直可滚动），任何内容高度都不会溢出；
        // 进程列表固定高度内部滚动。
        return ListView(
          padding: const EdgeInsets.all(AppflowySpacing.m),
          children: [
            // 控制条：绿色=监控中 / 红色=已停止，点击切换。
            Row(
              children: [
                Switch(
                  value: state.running,
                  onChanged: (on) {
                    if (on) {
                      _maybeStart();
                    } else {
                      widget.controller.stop();
                    }
                  },
                ),
                const SizedBox(width: AppflowySpacing.xs),
                Text(
                  state.running ? '监控中' : '已停止',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: state.running
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFC62828),
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  icon: const Icon(Icons.info_outline, size: 16),
                  label: const Text('服务器信息'),
                  onPressed: () => _showServerInfo(),
                ),
              ],
            ),
            // 采集异常/诊断：醒目红色提示条。
            if (state.error != null) ...[
              const SizedBox(height: AppflowySpacing.s),
              Container(
                padding: const EdgeInsets.all(AppflowySpacing.s),
                decoration: BoxDecoration(
                  color: const Color(0xFFC62828).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppflowyRadius.s),
                ),
                child: Text(
                  state.error!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFC62828),
                      ),
                ),
              ),
            ],
            const SizedBox(height: AppflowySpacing.m),
            if (latest == null)
              SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    state.running ? '正在采集…' : '监控已停止，打开开关开始采集',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                ),
              )
            else ...[
              // 三张并排实时趋势图（CPU / 内存 / 网络）置顶。
              _TrendRow(history: state.history),
              const SizedBox(height: AppflowySpacing.m),
              // GPU 状态卡（有 GPU 数据时显示）。
              if (latest.gpus.isNotEmpty) ...[
                _GpuRow(history: state.history),
                const SizedBox(height: AppflowySpacing.m),
              ],
              // 华为昇腾 NPU 趋势（有 NPU 数据时显示）。
              if (latest.npus.isNotEmpty) ...[
                _NpuRow(history: state.history),
                const SizedBox(height: AppflowySpacing.m),
              ],
              // TOP 进程（固定高度，内部滚动）。
              SizedBox(
                height: 240,
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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppflowySpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// 三张并排实时趋势图：CPU / 内存 / 网络。
class _TrendRow extends StatelessWidget {
  const _TrendRow({required this.history});

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

    // 两行布局，每张卡固定高度 200，趋势更清晰。
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _TrendCard(
                label: 'CPU',
                color: const Color(0xFF3F6AD8),
                value: latest == null
                    ? '-'
                    : '${latest.cpuPercent.toStringAsFixed(1)}%',
                values: [for (final m in history) m.cpuPercent],
                unitMax: 100,
              ),
            ),
            const SizedBox(width: AppflowySpacing.m),
            Expanded(
              child: _TrendCard(
                label: '内存',
                color: const Color(0xFF2E7D32),
                value: latest == null
                    ? '-'
                    : '${(latest.memPercent * 100).toStringAsFixed(0)}%',
                values: [for (final m in history) m.memPercent * 100],
                unitMax: 100,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppflowySpacing.m),
        Row(
          children: [
            Expanded(
              child: _TrendCard(
                label: '下载',
                color: const Color(0xFF1E88E5),
                value: latest == null
                    ? '-'
                    : '${_fmtRate(latest.netRxBytesPerSec)}/s',
                values: [
                  for (final m in history)
                    rxMax > 0 ? m.netRxBytesPerSec / rxMax * 100 : 0,
                ],
                unitMax: 100,
              ),
            ),
            const SizedBox(width: AppflowySpacing.m),
            Expanded(
              child: _TrendCard(
                label: '上传',
                color: const Color(0xFFF05033),
                value: latest == null
                    ? '-'
                    : '${_fmtRate(latest.netTxBytesPerSec)}/s',
                values: [
                  for (final m in history)
                    txMax > 0 ? m.netTxBytesPerSec / txMax * 100 : 0,
                ],
                unitMax: 100,
              ),
            ),
          ],
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

/// GPU 趋势图：每个 GPU 一张利用率趋势卡（含温度/功耗）。
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
          // GPU 名称信息行。
          Padding(
            padding: const EdgeInsets.only(bottom: AppflowySpacing.m),
            child: Text(
              'GPU ${i + 1}：${latest.gpus[i].name}'
              '${latest.gpus[i].tempC > 0 ? ' · ${latest.gpus[i].tempC.toStringAsFixed(0)}°C' : ''}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          // 利用率 / 功耗 / 显存 三卡并排，宽度自适应。
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _GpuTrend(
                  label: '利用率',
                  color: const Color(0xFF9C27B0),
                  value: '${latest.gpus[i].utilPercent.toStringAsFixed(0)}%',
                  series: [
                    for (final m in history)
                      if (i < m.gpus.length) m.gpus[i].utilPercent,
                  ],
                  unitMax: 100,
                ),
              ),
              const SizedBox(width: AppflowySpacing.m),
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
              const SizedBox(width: AppflowySpacing.m),
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
          const SizedBox(height: AppflowySpacing.m),
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
          // NPU 信息行：名称 + 温度 + 健康状态。
          Padding(
            padding: const EdgeInsets.only(bottom: AppflowySpacing.m),
            child: Text(
              'NPU ${i + 1}：${latest.npus[i].name}'
              '${latest.npus[i].tempC > 0 ? ' · ${latest.npus[i].tempC.toStringAsFixed(0)}°C' : ''}'
              ' · ${latest.npus[i].health.isEmpty ? 'OK' : latest.npus[i].health}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: _healthColor(latest.npus[i].health),
                  ),
            ),
          ),
          // AI Core / HBM / 功耗 三卡并排。
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _GpuTrend(
                  label: 'AI Core',
                  color: const Color(0xFF7B1FA2),
                  value:
                      '${latest.npus[i].aiCorePercent.toStringAsFixed(0)}%',
                  series: [
                    for (final m in history)
                      if (i < m.npus.length) m.npus[i].aiCorePercent,
                  ],
                  unitMax: 100,
                ),
              ),
              const SizedBox(width: AppflowySpacing.m),
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
              const SizedBox(width: AppflowySpacing.m),
              // 功耗趋势卡：功率为 NA（<=0）时隐藏。
              if (latest.npus[i].powerWatts > 0) ...[
                Expanded(
                  child: _GpuTrend(
                    label: '功耗',
                    color: const Color(0xFFEF6C00),
                    value:
                        '${latest.npus[i].powerWatts.toStringAsFixed(0)} W',
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
            ],
          ),
          const SizedBox(height: AppflowySpacing.m),
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

/// 单个 GPU 指标趋势卡（无额外副标题，标题含指标名）。
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

/// 单指标趋势卡片：大数值 + 最近历史折线。
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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      height: 240,
      padding: const EdgeInsets.all(AppflowySpacing.m),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppflowyRadius.m),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: textTheme.labelMedium),
          const SizedBox(height: AppflowySpacing.xs),
          Text(
            value,
            style: textTheme.titleLarge?.copyWith(color: color),
          ),
          const SizedBox(height: AppflowySpacing.s),
          // 折线区占剩余空间（卡片高度有界，Expanded 自适应），
          // 内容增多也不会溢出。
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

/// 单指标折线绘制。
class _TrendChartPainter extends CustomPainter {
  _TrendChartPainter({
    required this.values,
    required this.unitMax,
    required this.color,
  });

  final List<double> values;
  final double unitMax;
  final Color color;

  /// Y 轴标签区宽度。
  static const _axisWidth = 30.0;
  static const _pad = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    // 折线区：左侧留出 Y 轴标签宽度。
    final plotLeft = _axisWidth;
    final plotRight = size.width - _pad;
    final plotTop = _pad;
    final plotBottom = size.height - _pad;
    final plotWidth = plotRight - plotLeft;
    final plotHeight = plotBottom - plotTop;

    final gridPaint = Paint()
      ..strokeWidth = 1
      ..color = color.withValues(alpha: 0.15);
    final labelPaint = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Y 轴刻度：4 档（0, 1/3, 2/3, 1）× unitMax。
    const steps = 4;
    for (var s = 0; s < steps; s++) {
      final ratio = s / (steps - 1);
      final y = plotBottom - plotHeight * ratio;
      canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), gridPaint);
      final label = _fmtTick(unitMax * ratio);
      labelPaint.text = TextSpan(
        text: label,
        style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.8)),
      );
      labelPaint.layout();
      labelPaint.paint(
        canvas,
        Offset(_pad, y - labelPaint.height / 2),
      );
    }

    if (values.length < 2) {
      // 数据不足时画一条基准线。
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
        ..strokeWidth = 2
        ..color = color,
    );
  }

  /// 刻度标签格式：0 显示 0，否则整数或一位小数。
  String _fmtTick(double v) {
    if (v == 0) return '0';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}k';
    return v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }

  @override
  bool shouldRepaint(_TrendChartPainter old) => old.values != values;
}

/// TOP 进程列表：支持按 COMMAND 全称模糊搜索。

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

class _MonitorProcessList extends StatefulWidget {
  const _MonitorProcessList({
    required this.processes,
    required this.cpuCores,
    required this.memTotalBytes,
  });

  final List<TopProcess> processes;

  /// CPU 核心数（进程 CPU 占比换算）。
  final int cpuCores;

  /// 总内存字节（进程内存大小换算）。
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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final keyword = _searchController.text.trim().toLowerCase();
    final filtered = keyword.isEmpty
        ? widget.processes
        : widget.processes
            .where((p) => p.name.toLowerCase().contains(keyword))
            .toList();

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppflowyRadius.m),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppflowySpacing.m),
            child: Row(
              children: [
                Text('TOP 进程', style: textTheme.labelMedium),
                const Spacer(),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _searchController,
                    style: textTheme.bodySmall,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '按命令搜索',
                      prefixIcon: const Icon(Icons.search, size: 16),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppflowyRadius.s),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      keyword.isEmpty ? '无数据' : '未匹配，试试其他关键词',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = filtered[i];
                      return ListTile(
                        dense: true,
                        leading: SizedBox(
                          width: 56,
                          child: Text(
                            '${p.pid}',
                            style: textTheme.bodySmall,
                          ),
                        ),
                        title: Tooltip(
                          message: p.name,
                          child: Text(
                            p.name,
                            style: textTheme.bodyMedium,
                            // 过长用 ... 隐藏，悬停看完整命令。
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Tooltip(
                              message: 'CPU 单核占比：'
                                  '${(p.cpuPercent / widget.cpuCores).toStringAsFixed(1)}%',
                              child: Text(
                                'CPU ${p.cpuPercent.toStringAsFixed(1)}%',
                                style: textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppflowySpacing.s),
                            Tooltip(
                              message: '内存：${_processMemText(widget.memTotalBytes, p.memPercent)}',
                              child: Text(
                                '内存 ${p.memPercent.toStringAsFixed(1)}%',
                                style: textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
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

