import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:toolbox/common/byte_format.dart';
import 'package:toolbox/features/monitor/monitor_controller.dart';
import 'package:toolbox/features/monitor/monitor_models.dart';
import 'package:toolbox/features/remote/remote_controller.dart';
import 'package:toolbox/features/remote/remote_models.dart';
import 'package:toolbox/features/remote/sftp_view.dart';
import 'package:toolbox/features/remote/ssh_session.dart';

import 'package:toolbox/ui/theme/app_layout.dart';
import 'package:toolbox/ui/theme/theme_controller.dart';
import 'package:toolbox/ui/widgets/app_dialog.dart';
import 'package:toolbox/ui/widgets/app_empty_hint.dart';
import 'package:toolbox/ui/widgets/app_form_row.dart';
import 'package:toolbox/ui/widgets/app_resize_handle.dart';
import 'package:toolbox/ui/widgets/app_toast.dart';
import 'package:toolbox/ui/widgets/app_tooltip.dart';
import 'package:toolbox/ui/widgets/tile_icon_button.dart';
import 'package:xterm/xterm.dart';

part 'remote_monitor_view.dart';

// 性能监控趋势图的 4 条数据序列配色。
//
// 这属于「图表数据编码」而非 UI 样式：ForUI 不提供图表能力，且 4 条曲线
// 必须彼此可区分，无法从主题语义色里取够。终端配色同理（见 TerminalTheme）。
const _chartCpu = Color(0xFF3F6AD8);
const _chartMemory = Color(0xFF2E7D32);
const _chartDownload = Color(0xFF1E88E5);
const _chartUpload = Color(0xFFF05033);

/// 远程管理页：左侧连接列表，右侧多开 SSH 会话。
///
/// 布局：上半区终端与文件永久并排（可拖拽调宽，默认各占 50%），
/// 下半区服务器监控默认展开、可折叠；终端/文件/监控状态同时保活。
/// 终端是否持有键盘焦点。
///
/// 远程页的快捷键（Ctrl+N / Ctrl+W / Ctrl+Tab）在终端持有焦点时**必须让行**：
/// 这些组合键在 shell 里有原义（例如 bash 的 Ctrl+W 是删除前一个词），
/// 抢走它们会让用户在终端里「按了没反应」。
class TerminalFocus extends Notifier<bool> {
  @override
  bool build() => false;

  /// 更新终端焦点状态（由终端宿主上报）。
  void set(bool focused) => state = focused;
}

/// 终端是否持有键盘焦点（页面级快捷键据此让行）。
final terminalFocusProvider = NotifierProvider<TerminalFocus, bool>(
  TerminalFocus.new,
);

/// 远程管理：SSH 连接 + 会话（终端 / 文件 / 监控）。
class RemoteView extends ConsumerStatefulWidget {
  const RemoteView({super.key});

  @override
  ConsumerState<RemoteView> createState() => _RemoteViewState();
}

class _RemoteViewState extends ConsumerState<RemoteView> {
  /// 当前会话 id。用 ValueNotifier 而不是 setState：
  /// 切换会话时只重建「连接面板高亮 + 标签栏 + IndexedStack」，
  /// 不再牵动整页（此前每次切换都会触发整页重建，是卡顿来源之一）。
  final ValueNotifier<String?> _activeSessionId = ValueNotifier(null);

  /// 布局偏好持久化键前缀（user/settings.json）。
  static const _prefix = 'remote.';

