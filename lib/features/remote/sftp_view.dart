import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:toolbox/common/app_log.dart';
import 'package:toolbox/common/byte_format.dart';
import 'package:toolbox/features/remote/ssh_session.dart';
import 'package:toolbox/features/remote/transfer_controller.dart';
import 'package:toolbox/features/remote/transfer_worker.dart';
import 'package:toolbox/ui/theme/app_layout.dart';
import 'package:toolbox/ui/widgets/app_dialog.dart';
import 'package:toolbox/ui/widgets/app_form_row.dart';
import 'package:toolbox/ui/widgets/app_toast.dart';
import 'package:toolbox/ui/widgets/app_tooltip.dart';

part 'sftp_file_list.dart';
/// SFTP 文件浏览视图：路径可编辑直达，支持上传/下载/新建目录/删除/
/// 权限详情与修改。目录状态保存在视图 State 中，配合外层 IndexedStack
/// 保活，切换视图不丢失当前位置。
class SftpView extends ConsumerStatefulWidget {
  const SftpView({super.key, required this.handle});

  final SshSessionHandle handle;

  @override
  ConsumerState<SftpView> createState() => _SftpViewState();
}

class _SftpViewState extends ConsumerState<SftpView> {
  String _path = '/';
  late final TextEditingController _pathController;
  final FocusNode _pathFocus = FocusNode();
  List<SftpName>? _entries;
  List<_PathSuggestion> _suggestions = const [];
  Timer? _suggestDebounce;
  bool _loading = false;
  bool _connected = false;

  /// 排序字段：name / date / size。
  String _sortField = 'name';

