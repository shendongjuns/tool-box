import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/features/remote/remote_models.dart';
import 'package:toolbox/features/remote/ssh_session.dart';
import 'package:toolbox/features/remote/transfer_controller.dart';
import 'package:toolbox/features/remote/transfer_worker.dart';
import 'package:toolbox/ui/theme/app_icons.dart';
import 'package:toolbox/ui/theme/mochi_cat_tokens.dart';
import 'package:toolbox/ui/widgets/mochi_widgets.dart';

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

  /// 连接完成后自动加载目录（视图常驻，可能在连接前就挂载）。
  void _onStatusChanged() {
    if (widget.handle.isConnected && !_connected) {
      _connected = true;
      _resolveHome();
    }
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
      _runUploadWorker(
        conn: conn,
        taskId: taskId,
        localPath: localPath,
        remotePath: _join(file.name),
        totalBytes: total,
      );
    }
    // 无论成败都刷新（失败/取消时 worker 已清理远端残留文件）。
    _refresh();
  }

  /// 启动单个上传 worker（并发，不等待完成）。
  void _runUploadWorker({
    required SshConnection conn,
    required String taskId,
    required String localPath,
    required String remotePath,
    required int totalBytes,
  }) {
    final transfer = ref.read(transferTasksProvider.notifier);
    final completer = Completer<void>();
    // 超时后忽略后续 worker 消息（任务已结束）。
    var timedOut = false;
    final port = startTransferWorker(TransferRequest(
      host: conn.host,
      port: conn.port,
      username: conn.username,
      password: conn.password,
      useKeyAuth: conn.useKeyAuth,
      privateKeyPath: conn.privateKeyPath,
      keyPassphrase: conn.keyPassphrase,
      direction: 'upload',
      localPath: localPath,
      remotePath: remotePath,
      totalBytes: totalBytes,
    ));
    port.listen((msg) {
      final list = msg as List<Object?>;
      final type = list[0] as String;
      // 超时后忽略 worker 消息（任务已结束）。
      if (timedOut) return;
      if (type == 'cancelPort') {
        transfer.setCancelPort(taskId, list[1] as SendPort);
      } else if (type == 'debug') {
        debugPrint('传输诊断: ${list[1]}');
      } else if (type == 'start') {
        transfer.start(taskId);
      } else if (type == 'progress') {
        transfer.updateProgress(taskId, list[1] as int);
      } else if (type == 'done') {
        transfer.finish(taskId, TransferStatus.done);
        if (!completer.isCompleted) completer.complete();
        port.close();
      } else if (type == 'cancelled') {
        transfer.finish(taskId, TransferStatus.cancelled);
        if (!completer.isCompleted) completer.complete();
        port.close();
      } else if (type == 'error') {
        transfer.finish(taskId, TransferStatus.failed, error: '${list[1]}');
        if (!completer.isCompleted) completer.complete();
        port.close();
      }
    });
    // 超时保护：worker 长时间无响应（崩溃/挂起）时强制结束。
    unawaited(completer.future.timeout(const Duration(minutes: 1)).catchError((_) {
      timedOut = true;
      transfer.finish(taskId, TransferStatus.failed, error: '传输超时');
      try {
        port.close();
      } catch (_) {}
    }));
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
      final port = startTransferWorker(TransferRequest(
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
      ));
      port.listen((msg) {
        final list = msg as List<Object?>;
        final type = list[0] as String;
        if (type == 'cancelPort') {
          transfer.setCancelPort(taskId, list[1] as SendPort);
        } else if (type == 'start') {
          transfer.start(taskId);
        } else if (type == 'total') {
          transfer.updateTotal(taskId, list[1] as int);
        } else if (type == 'progress') {
          // dartssh2 回报累计字节，任务 totalBytes 已由 total 消息设置。
          transfer.updateProgress(taskId, list[1] as int);
        } else if (type == 'done') {
          transfer.finish(taskId, TransferStatus.done);
          _showMessage('已下载 ${name.filename}');
          port.close();
        } else if (type == 'cancelled') {
          transfer.finish(taskId, TransferStatus.cancelled);
          _showMessage('已取消下载');
          port.close();
        } else if (type == 'error') {
          transfer.finish(taskId, TransferStatus.failed, error: '${list[1]}');
          _showMessage('下载失败：${list[1]}');
          port.close();
        }
      });
    } catch (e) {
      _showMessage('下载失败：$e');
    }
  }

  /// 查询远端文件大小（用独立短连接）。
  Future<int> _remoteSize(String filename) async {
    try {
      final client = await defaultSshConnector(widget.handle.connection);
      final sftp = await client.sftp();
      final remote = await sftp.open(
        _join(filename),
        mode: SftpFileOpenMode.read,
      );
      final size = (await remote.stat()).size ?? 0;
      await remote.close();
      await client.close();
      return size;
    } catch (e) {
      // 诊断：dartssh2 预查大小失败（可能是路径格式问题）。
      debugPrint('_remoteSize 失败 ${_join(filename)}: $e');
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
    final name = await showMochiDialog<String>(
      context: context,
      title: '新建目录',
      emoji: '📁',
      width: 400,
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: '目录名'),
      ),
      actions: [
        MochiButton(
          label: '取消',
          type: MochiButtonType.ghost,
          onPressed: () => Navigator.pop(context),
        ),
        MochiButton(
          label: '创建',
          icon: AppIcons.newFolder,
          type: MochiButtonType.primary,
          onPressed: () => Navigator.pop(context, controller.text.trim()),
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

    await showMochiDialog<void>(
      context: context,
      title: name.filename,
      emoji: isDir ? '📁' : '📄',
      width: 400,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _detailRow('类型', isDir ? '目录' : '文件'),
          if (attr.size != null) _detailRow('大小', _formatSize(attr.size)),
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
        MochiButton(
          label: '关闭',
          type: MochiButtonType.ghost,
          onPressed: () => Navigator.pop(context),
        ),
        if (!isDir)
          MochiButton(
            label: '打开',
            icon: AppIcons.openInNew,
            onPressed: () {
              Navigator.pop(context);
              _open(name);
            },
          ),
        if (!isDir)
          MochiButton(
            label: '下载',
            icon: AppIcons.sftpDownload,
            onPressed: () {
              Navigator.pop(context);
              _download(name);
            },
          ),
        MochiButton(
          label: '修改权限',
          icon: AppIcons.lock,
          onPressed: () {
            Navigator.pop(context);
            _changeMode(name);
          },
        ),
        MochiButton(
          label: '删除',
          icon: AppIcons.delete,
          type: MochiButtonType.danger,
          onPressed: () {
            Navigator.pop(context);
            _delete(name);
          },
        ),
      ],
    );
  }

  Future<void> _changeMode(SftpName name) async {
    final current = name.attr.mode?.value ?? 0;
    final defaultMode =
        current >= 0 ? (current & 0x1FF).toRadixString(8) : '755';
    final controller = TextEditingController(text: defaultMode);
    final input = await showMochiDialog<String>(
      context: context,
      title: '修改权限',
      emoji: '🔐',
      width: 400,
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: '八进制权限，如 755'),
      ),
      actions: [
        MochiButton(
          label: '取消',
          type: MochiButtonType.ghost,
          onPressed: () => Navigator.pop(context),
        ),
        MochiButton(
          label: '保存',
          icon: AppIcons.save,
          type: MochiButtonType.primary,
          onPressed: () => Navigator.pop(context, controller.text.trim()),
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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MochiCatSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 72,
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// 弹出传输记录窗口（当前/历史上传下载任务与进度）。
  void _showTransferHistory() {
    showMochiDialog<void>(
      context: context,
      title: '传输记录',
      emoji: '📦',
      width: 460,
      content: const SizedBox(
        height: 320,
        child: _TransferPanel(),
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 路径栏（可编辑直达）+ 操作按钮。
        // 文件面板只有约一半窗口宽度；工具栏横向可滚动（无滚动条），
        // 窄宽度下不溢出。
        Padding(
          padding: const EdgeInsets.all(MochiCatSpacing.md),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _ToolIcon(
                  icon: AppIcons.goUp,
                  tooltip: '上一级',
                  onPressed: _isRoot ? null : _goUp,
                ),
                  SizedBox(
                    width: 180,
                    child: TextField(
                      controller: _pathController,
                      focusNode: _pathFocus,
                      style: textTheme.bodySmall,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '远程路径，回车前往',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: _onPathChanged,
                      onSubmitted: (_) {
                        setState(() => _suggestions = const []);
                        _goTo(_pathController.text);
                      },
                    ),
                  ),
                  _ToolIcon(
                    icon: AppIcons.goForward,
                    tooltip: '前往',
                    onPressed: () {
                      setState(() => _suggestions = const []);
                      _goTo(_pathController.text);
                    },
                  ),
                  _ToolIcon(
                    icon: AppIcons.refresh,
                    tooltip: '刷新',
                    onPressed: _refresh,
                  ),
                  // 排序：字段下拉 + 升降序切换。
                  SizedBox(
                    width: 80,
                    child: MochiSelectField<String>(
                      value: _sortField,
                      items: const [
                        ('name', '名称'),
                        ('date', '日期'),
                        ('size', '大小'),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _sortField = v);
                          _refresh();
                        }
                      },
                    ),
                  ),
                  _ToolIcon(
                    icon: _sortAsc ? AppIcons.goUp : AppIcons.sortDesc,
                    tooltip: _sortAsc ? '升序' : '降序',
                    onPressed: () {
                      setState(() => _sortAsc = !_sortAsc);
                      _refresh();
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(AppIcons.newFolder, size: 16),
                    label: const Text('新建目录'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 32),
                    ),
                    onPressed: _mkdir,
                  ),
                  TextButton.icon(
                    icon: const Icon(AppIcons.sftpUpload, size: 16),
                    label: const Text('上传'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 32),
                    ),
                    onPressed: _upload,
                  ),
                  // 传输记录按钮：查看当前/历史上传下载进度。
                  _ToolIcon(
                    icon: AppIcons.transferHistory,
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
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _entries == null
                  ? Center(child: Text(_connected ? '加载中…' : '等待连接…'))
                  : _entries!.isEmpty
                      ? const Center(child: Text('目录为空'))
                      : Material(
                          // 文件列表的墨水涟漪需要不透明表面（与背景同色）。
                          color: scheme.surface,
                          child: ListView.separated(
                            itemCount: _entries!.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final entry = _entries![i];
                              final isDir = _isDir(entry);
                              final modeVal = entry.attr.mode?.value ?? 0;
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  isDir
                                      ? AppIcons.folder
                                      : AppIcons.fileText,
                                  color: isDir
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                                title: Text(
                                  entry.filename,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: _FileMetaRow(
                                  isDir: isDir,
                                  size: entry.attr.size,
                                  mode: modeVal,
                                  time: entry.attr.modifyTime,
                                ),
                                onTap: isDir
                                    ? () => _enterDir(entry)
                                    : () => _showDetails(entry),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!isDir)
                                      IconButton(
                                        icon: const Icon(AppIcons.sftpDownload,
                                            size: 18),
                                        tooltip: '下载',
                                        onPressed: () => _download(entry),
                                      ),
                                    IconButton(
                                      icon: const Icon(AppIcons.info,
                                          size: 18),
                                      tooltip: '详情',
                                      onPressed: () => _showDetails(entry),
                                    ),
                                    IconButton(
                                      icon: const Icon(AppIcons.delete,
                                          size: 18),
                                      tooltip: '删除',
                                      onPressed: () => _delete(entry),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  void _goUp() => _goTo(_parentPath());

  String _formatSize(int? size) {
    if (size == null) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

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

/// 文件元信息行：大小 / 权限 / 日期 三列固定宽度对齐，
/// 避免字体变化导致每行位置漂移。
class _FileMetaRow extends StatelessWidget {
  const _FileMetaRow({
    required this.isDir,
    required this.size,
    required this.mode,
    required this.time,
  });

  final bool isDir;
  final int? size;
  final int mode;
  final int? time;

  static String _fmtSize(int? size) {
    if (size == null) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String _fmtTime(int? unixSeconds) {
    if (unixSeconds == null) return '';
    final dt =
        DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    // 精简格式：MM-dd HH:mm，窄面板下列宽可控、不易截断。
    return '${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  static String _modeStr(int mode) {
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        );
    final valueStyle = labelStyle?.copyWith(
      color: scheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // 带标签三列：大小：xxx  权限：xxx  日期：xxx
    // 用 Wrap 保证窄面板下自动换行不截断，各列始终对齐。
    return Wrap(
      spacing: 12,
      runSpacing: 2,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: '大小：', style: labelStyle),
            TextSpan(
              text: isDir ? '—' : _fmtSize(size),
              style: valueStyle,
            ),
          ]),
        ),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: '权限：', style: labelStyle),
            TextSpan(
              text: _modeStr(mode),
              style: valueStyle?.copyWith(fontFamily: 'monospace'),
            ),
          ]),
        ),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: '日期：', style: labelStyle),
            TextSpan(text: _fmtTime(time), style: valueStyle),
          ]),
        ),
      ],
    );
  }
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
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: BoxConstraints.tight(const Size(32, 32)),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
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
    final scheme = Theme.of(context).colorScheme;

    // 用 Material 承载背景色（而非外层带色 Container），保证 ListTile
    // 的墨水涟漪有可见的不透明表面，避免 Flutter 的
    // "background color or ink splashes may be invisible" 断言。
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MochiCatSpacing.md,
        0,
        MochiCatSpacing.md,
        MochiCatSpacing.xs,
      ),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MochiCatRadius.md),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 160),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: suggestions.length,
            itemBuilder: (_, i) {
              final s = suggestions[i];
              return ListTile(
                dense: true,
                leading: Icon(
                  s.isDir
                      ? AppIcons.folder
                      : AppIcons.fileText,
                  size: 18,
                  color: s.isDir ? scheme.primary : scheme.onSurfaceVariant,
                ),
                title: Text(s.label),
                onTap: () => onSelect(s),
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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // 内部监听任务列表，仅本面板 rebuild，不影响整个文件视图。
    final tasks = ref.watch(transferTasksProvider);
    if (tasks.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(
        MochiCatSpacing.md,
        0,
        MochiCatSpacing.md,
        MochiCatSpacing.sm,
      ),
      padding: const EdgeInsets.all(MochiCatSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(MochiCatRadius.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('传输任务', style: textTheme.labelMedium),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(AppIcons.delete, size: 14),
                label: const Text('清空已完成'),
                onPressed: () =>
                    ref.read(transferTasksProvider.notifier).clearFinished(),
              ),
            ],
          ),
          const SizedBox(height: MochiCatSpacing.xs),
          // 任务列表可滚动，避免任务多时溢出。
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: tasks.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: MochiCatSpacing.xs),
              itemBuilder: (_, i) {
                final task = tasks[i];
                return Row(
                  children: [
                    Icon(
                      task.direction == TransferDirection.upload
                          ? AppIcons.sftpUpload
                          : AppIcons.sftpDownload,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: MochiCatSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 失败/取消时悬停显示具体原因。
                          Tooltip(
                            message: task.error ?? task.fileName,
                            child: Text(
                              task.fileName,
                              style: textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 2),
                          ClipRRect(
                            borderRadius:
                                BorderRadius.circular(MochiCatRadius.xs),
                            // 完成/取消/失败显示最终进度（done 满条），
                            // 传输中显示实时百分比。
                            child: LinearProgressIndicator(
                              value: task.status == TransferStatus.done
                                  ? 1
                                  : task.progress,
                              minHeight: 6,
                              color: task.status == TransferStatus.cancelled ||
                                      task.status == TransferStatus.failed
                                  ? scheme.onSurfaceVariant.withValues(alpha: .5)
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: MochiCatSpacing.sm),
                    SizedBox(
                      width: 70,
                      child: Text(
                        _taskStatusText(task),
                        style: textTheme.bodySmall?.copyWith(
                          color: _taskStatusColor(task, scheme),
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    // 终止按钮（传输中显示）。
                    if (task.status == TransferStatus.running ||
                        task.status == TransferStatus.pending)
                      IconButton(
                        icon: const Icon(AppIcons.close, size: 16),
                        tooltip: '终止',
                        onPressed: () => ref
                            .read(transferTasksProvider.notifier)
                            .cancel(task.id),
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

  Color _taskStatusColor(TransferTask task, ColorScheme scheme) {
    switch (task.status) {
      case TransferStatus.done:
        return const Color(0xFF2E7D32);
      case TransferStatus.failed:
      case TransferStatus.cancelled:
        return const Color(0xFFC62828);
      case TransferStatus.pending:
      case TransferStatus.running:
        return scheme.onSurfaceVariant;
    }
  }
}