  bool _panelVisible = true;
  double _splitRatio = 0.5;
  bool _monitorVisible = true;
  double _monitorHeight = 280;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    // 恢复上次的布局偏好。
    final saved = ref.read(settingsStoreProvider).read();
    _panelVisible = saved['${_prefix}panelVisible'] as bool? ?? true;
    _splitRatio = _clampRatio((saved['${_prefix}splitRatio'] as num?) ?? 0.5);
    _monitorVisible = saved['${_prefix}monitorVisible'] as bool? ?? true;
    _monitorHeight =
        _clampHeight((saved['${_prefix}monitorHeight'] as num?) ?? 280);
  }

  @override
  void dispose() {
    _activeSessionId.dispose();
    _saveDebounce?.cancel();
    super.dispose();
  }

  /// 会话内部布局变化 → 更新页面字段并防抖持久化。
  void _onSessionLayoutChanged({
    required bool monitorVisible,
    required double monitorHeight,
    required double splitRatio,
  }) {
    _monitorVisible = monitorVisible;
    _monitorHeight = monitorHeight;
    _splitRatio = splitRatio;
    _saveLayoutDebounced();
  }

  static double _clampRatio(num v) => v.clamp(0.3, 0.7).toDouble();

  static double _clampHeight(num v) => v.clamp(120.0, 2000.0).toDouble();

  /// 布局变化后防抖保存（拖拽过程每帧都会变，不能每帧写盘）。
  void _saveLayoutDebounced() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _saveLayout);
  }

  void _saveLayout() {
    final store = ref.read(settingsStoreProvider);
    store.write({
      ...store.read(),
      '${_prefix}panelVisible': _panelVisible,
      '${_prefix}splitRatio': _splitRatio,
      '${_prefix}monitorVisible': _monitorVisible,
      '${_prefix}monitorHeight': _monitorHeight,
    });
  }

  @override
  Widget build(BuildContext context) {
    final connections = ref.watch(sshConnectionsProvider);
    final sessions = ref.watch(sshSessionsProvider);

    // 页面级快捷键：Ctrl+* 交给 CallbackShortcuts，终端有焦点时让行。
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _shortcutNewConnection,
        const SingleActivator(LogicalKeyboardKey.keyW, control: true):
            _shortcutCloseSession,
        const SingleActivator(LogicalKeyboardKey.tab, control: true): () =>
            _shortcutCycleSession(1),
        const SingleActivator(
          LogicalKeyboardKey.tab,
          control: true,
          shift: true,
        ): () => _shortcutCycleSession(-1),
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Padding(
        padding: const EdgeInsets.all(AppLayout.gapLg),
        child: ValueListenableBuilder<String?>(
          valueListenable: _activeSessionId,
          builder: (context, activeId, _) {
            // 当前会话若已被关闭，回退到最后一个会话（只影响显示，不改通知器）。
            var active = activeId;
            if (active != null && !sessions.containsKey(active)) {
              active = sessions.isNotEmpty ? sessions.keys.last : null;
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_panelVisible) ...[
                  _ConnectionPanel(
                    connections: connections,
                    activeId: active,
                    onSelect: (id) => _activeSessionId.value = id,
                    onAdd: _showConnectionDialog,
                    onEdit: (conn) => _showConnectionDialog(connection: conn),
                    onDelete: (conn) => _deleteConnection(conn),
                    onConnect: (conn) => _openSession(conn),
                    onToggle: () => setState(() {
                      _panelVisible = false;
                      _saveLayoutDebounced();
                    }),
                  ),
                  const SizedBox(width: AppLayout.gapMd),
                ],
                Expanded(
                  child: sessions.isEmpty
                      ? Stack(
                          children: [
                            if (!_panelVisible)
                              Positioned(
                                top: 0,
                                left: 0,
                                child: FButton(
                                  mainAxisSize: MainAxisSize.min,
                                  variant: FButtonVariant.ghost,
                                  size: FButtonSizeVariant.sm,
                                  semanticsTooltip: '显示连接面板',
                                  onPress: () => setState(() {
                                    _panelVisible = true;
                                    _saveLayoutDebounced();
                                  }),
                                  child: const Icon(
                                    FLucideIcons.panelLeftClose,
                                  ),
                                ),
                              ),
                            Center(
                              child: AppEmptyHint(
                                icon: FLucideIcons.terminal,
                                text: '还没有打开的会话',
                                detail:
                                    '在左侧选择连接，点它右侧的连接按钮即可打开 SSH 会话',
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SessionTabBar(
                              sessions: sessions,
                              activeId: active,
                              onActivate: (id) =>
                                  _activeSessionId.value = id,
                              onClose: (id) => _closeSession(id),
                              onTogglePanel: () => setState(() {
                                    _panelVisible = true;
                                    _saveLayoutDebounced();
                                  }),
                              panelVisible: _panelVisible,
                            ),
                            if (sessions.isNotEmpty)
                              Expanded(
                                child: IndexedStack(
                                  // 有会话但未选中时默认激活最后一个，避免 index -1。
                                  index: sessions.keys
                                      .toList()
                                      .indexOf(active ?? sessions.keys.last),
                                  children: [
                                    for (final entry in sessions.entries)
                                      _SessionContent(
                                        key: ValueKey(
                                          entry.value.connection.id,
                                        ),
                                        handle: entry.value,
                                        // 只有当前显示的会话保持监控采集；
                                        // 后台会话暂停，避免每秒打断前台。
                                        active:
                                            entry.key == (active ?? sessions.keys.last),
                                        initialMonitorVisible: _monitorVisible,
                                        initialMonitorHeight: _monitorHeight,
                                        initialSplitRatio: _splitRatio,
                                        onLayoutChanged: _onSessionLayoutChanged,
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
      ),
    );
  }

  /// Ctrl+N：新建连接（终端聚焦时让行）。
  void _shortcutNewConnection() {
    if (ref.read(terminalFocusProvider)) return;
    unawaited(_showConnectionDialog());
  }

  /// Ctrl+W：关闭当前会话（终端聚焦时让行）。
  void _shortcutCloseSession() {
    if (ref.read(terminalFocusProvider)) return;
    final sessions = ref.read(sshSessionsProvider);
    if (sessions.isEmpty) return;
    _closeSession(_activeSessionId.value ?? sessions.keys.last);
  }

  /// Ctrl+Tab / Ctrl+Shift+Tab：在同一连接的多个会话间循环。
  void _shortcutCycleSession(int delta) {
    if (ref.read(terminalFocusProvider)) return;
    final ids = ref.read(sshSessionsProvider).keys.toList();
    if (ids.length < 2) return;
    final current = ids.indexOf(_activeSessionId.value ?? ids.last);
    final next = (current + delta + ids.length) % ids.length;
    _activeSessionId.value = ids[next];
  }

  Future<void> _openSession(SshConnection connection) async {
    _activeSessionId.value = connection.id;
    await ref.read(sshSessionsProvider.notifier).open(connection);
  }

  void _closeSession(String id) {
    ref.read(sshSessionsProvider.notifier).close(id);
    if (_activeSessionId.value == id) _activeSessionId.value = null;
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
    // 测试连接的状态用 ValueNotifier 持有，而不是 StatefulBuilder 的局部变量：
    // 「测试连接」按钮位于弹窗底部操作区（StatefulBuilder 之外），
    // 只有 notifier 才能同时驱动按钮加载态与内容区结果提示。
    final testing = ValueNotifier(false);
    final testResult = ValueNotifier<String?>(null);

    /// 表单校验状态：保存/测试按钮按合法性置灰（**校验前移**，
    /// 不再出现「保存 → 弹窗关闭 → 刚填的内容全丢」）。
    final formState = DialogFormState();

    String? validateForm() {
      if (nameController.text.trim().isEmpty) return '请填写连接名称';
      if (hostController.text.trim().isEmpty) return '请填写主机地址';
      if (usernameController.text.trim().isEmpty) return '请填写用户名';
      final port = int.tryParse(portController.text.trim());
      if (port == null || port < 1 || port > 65535) {
        return '端口需为 1–65535 之间的数字';
      }
      if (useKeyAuth && keyPathController.text.trim().isEmpty) {
        return '选择私钥认证后需要指定私钥文件';
      }
      return null;
    }

    void revalidate() => formState.check(validateForm);

    // 两个按钮都要随「测试中 / 表单合法性」变化刷新可用性，合并成一个重建源。
    final buttonState = Listenable.merge([testing, formState]);

    final saved = await showAppDialog<bool>(
      context: context,
      title: connection == null ? '新建 SSH 连接' : '编辑 SSH 连接',
      subtitle: '填写服务器信息，保存前可先测试连接是否可达。',
      // 字段名在左、输入框在右，略加宽让输入框仍有足够长度。
      width: dialogWidthLarge,
      content: SingleChildScrollView(
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            final textTheme = context.theme.typography.body;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppFormRow(
                  label: '连接名称',
                  description: '用于区分不同服务器，例如按用途或机房命名',
                  child: FTextField(
                    control: FTextFieldControl.managed(
                      controller: nameController,
                      onChange: (_) => revalidate(),
                    ),
                    autofocus: connection == null,
                  ),
                ),
                const SizedBox(height: AppLayout.gapMd),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: AppFormRow(
                        label: '主机',
                        description: '服务器 IP 或域名，例如 10.0.0.10',
                        // 标签列宽必须与其它行一致（默认 formLabelWidth），
                        // 否则这一行的输入框左缘会与上下行错开。
                        child: FTextField(
                          control: FTextFieldControl.managed(
                            controller: hostController,
                            onChange: (_) => revalidate(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppLayout.gapMd),
                    Expanded(
                      flex: 2,
                      child: AppFormRow(
                        label: '端口',
                        description: 'SSH 端口，默认 22',
                        child: FTextField(
                          control: FTextFieldControl.managed(
                            controller: portController,
                            onChange: (_) => revalidate(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppLayout.gapMd),
                AppFormRow(
                  label: '用户名',
                  description: 'SSH 登录用户名',
                  child: FTextField(
                    control: FTextFieldControl.managed(
                      controller: usernameController,
                      onChange: (_) => revalidate(),
                    ),
                  ),
                ),
                const SizedBox(height: AppLayout.gapMd),
                AppFormRow(
                  label: '密码',
                  description: 'SSH 登录密码；使用私钥认证时可以留空',
                  child: FTextField(
                    control: FTextFieldControl.managed(
                      controller: passwordController,
                      onChange: (_) => revalidate(),
                    ),
                    obscureText: true,
                  ),
                ),
                const SizedBox(height: AppLayout.gapMd),
                // 认证方式：密码 / 私钥（ForUI 下拉，替代 Material 分段控件）
                AppFormRow(
                  label: '认证方式',
                  description: '密码用服务器账号登录；私钥用本地密钥文件登录',
                  child: FSelect<bool>(
                    control: FSelectControl<bool>.lifted(
                      value: useKeyAuth,
                      onChange: (v) {
                        setDialogState(() => useKeyAuth = v ?? false);
                        revalidate();
                      },
                    ),
                    items: const {'密码认证': false, '私钥认证': true},
                  ),
                ),
                if (useKeyAuth) ...[
                  const SizedBox(height: AppLayout.gapMd),
                  // 私钥路径输入与「选择文件」同排，避免按钮独占一行。
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: AppFormRow(
                          label: '私钥文件',
                          description: '支持 OpenSSH / RSA / EC PEM 格式的私钥文件',
                          child: FTextField(
                            control: FTextFieldControl.managed(
                              controller: keyPathController,
                              onChange: (_) => revalidate(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppLayout.gapSm),
                      FButton(
                        mainAxisSize: MainAxisSize.min,
                        variant: FButtonVariant.outline,
                        onPress: () async {
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
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(FLucideIcons.folderOpen, size: 16),
                            SizedBox(width: 6),
                            Text('选择文件'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppLayout.gapMd),
                  AppFormRow(
                    label: '口令',
                    description: '私钥的 passphrase，没有则留空',
                    child: FTextField(
                      control: FTextFieldControl.managed(
                        controller: passphraseController,
                        onChange: (_) => revalidate(),
                      ),
                      obscureText: true,
                    ),
                  ),
                ],
                // 校验提示：动过表单后才出现（未动过时不打扰）。
                DialogFormHint(state: formState),
                // 测试结果（由底部「测试连接」按钮驱动）。
                ValueListenableBuilder<String?>(
                  valueListenable: testResult,
                  builder: (context, result, _) {
                    if (result == null) return const SizedBox.shrink();
                    final ok = result.startsWith('连接成功');
                    final colors = context.theme.colors;
                    final color = ok ? colors.primary : colors.destructive;
                    return Padding(
                      padding: const EdgeInsets.only(top: AppLayout.gapMd),
                      child: Row(
                        children: [
                          Icon(
                            ok ? FLucideIcons.check : FLucideIcons.info,
                            size: 15,
                            color: color,
                          ),
                          const SizedBox(width: AppLayout.gapSm),
                          Expanded(
                            child: Text(
                              result,
                              style: textTheme.sm.copyWith(color: color),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
      leadingActions: [
        // 与「取消 / 保存」同一行，避免测试按钮独占一行。
        ListenableBuilder(
          listenable: buttonState,
          builder: (context, _) => FButton(
            mainAxisSize: MainAxisSize.min,
            variant: FButtonVariant.outline,
            onPress: (testing.value || !formState.canSubmit)
                ? null
                : () async {
                    testing.value = true;
                    testResult.value = null;
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
                    testing.value = false;
                    testResult.value = result;
                  },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  testing.value
                      ? FLucideIcons.refreshCw
                      : FLucideIcons.sparkles,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(testing.value ? '测试中…' : '测试连接'),
              ],
            ),
          ),
        ),
      ],
      actions: [
        FButton(
          mainAxisSize: MainAxisSize.min,
          variant: FButtonVariant.ghost,
          onPress: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        ListenableBuilder(
          listenable: buttonState,
          builder: (context, _) => FButton(
            mainAxisSize: MainAxisSize.min,
            variant: FButtonVariant.primary,
            // 校验未通过时置灰——用户不会被「保存后弹窗关闭、输入全丢」坑到。
            onPress: formState.canSubmit
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
    showAppToast(context, message);
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
    final p = context.theme.colors;

    return Container(
      width: AppLayout.connectionPanelWidth,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: context.theme.style.borderRadius.xl,
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppLayout.gapLg,
              AppLayout.gapMd,
              AppLayout.gapSm,
              AppLayout.gapSm,
            ),
            child: Row(
              children: [
                Text(
                  '连接',
                  style: context.theme.typography.body.sm.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                FButton(
                  mainAxisSize: MainAxisSize.min,
                  variant: FButtonVariant.ghost,
                  size: FButtonSizeVariant.sm,
                  semanticsTooltip: '收起连接面板',
                  onPress: onToggle,
                  child: const Icon(FLucideIcons.chevronDown, size: 18),
                ),
                FButton(
                  mainAxisSize: MainAxisSize.min,
                  variant: FButtonVariant.ghost,
                  size: FButtonSizeVariant.sm,
                  semanticsTooltip: '新建连接',
                  onPress: onAdd,
                  child: const Icon(FLucideIcons.plus, size: 20),
                ),
              ],
            ),
          ),
          const FDivider(),
          Expanded(
            child: connections.isEmpty
                ? const AppEmptyHint(
                    icon: FLucideIcons.server,
                    text: '暂无连接',
                    detail: '点击右上角 + 新建 SSH 连接',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(AppLayout.gapSm),
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
    final p = context.theme.colors;
    final connection = this.connection;

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: active ? p.secondary : Colors.transparent,
          borderRadius: context.theme.style.borderRadius.md,
        ),
        child: FTappable(
          onPress: onTap,
          onDoubleTap: onConnect,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppLayout.gapMd,
              vertical: AppLayout.gapSm + 2,
            ),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: active
                        ? p.primary
                        : p.mutedForeground.withValues(alpha: .4),
                    shape: BoxShape.circle,
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: p.primary.withValues(alpha: .35),
                              blurRadius: 0,
                              spreadRadius: 4,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: AppLayout.gapSm + 2),
                // 只显示连接名；IP 地址在 hover 时以 Tooltip 展示。
                Expanded(
                  child: AppTooltip(
                    message: '${connection.username}@${connection.hostLabel}',
                    child: Text(
                      connection.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.theme.typography.body.xs.copyWith(fontWeight: active ? FontWeight.w600 : FontWeight.w400, color: active ? p.primary : p.foreground),
                    ),
                  ),
                ),
                const SizedBox(width: AppLayout.gapXs),
                // 按钮间留 2px 间隙：命中区相邻但视觉分离，
                // 避免悬停从上一个按钮过渡到下一个时高亮「连成一片」。
                TileIconButton(
                  icon: FLucideIcons.terminal,
                  tooltip: '连接',
                  onPress: onConnect,
                ),
                const SizedBox(width: 2),
                TileIconButton(
                  icon: FLucideIcons.pencil,
                  tooltip: '编辑连接',
                  onPress: onEdit,
                ),
                const SizedBox(width: 2),
                TileIconButton(
                  icon: FLucideIcons.trash2,
                  tooltip: '删除连接',
                  onPress: onDelete,
                  destructive: true,
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
///
/// 「新建连接」入口只在左侧连接面板里保留（此处不再重复放 + 按钮）。
class _SessionTabBar extends ConsumerWidget {
  const _SessionTabBar({
    required this.sessions,
    required this.activeId,
    required this.onActivate,
    required this.onClose,
    required this.onTogglePanel,
    required this.panelVisible,
  });

  final Map<String, SshSessionHandle> sessions;
  final String? activeId;
  final ValueChanged<String> onActivate;
  final ValueChanged<String> onClose;
  final VoidCallback onTogglePanel;
  final bool panelVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    final activeHandle = activeId == null ? null : sessions[activeId];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppLayout.gapSm),
      child: Row(
        children: [
          if (!panelVisible)
            FButton(
              mainAxisSize: MainAxisSize.min,
              variant: FButtonVariant.ghost,
              size: FButtonSizeVariant.sm,
              semanticsTooltip: '显示连接面板',
              onPress: onTogglePanel,
              child: const Icon(FLucideIcons.panelLeftClose, size: 17),
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
                    padding: const EdgeInsets.only(right: AppLayout.gapSm),
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
                final (label, variant) = switch (status) {
                  SshSessionStatus.connecting => ('连接中…', FBadgeVariant.primary),
                  SshSessionStatus.connected => ('已连接', FBadgeVariant.primary),
                  SshSessionStatus.error => ('连接失败', FBadgeVariant.destructive),
                  SshSessionStatus.closed => ('已断开', FBadgeVariant.secondary),
                };
                return Padding(
                  padding: const EdgeInsets.only(right: AppLayout.gapSm),
                  child: FBadge(variant: variant, child: Text(label)),
                );
              },
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
    final p = context.theme.colors;
    final bg = widget.active
        ? p.secondary
        : (_hovered ? p.background : Colors.transparent);
    final fg = widget.active ? p.primary : p.mutedForeground;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: context.theme.style.borderRadius.sm,
        ),
        child: FTappable(
          onPress: widget.onTap,
          child: Container(
            height: 30,
            padding: const EdgeInsets.only(left: AppLayout.gapMd),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: context.theme.typography.body.xs.copyWith(color: fg, fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400),
                ),
                FTappable(
                  onPress: widget.onClose,
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Icon(
                      FLucideIcons.x,
                      size: 13,
                      color: p.mutedForeground,
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
  const _SessionContent({
    super.key,
    required this.handle,
    required this.active,
    required this.onLayoutChanged,
    this.initialMonitorVisible = true,
    this.initialMonitorHeight = 280,
    this.initialSplitRatio = 0.5,
  });

  final SshSessionHandle handle;

  /// 布局变化回调（监控显隐/高度、终端分栏比例），由页面持久化。
  final void Function({
    required bool monitorVisible,
    required double monitorHeight,
    required double splitRatio,
  })
  onLayoutChanged;

  final bool initialMonitorVisible;
  final double initialMonitorHeight;
  final double initialSplitRatio;

  /// 是否是当前显示的会话。IndexedStack 保活让所有会话都挂在树上，
  /// 若不区分前后台，后台会话的监控器也会每秒经 SSH 采集并触发重建，
  /// 是会话切换卡顿与内存占用的主因。切到后台即暂停采集，切回自动恢复。
  final bool active;

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

  /// 是否因切到后台而暂停了监控（切回时据此恢复）。
  bool _pausedForBackground = false;

  @override
  void initState() {
    super.initState();
    _controller = TerminalController();
    // 应用持久化的布局偏好。
    _monitorVisible = widget.initialMonitorVisible;
    _monitorHeight = widget.initialMonitorHeight;
    _splitRatio = widget.initialSplitRatio;
    // 选中变化 → 自动复制选中文本到剪切板。
    _controller.addListener(_onSelectionChanged);
    // 上报终端焦点：页面级快捷键据此决定是否让行。
    _terminalFocus.addListener(_publishTerminalFocus);
    // 会话打开时终端自动聚焦，可直接键入命令；
    // 之后由 MouseRegion 悬停聚焦，不随 build 反复抢焦点。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _terminalFocus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant _SessionContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _resumeMonitorIfPaused();
    } else {
      _pauseMonitorForBackground();
    }
  }

  /// 切到后台：暂停监控采集（保留历史，切回无缝接续）。
  /// 面板本身被隐藏（_monitorVisible == false）时本来就停着，无需处理。
  void _pauseMonitorForBackground() {
    if (!_monitorVisible || !_monitorController.state.running) return;
    _monitorController.pause();
    _pausedForBackground = true;
  }

  /// 切回前台：恢复采集。
  void _resumeMonitorIfPaused() {
    if (!_pausedForBackground) return;
    _pausedForBackground = false;
    final client = widget.handle.client;
    if (client != null) _monitorController.resumeWithClient(client);
  }

  /// 把「终端是否有焦点」同步给页面（供快捷键让行）。
  void _publishTerminalFocus() {
    if (!mounted) return;
    ref.read(terminalFocusProvider.notifier).set(_terminalFocus.hasFocus);
  }

  @override
  void dispose() {
    _controller.removeListener(_onSelectionChanged);
    _controller.dispose();
    _terminalFocus.removeListener(_publishTerminalFocus);
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
    _reportLayout();
  }

  /// 把当前布局回报给页面（页面负责持久化）。
  void _reportLayout() => widget.onLayoutChanged(
    monitorVisible: _monitorVisible,
    monitorHeight: _monitorHeight,
    splitRatio: _splitRatio,
  );

  /// 拖拽调整监控面板高度（向上拖增大，向下拖减小）。
  void _resizeMonitor(double dy, double maxHeight) {
    setState(() {
      _monitorHeight = (_monitorHeight - dy).clamp(120.0, maxHeight * 0.72);
    });
    _reportLayout();
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
                      AppResizeHandle(
                        style: ResizeHandleStyle.capsule,
                        onDrag: (dx) {
                          setState(() {
                            final w = constraints.maxWidth - AppLayout.gapMd;
                            _splitRatio =
                                (_splitRatio + dx / (w <= 0 ? 1 : w)).clamp(
                              0.3,
                              0.7,
                            );
                          });
                          _reportLayout();
                        },
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
              AppResizeHandle(
                axis: Axis.vertical,
                style: ResizeHandleStyle.capsule,
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
    final p = context.theme.colors;
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: context.theme.style.borderRadius.lg,
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PaneHeader(
            icon: FLucideIcons.terminal,
            title: '终端',
            actions: [
              FButton(
                mainAxisSize: MainAxisSize.min,
                variant: FButtonVariant.ghost,
                size: FButtonSizeVariant.sm,
                semanticsTooltip: '隐藏终端',
                onPress: onToggle,
                child: const Icon(FLucideIcons.eyeOff, size: 15),
              ),
            ],
          ),
          Expanded(
            child: Container(
              color: p.card,
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
        color: context.theme.colors.card,
        borderRadius: context.theme.style.borderRadius.lg,
        border: Border.all(color: context.theme.colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PaneHeader(
            icon: FLucideIcons.folder,
            title: '文件',
            actions: [
              FButton(
                mainAxisSize: MainAxisSize.min,
                variant: FButtonVariant.ghost,
                size: FButtonSizeVariant.sm,
                semanticsTooltip: '隐藏文件',
                onPress: onToggle,
                child: const Icon(FLucideIcons.eyeOff, size: 15),
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
    final p = context.theme.colors;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppLayout.gapMd),
      decoration: BoxDecoration(
        color: p.card,
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: p.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: context.theme.typography.body.xs.copyWith(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

/// 监控高度拖拽条：上下拖动调整监控面板高度（上拖变高，下拖变矮）。
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
    final p = context.theme.colors;
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: context.theme.style.borderRadius.lg,
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
                padding: const EdgeInsets.symmetric(horizontal: AppLayout.gapMd),
                decoration: BoxDecoration(
                  color: p.card,
                  border: visible
                      ? Border(bottom: BorderSide(color: p.border))
                      : null,
                ),
                child: LayoutBuilder(
                  builder: (context, header) {
                    // 窄宽度下按钮只留图标（tooltip 仍在），避免标题栏横向溢出。
                    final labels = header.maxWidth >= 560;

                    Widget action(
                      IconData icon,
                      String label,
                      VoidCallback? onPress,
                    ) => FButton(
                      mainAxisSize: MainAxisSize.min,
                      variant: FButtonVariant.ghost,
                      size: FButtonSizeVariant.sm,
                      semanticsTooltip: label,
                      onPress: onPress,
                      child: labels
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon, size: 15),
                                const SizedBox(width: 6),
                                Text(label),
                              ],
                            )
                          : Icon(icon, size: 15),
                    );

                    return Row(
                      children: [
                        Icon(FLucideIcons.activity, size: 16, color: p.primary),
                        const SizedBox(width: 6),
                        Text(
                          '服务器监控',
                          style: context.theme.typography.body.xs.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: AppLayout.gapSm),
                        FBadge(
                          variant: running
                              ? FBadgeVariant.primary
                              : FBadgeVariant.secondary,
                          child: Text(running ? '监控中' : '已停止'),
                        ),
                        const Spacer(),
                        action(
                          FLucideIcons.info,
                          '服务器信息',
                          () => _showServerInfo(context),
                        ),
                        // 终端/文件被隐藏时的恢复按钮（彻底隐藏，无残留条）。
                        if (showTerminal)
                          action(
                            FLucideIcons.terminal,
                            '显示终端',
                            onShowTerminal,
                          ),
                        if (showFiles)
                          action(FLucideIcons.folder, '显示文件', onShowFiles),
                        const SizedBox(width: AppLayout.gapSm),
                        FTappable(
                          onPress: onToggle,
                          semanticsTooltip: visible ? '隐藏监控' : '显示监控',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppLayout.gapSm,
                              vertical: 5,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  visible
                                      ? FLucideIcons.chevronUp
                                      : FLucideIcons.chevronDown,
                                  size: 17,
                                  color: p.mutedForeground,
                                ),
                                if (labels) ...[
                                  const SizedBox(width: 3),
                                  Text(
                                    visible ? '隐藏监控' : '显示监控',
                                    style: context.theme.typography.body.xs.copyWith(color: p.mutedForeground),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
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
        showAppToast(context, '请先连接会话', error: true);
        return;
      }
      controller.startWithClient(client);
    }
    await controller.fetchServerInfo();
    if (!wasRunning) controller.stop();

    final info = controller.state.serverInfo;
    if (!context.mounted) return;
    if (info == null) {
      showAppToast(context, '服务器信息查询失败', error: true);
      return;
    }

    await showAppDialog<void>(
      context: context,
      title: '服务器信息',
      width: dialogWidthSmall,
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
                : formatBytes((int.tryParse(info['MEM_TOTAL']!) ?? 0) * 1024),
          ),
          _InfoRow(
            '磁盘总量',
            info['DISK_TOTAL'] == null
                ? '-'
                : formatBytes((int.tryParse(info['DISK_TOTAL']!) ?? 0) * 1024),
          ),
          _InfoRow('IP 地址', info['IP'] ?? '-'),
        ],
      ),
      actions: [
        FButton(
          mainAxisSize: MainAxisSize.min,
          variant: FButtonVariant.ghost,
          onPress: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
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
    // RepaintBoundary：把终端的重绘范围限制在其自身，切换会话/其它面板
    // 变化时不会牵动整块重绘（终端缓冲区大，整页重绘代价高）。
    return RepaintBoundary(
      child: ClipRect(
        child: MouseRegion(
        cursor: SystemMouseCursors.text,
        onEnter: (_) {
          if (!focusNode.hasFocus) focusNode.requestFocus();
        },
        child: TerminalView(
          handle.terminal,
          focusNode: focusNode,
          autofocus: true,
          // 走默认 CustomTextEdit（TextInput 通道）：Windows 中文 IME
          // 上屏文本只通过 flutter/textinput 送达，硬件键盘 KeyEvent
          // 收不到中文（引擎压制 WM_CHAR 转换）。vendor 的 xterm 已补
          // viewId，修复 Flutter 3.32+ 下 attach 失败。
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
                  const Icon(FLucideIcons.copy, size: 16),
                  const SizedBox(width: 8),
                  Text(selection != null ? '复制' : '复制（无选中）'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'paste',
              child: Row(
                children: [
                  Icon(FLucideIcons.clipboardPaste, size: 16),
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
      ),
    );
  }
}

/// 嵌入会话的监控视图：四张独立趋势图 + GPU/NPU + TOP 进程。
class _HeadText extends StatelessWidget {
  const _HeadText(this.text, {this.right = false});

  final String text;
  final bool right;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: right ? TextAlign.right : TextAlign.left,
      style: context.theme.typography.body.xs2.copyWith(fontWeight: FontWeight.w600, color: context.theme.colors.mutedForeground),
    );
  }
}