  /// 是否升序。
  bool _sortAsc = true;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(text: _path);
    _connected = widget.handle.isConnected;
    widget.handle.status.addListener(_onStatusChanged);
    if (_connected) _resolveHome();
  }

  @override
  void dispose() {
    widget.handle.status.removeListener(_onStatusChanged);
    _suggestDebounce?.cancel();
    _pathController.dispose();
    _pathFocus.dispose();
    super.dispose();
  }

  /// 会话状态变化时同步本地连接标志：断开后禁用操作按钮（此前只在
  /// 连接成功时置 true，断线后按钮仍可点导致报错）。
  void _onStatusChanged() {
    final connected = widget.handle.isConnected;
    if (connected == _connected) return;
    setState(() => _connected = connected);
    if (connected) _resolveHome();
  }

  /// 解析登录用户的 home 目录（sftp 初始当前目录）作为默认目录。
  Future<void> _resolveHome() async {
    try {
      final sftp = await widget.handle.sftp();
      var home = await sftp.absolute('.');
      if (home.isEmpty) home = '/';
      if (home.length > 1 && home.endsWith('/')) {
        home = home.substring(0, home.length - 1);
      }
      _goTo(home);
    } catch (_) {
      _goTo('/');
    }
  }

  bool get _isRoot => _path == '/';

  String _join(String name) => _isRoot ? '/$name' : '$_path/$name';

  String _parentPath() {
    if (_isRoot) return _path;
    final trimmed = _path.endsWith('/')
        ? _path.substring(0, _path.length - 1)
        : _path;
    final slash = trimmed.lastIndexOf('/');
    return slash <= 0 ? '/' : trimmed.substring(0, slash);
  }

  void _goTo(String path) {
    setState(() {
      _path = path.trim().isEmpty ? '/' : path.trim();
      _pathController.text = _path;
      // 路径跳转后清空补全建议，避免残留占位。
      _suggestions = const [];
    });
    _refresh();
  }

  /// 根据输入文本计算补全建议（防抖 250ms）。
  void _onPathChanged(String text) {
    _suggestDebounce?.cancel();
    _suggestDebounce = Timer(const Duration(milliseconds: 250), () {
      _updateSuggestions(text);
    });
  }

  Future<void> _updateSuggestions(String text) async {
    if (!_connected) {
      if (mounted) setState(() => _suggestions = const []);
      return;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.startsWith('~')) {
      if (mounted) setState(() => _suggestions = const []);
      return;
    }
    final lastSlash = trimmed.lastIndexOf('/');
    // 当前所在目录（含末尾斜杠）与输入前缀。
    final dirPart = lastSlash < 0 ? '/' : trimmed.substring(0, lastSlash + 1);
    final prefix = lastSlash < 0 ? trimmed : trimmed.substring(lastSlash + 1);

    try {
      final sftp = await widget.handle.sftp();
      final entries = await sftp.listdir(dirPart);
      final matches = entries
          .where((e) =>
              e.filename != '.' &&
              e.filename != '..' &&
              e.filename.toLowerCase().startsWith(prefix.toLowerCase()))
          .toList()
        ..sort(
          (a, b) => a.filename.toLowerCase().compareTo(b.filename.toLowerCase()),
        );
      if (!mounted) return;
      setState(() => _suggestions = [
            for (final e in matches)
              _PathSuggestion(
                fullPath: dirPart + e.filename,
                label: e.filename,
                isDir: _isDir(e),
              ),
          ]);
    } catch (_) {
      if (mounted) setState(() => _suggestions = const []);
    }
  }

  /// 点击补全项：目录则直接进入，文件则填入路径。
  void _applySuggestion(_PathSuggestion s) {
    setState(() => _suggestions = const []);
    if (s.isDir) {
      _goTo(s.fullPath);
    } else {
      setState(() => _pathController.text = s.fullPath);
    }
  }

  Future<void> _refresh() async {
    // 未连接时直接返回，避免 sftp() 抛 StateError（防御任何时序）。
    if (!widget.handle.isConnected) return;
    setState(() => _loading = true);
    try {
      final sftp = await widget.handle.sftp();
      final entries = await sftp.listdir(_path);
      final filtered = entries
          .where((e) => e.filename != '.' && e.filename != '..')
          .toList()
        ..sort(_compareEntries);
      setState(() => _entries = filtered);
    } catch (e) {
      _showMessage('加载目录失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 按当前排序字段比较两个条目（文件夹与文件混排，不分开）。
  int _compareEntries(SftpName a, SftpName b) {
    int result;
    switch (_sortField) {
      case 'date':
        final at = a.attr.modifyTime ?? 0;
        final bt = b.attr.modifyTime ?? 0;
        result = at.compareTo(bt);
      case 'size':
        final as = a.attr.size ?? 0;
        final bs = b.attr.size ?? 0;
        result = as.compareTo(bs);
      default:
        result = a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
    }
    return _sortAsc ? result : -result;
  }

  bool _isDir(SftpName name) => name.attr.type == SftpFileType.directory;

  void _enterDir(SftpName name) => _goTo(_join(name.filename));

  Future<void> _upload() async {
    if (!_connected) {
      _showMessage('SSH 未连接，请等待连接完成');
      return;
    }
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty) return;
    final conn = widget.handle.connection;
    final transfer = ref.read(transferTasksProvider.notifier);

    // 批量上传：所有文件并发启动，不排队。
    for (final file in picked) {
      final localPath = file.path;
      if (localPath == null) {
        _showMessage('${file.name}：无法获取本地路径');
        continue;
      }
      final localFile = File(localPath);
      final total = await localFile.length();
      // 创建任务（pending 显示）。
      final taskId = transfer.add(
        file.name,
        TransferDirection.upload,
        totalBytes: total,
      );
      // 并发启动 worker（不等待、不排队）。
      _runTransferWorker(
        request: TransferRequest(
          host: conn.host,
          port: conn.port,
          username: conn.username,
          password: conn.password,
          useKeyAuth: conn.useKeyAuth,
          privateKeyPath: conn.privateKeyPath,
          keyPassphrase: conn.keyPassphrase,
          direction: 'upload',
          localPath: localPath,
          remotePath: _join(file.name),
          totalBytes: total,
        ),
        taskId: taskId,
      );
    }
    // 无论成败都刷新目录（失败时远端可能残留半截文件，worker 刻意
    // 不删远端，防止误删用户原有同名文件）。
    _refresh();
  }

  /// 心跳超时：连续该时长未收到任何 worker 消息才判定传输挂起。
  /// 传输中 worker 每 300ms 回报一次进度，正常大文件不会误判。
  static const _transferHeartbeatTimeout = Duration(seconds: 60);

  /// 启动传输 worker 并接管其消息（上传/下载共用）：进度上报 +
  /// 心跳超时保护。
  ///
  /// 超时通过 cancelPort 通知 worker 中断并清理残留，而非只丢弃消息
  /// （否则 worker 仍在后台继续传输，远端文件最终写入完整、UI 却显示
  /// 失败）。[doneHint]/[cancelledHint]/[errorPrefix] 为完成/取消/失败
  /// 时的界面提示（传 null 则不提示）；提示前检查 mounted，避免视图
  /// 销毁后使用已失效的 context。
  void _runTransferWorker({
    required TransferRequest request,
    required String taskId,
    String? doneHint,
    String? cancelledHint,
    String? errorPrefix,
  }) {
    final transfer = ref.read(transferTasksProvider.notifier);
    final port = startTransferWorker(request);
    SendPort? cancelPort;
    Timer? heartbeat;

    /// 已落定（完成/取消/失败/超时）：忽略 worker 迟到的消息。
    var settled = false;

    void resetHeartbeat() {
      heartbeat?.cancel();
      heartbeat = Timer(_transferHeartbeatTimeout, () {
        if (settled) return;
        settled = true;
        try {
          cancelPort?.send(['cancel']);
        } catch (_) {}
        transfer.finish(
          taskId,
          TransferStatus.failed,
          error: '传输超时（长时间无响应）',
        );
        port.close();
      });
    }

    resetHeartbeat();
    port.listen((msg) {
      if (settled) return;
      final list = msg as List<Object?>;
      final type = list[0] as String;
      resetHeartbeat();
      switch (type) {
        case 'cancelPort':
          cancelPort = list[1] as SendPort;
          transfer.setCancelPort(taskId, cancelPort!);
        case 'start':
          transfer.start(taskId);
        case 'total':
          transfer.updateTotal(taskId, list[1] as int);
        case 'progress':
          // dartssh2 回报累计字节。
          transfer.updateProgress(taskId, list[1] as int);
        case 'done':
          settled = true;
          heartbeat?.cancel();
          transfer.finish(taskId, TransferStatus.done);
          port.close();
          if (doneHint != null && mounted) _showMessage(doneHint);
        case 'cancelled':
          settled = true;
          heartbeat?.cancel();
          transfer.finish(taskId, TransferStatus.cancelled);
          port.close();
          if (cancelledHint != null && mounted) _showMessage(cancelledHint);
        case 'error':
          settled = true;
          heartbeat?.cancel();
          transfer.finish(taskId, TransferStatus.failed, error: '${list[1]}');
          port.close();
          AppLog.e(
            'transfer',
            '${request.direction} 失败：${request.localPath}',
            list[1],
          );
          if (errorPrefix != null && mounted) {
            _showMessage('$errorPrefix${list[1]}');
          }
      }
    });
  }

  Future<void> _download(SftpName name) async {
    if (!_connected) {
      _showMessage('SSH 未连接，请等待连接完成');
      return;
    }
    try {
      final dirPath = await FilePicker.getDirectoryPath(
        dialogTitle: '选择保存位置',
      );
      if (dirPath == null || dirPath.isEmpty) return;

      final localFile =
          File('$dirPath${Platform.pathSeparator}${name.filename}');
      // 先查远端文件大小（进度总量）。
      final total = await _remoteSize(name.filename);
      // 后台 isolate 用 dartssh2 SFTP 传输（不卡 UI）。
      final conn = widget.handle.connection;
      final transfer = ref.read(transferTasksProvider.notifier);
      final taskId = transfer.add(
        name.filename,
        TransferDirection.download,
        totalBytes: total,
      );
      _runTransferWorker(
        request: TransferRequest(
          host: conn.host,
          port: conn.port,
          username: conn.username,
          password: conn.password,
          useKeyAuth: conn.useKeyAuth,
          privateKeyPath: conn.privateKeyPath,
          keyPassphrase: conn.keyPassphrase,
          direction: 'download',
          localPath: localFile.path,
          remotePath: _join(name.filename),
          totalBytes: total,
        ),
        taskId: taskId,
        doneHint: '已下载 ${name.filename}',
        cancelledHint: '已取消下载',
        errorPrefix: '下载失败：',
      );
    } catch (e) {
      _showMessage('下载失败：$e');
    }
  }

  /// 查询远端文件大小（复用当前会话的 SFTP 客户端）。
  Future<int> _remoteSize(String filename) async {
    try {
      final sftp = await widget.handle.sftp();
      final remote =
          await sftp.open(_join(filename), mode: SftpFileOpenMode.read);
      final size = (await remote.stat()).size ?? 0;
      await remote.close();
      return size;
    } catch (e) {
      // 预查大小失败（可能是路径格式问题）：写进日志，否则「显示 0 字节」无从排查。
      AppLog.w('sftp', '预查远端文件大小失败 ${_join(filename)}：$e');
      return 0;
    }
  }

  /// 打开文件：下载到系统临时目录后用系统默认程序打开。
  Future<void> _open(SftpName name) async {
    if (!_connected) {
      _showMessage('SSH 未连接，请等待连接完成');
      return;
    }
    try {
      final sftp = await widget.handle.sftp();
      final remote =
          await sftp.open(_join(name.filename), mode: SftpFileOpenMode.read);

      final tempDir = Directory.systemTemp.createTempSync('toolbox_sftp');
      final localFile =
          File('${tempDir.path}${Platform.pathSeparator}${name.filename}');
      final sink = localFile.openWrite();
      try {
        await for (final chunk in remote.read()) {
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
        try {
          await remote.close();
        } catch (_) {}
      }

      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', localFile.path]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [localFile.path]);
      } else {
        await Process.start('xdg-open', [localFile.path]);
      }
      _showMessage('已打开 ${name.filename}');
    } catch (e) {
      _showMessage('打开失败：$e');
    }
  }

  Future<void> _mkdir() async {
    if (!_connected) {
      _showMessage('SSH 未连接，请等待连接完成');
      return;
    }
    final controller = TextEditingController();
    final name = await showAppDialog<String>(
      context: context,
      title: '新建目录',
      width: dialogWidthSmall,
      content: AppFormRow(
        label: '目录名',
        description: '在当前目录下创建的子目录名称',
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
          onPress: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FButton(
          mainAxisSize: MainAxisSize.min,
          variant: FButtonVariant.primary,
          onPress: () => Navigator.pop(context, controller.text.trim()),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FLucideIcons.folderPlus, size: 16),
              SizedBox(width: 6),
              Text('创建'),
            ],
          ),
        ),
      ],
    );
    await disposeAfterDialog([controller]);
    if (name == null || name.isEmpty) return;
    try {
      final sftp = await widget.handle.sftp();
      await sftp.mkdir(_join(name));
      _showMessage('已创建目录 $name');
      _refresh();
    } catch (e) {
      _showMessage('创建目录失败：$e');
    }
  }

  Future<void> _delete(SftpName name) async {
    if (!_connected) {
      _showMessage('SSH 未连接，请等待连接完成');
      return;
    }
    final ok = await showDeleteConfirm(
      context,
      title: '确认删除？',
      description: '将删除「${name.filename}」。',
    );
    if (!ok) return;
    try {
      final sftp = await widget.handle.sftp();
      if (_isDir(name)) {
        await _recursiveDelete(sftp, _join(name.filename));
      } else {
        await sftp.remove(_join(name.filename));
      }
      _showMessage('已删除 ${name.filename}');
      _refresh();
    } catch (e) {
      _showMessage('删除失败：$e');
    }
  }

  /// 递归删除远程目录（含所有子文件/子目录）。
  Future<void> _recursiveDelete(SftpClient sftp, String path) async {
    final entries = await sftp.listdir(path);
    for (final entry in entries) {
      if (entry.filename == '.' || entry.filename == '..') continue;
      final childPath = '$path/${entry.filename}';
      if (entry.attr.type == SftpFileType.directory) {
        await _recursiveDelete(sftp, childPath);
      } else {
        await sftp.remove(childPath);
      }
    }
    await sftp.rmdir(path);
  }

  /// 查看文件详情：类型/大小/权限/修改时间/所属用户组，并可下载/删除/改权限。
  Future<void> _showDetails(SftpName name) async {
    final isDir = _isDir(name);
    final attr = name.attr;
    final modeVal = attr.mode?.value ?? 0;
    final permText = _modeString(modeVal);

    await showAppDialog<void>(
      context: context,
      title: name.filename,
      // 5 个操作按钮（关闭/打开/下载/修改权限/删除）需要更宽的弹窗才能排成一行，
      // 否则会被 Wrap 折到第二行。
      width: dialogWidthLarge,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _detailRow('类型', isDir ? '目录' : '文件'),
          if (attr.size != null) _detailRow('大小', formatBytes(attr.size!)),
          _detailRow(
            '权限',
            modeVal < 0 ? '-' : '$permText (${(modeVal & 0x1FF).toRadixString(8)})',
          ),
          if (attr.modifyTime != null)
            _detailRow('修改时间', _formatTime(attr.modifyTime)),
          if (attr.userID != null) _detailRow('用户 ID', '${attr.userID}'),
          if (attr.groupID != null) _detailRow('组 ID', '${attr.groupID}'),
        ],
      ),
      actions: [
        FButton(
          mainAxisSize: MainAxisSize.min,
          variant: FButtonVariant.ghost,
          onPress: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        if (!isDir)
          FButton(
            mainAxisSize: MainAxisSize.min,
            variant: FButtonVariant.outline,
            onPress: () {
              Navigator.pop(context);
              _open(name);
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FLucideIcons.externalLink, size: 16),
                SizedBox(width: 6),
                Text('打开'),
              ],
            ),
          ),
        if (!isDir)
          FButton(
            mainAxisSize: MainAxisSize.min,
            variant: FButtonVariant.outline,
            onPress: () {
              Navigator.pop(context);
              _download(name);
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FLucideIcons.download, size: 16),
                SizedBox(width: 6),
                Text('下载'),
              ],
            ),
          ),
        FButton(
          mainAxisSize: MainAxisSize.min,
          variant: FButtonVariant.outline,
          onPress: () {
            Navigator.pop(context);
            _changeMode(name);
          },
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FLucideIcons.lock, size: 16),
              SizedBox(width: 6),
              Text('修改权限'),
            ],
          ),
        ),
        FButton(
          mainAxisSize: MainAxisSize.min,
          variant: FButtonVariant.destructive,
          onPress: () {
            Navigator.pop(context);
            _delete(name);
          },
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FLucideIcons.trash2, size: 16),
              SizedBox(width: 6),
              Text('删除'),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _changeMode(SftpName name) async {
    final current = name.attr.mode?.value ?? 0;
    final defaultMode =
        current >= 0 ? (current & 0x1FF).toRadixString(8) : '755';
    final controller = TextEditingController(text: defaultMode);
    final input = await showAppDialog<String>(
      context: context,
      title: '修改权限',
      width: dialogWidthSmall,
      content: AppFormRow(
        label: '权限',
        description: '八进制权限，例如 755 表示 rwxr-xr-x',
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
          onPress: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FButton(
          mainAxisSize: MainAxisSize.min,
          variant: FButtonVariant.primary,
          onPress: () => Navigator.pop(context, controller.text.trim()),
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
    await disposeAfterDialog([controller]);
    if (input == null || input.isEmpty) return;
    final mode = int.tryParse(input, radix: 8);
    if (mode == null) {
      _showMessage('权限格式无效，请输入如 755');
      return;
    }
    try {
      final sftp = await widget.handle.sftp();
      await sftp.setStat(
        _join(name.filename),
        SftpFileAttrs(mode: SftpFileMode.value(mode)),
      );
      _showMessage('已修改 ${name.filename} 的权限');
      _refresh();
    } catch (e) {
      _showMessage('修改权限失败：$e');
    }
  }

  Widget _detailRow(String label, String value) {
    final scheme = context.theme.colors;
    final textTheme = context.theme.typography.body;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppLayout.gapXs),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: textTheme.md.copyWith(
                color: scheme.mutedForeground,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: textTheme.md),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    showAppToast(context, message);
  }

  /// 弹出传输记录窗口（当前/历史上传下载任务与进度）。
  void _showTransferHistory() {
    // 弹窗结果无需处理，显式标记为「有意丢弃的 Future」。
    unawaited(
      showAppDialog<void>(
        context: context,
        title: '传输记录',
        width: dialogWidthMedium,
        content: const SizedBox(height: 320, child: _TransferPanel()),
        actions: [
          FButton(
            mainAxisSize: MainAxisSize.min,
            variant: FButtonVariant.ghost,
            onPress: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 路径栏（可编辑直达）+ 操作按钮。
        // 固定单行布局：文件面板只有约一半窗口宽度，装不下时**横向滚动**，
        // 而不是折行——折行会把列表的可用高度吃掉一大截。
        // ⚠️ Row 里的 FButton 一定要 `mainAxisSize: MainAxisSize.min`，
        // 否则 ForUI 默认的 max 会让按钮撑满可用宽度。
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppLayout.gapMd,
            AppLayout.gapXs,
            AppLayout.gapMd,
            0,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _ToolIcon(
                  icon: FLucideIcons.arrowUp,
                  tooltip: '上一级',
                  onPressed: _isRoot ? null : _goUp,
                ),
                SizedBox(
                  width: 200,
                  child: FTextField(
                    control: FTextFieldControl.managed(
                      controller: _pathController,
                      onChange: (v) => _onPathChanged(v.text),
                    ),
                    hint: '远程路径，回车前往',
                    onSubmit: (_) {
                      setState(() => _suggestions = const []);
                      _goTo(_pathController.text);
                    },
                  ),
                ),
                _ToolIcon(
                  icon: FLucideIcons.arrowRight,
                  tooltip: '前往',
                  onPressed: () {
                    setState(() => _suggestions = const []);
                    _goTo(_pathController.text);
                  },
                ),
                _ToolIcon(
                  icon: FLucideIcons.refreshCw,
                  tooltip: '刷新',
                  onPressed: _refresh,
                ),
                // 排序：字段下拉 + 升降序切换。
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppLayout.gapXs,
                  ),
                  child: SizedBox(
                    width: 104,
                    child: FSelect<String>(
                      control: FSelectControl<String>.lifted(
                        value: _sortField,
                        onChange: (v) {
                          if (v != null) {
                            setState(() => _sortField = v);
                            unawaited(_refresh());
                          }
                        },
                      ),
                      items: const {'名称': 'name', '日期': 'date', '大小': 'size'},
                    ),
                  ),
                ),
                _ToolIcon(
                  icon: _sortAsc
                      ? FLucideIcons.arrowUp
                      : FLucideIcons.arrowDown,
                  tooltip: _sortAsc ? '升序' : '降序',
                  onPressed: () {
                    setState(() => _sortAsc = !_sortAsc);
                    unawaited(_refresh());
                  },
                ),
                _LabeledTool(
                  icon: FLucideIcons.folderPlus,
                  label: '新建目录',
                  onPressed: _mkdir,
                ),
                _LabeledTool(
                  icon: FLucideIcons.upload,
                  label: '上传',
                  onPressed: _upload,
                ),
                // 传输记录按钮：查看当前/历史上传下载进度。
                _ToolIcon(
                  icon: FLucideIcons.history,
                  tooltip: '传输记录',
                  onPressed: _showTransferHistory,
                ),
              ],
            ),
          ),
        ),
        // 路径自动补全建议列表：仅在输入框聚焦且有建议时显示，
        // 失焦或路径跳转后自动隐藏，不占用多余空间。
        if (_pathFocus.hasFocus && _suggestions.isNotEmpty)
          _SuggestionList(
            suggestions: _suggestions,
            onSelect: _applySuggestion,
          ),
        Expanded(
          child: _loading
              ? const Center(child: FCircularProgress())
              : _entries == null
              ? Center(child: Text(_connected ? '加载中…' : '等待连接…'))
              : _entries!.isEmpty
              ? const Center(child: Text('目录为空'))
              // 列按可用宽度自适应：面板被拖窄时逐级隐藏元信息列，
              // 保证「名称」与行内操作按钮始终在可视区内（全屏下四列齐全）。
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = _FileColumns.of(constraints.maxWidth);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _FileListHeader(columns: columns),
                        const FDivider(),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _entries!.length,
                            itemBuilder: (_, i) {
                              final entry = _entries![i];
                              final isDir = _isDir(entry);
                              return _FileRow(
                                entry: entry,
                                isDir: isDir,
                                columns: columns,
                                onOpen: () => isDir
                                    ? _enterDir(entry)
                                    : _showDetails(entry),
                                onDetails: () => _showDetails(entry),
                                onDownload: () => _download(entry),
                                onDelete: () => _delete(entry),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _goUp() => _goTo(_parentPath());

  String _formatTime(int? unixSeconds) {
    if (unixSeconds == null) return '';
    final dt =
        DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  /// 权限字符串，如 `drwxr-xr-x`；目录以 d 开头。mode 无效（负数）时返回 `----------`。
  String _modeString(int mode) {
    if (mode < 0) return '----------';
    const read = 0x4;
    const write = 0x2;
    const exec = 0x1;
    final sb = StringBuffer((mode & 0x4000) != 0 ? 'd' : '-');
    // 右移永不为负，避免左移负位移抛 ArgumentError。
    for (final shift in const [6, 3, 0]) {
      final bits = mode >> shift;
      sb.write((bits & read) != 0 ? 'r' : '-');
      sb.write((bits & write) != 0 ? 'w' : '-');
      sb.write((bits & exec) != 0 ? 'x' : '-');
    }
    return sb.toString();
  }
}
