import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/features/remote/ssh_session.dart';
import 'package:toolbox/ui/theme/appflowy_colors.dart';

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
        ..sort((a, b) {
          final aDir = _isDir(a);
          final bDir = _isDir(b);
          if (aDir != bDir) return aDir ? -1 : 1;
          return a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
        });
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
        ..sort((a, b) {
          final aDir = _isDir(a);
          final bDir = _isDir(b);
          if (aDir != bDir) return aDir ? -1 : 1;
          return a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
        });
      setState(() => _entries = filtered);
    } catch (e) {
      _showMessage('加载目录失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    final sftp = await widget.handle.sftp();
    var success = 0;
    final failures = <String>[];
    for (final file in picked) {
      final localPath = file.path;
      if (localPath == null) {
        failures.add('${file.name}：无法获取本地路径');
        continue;
      }
      try {
        final bytes = await File(localPath).readAsBytes();
        final remote = await sftp.open(
          _join(file.name),
          mode: SftpFileOpenMode.write |
              SftpFileOpenMode.create |
              SftpFileOpenMode.truncate,
        );
        await remote.writeBytes(bytes);
        await remote.close();
        success++;
      } catch (e) {
        failures.add('${file.name}：$e');
      }
    }
    if (failures.isEmpty) {
      _showMessage('已上传 $success 个文件');
      _refresh();
    } else {
      _showMessage(
        '上传完成：成功 $success 个，失败 ${failures.length} 个\n'
        '${failures.join('\n')}',
      );
    }
  }

  Future<void> _download(SftpName name) async {
    if (!_connected) {
      _showMessage('SSH 未连接，请等待连接完成');
      return;
    }
    try {
      // 大文件不支持一次性读进内存，流式分块写盘。
      // file_picker 12 的 saveFile 必须传完整 bytes（不适合大文件），
      // 改用目录选择器选保存目录，再拼文件名流式写入。
      final dirPath = await FilePicker.getDirectoryPath(
        dialogTitle: '选择保存位置',
      );
      if (dirPath == null || dirPath.isEmpty) return;

      final sftp = await widget.handle.sftp();
      final remote =
          await sftp.open(_join(name.filename), mode: SftpFileOpenMode.read);
      final localFile =
          File('$dirPath${Platform.pathSeparator}${name.filename}');
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
      _showMessage('已下载 ${name.filename}');
    } catch (e) {
      _showMessage('下载失败：$e');
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
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建目录'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '目录名'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('删除「${name.filename}」？'),
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
    if (ok != true) return;
    try {
      final sftp = await widget.handle.sftp();
      if (_isDir(name)) {
        await sftp.rmdir(_join(name.filename));
      } else {
        await sftp.remove(_join(name.filename));
      }
      _showMessage('已删除 ${name.filename}');
      _refresh();
    } catch (e) {
      _showMessage('删除失败：$e');
    }
  }

  /// 查看文件详情：类型/大小/权限/修改时间/所属用户组，并可下载/删除/改权限。
  Future<void> _showDetails(SftpName name) async {
    final isDir = _isDir(name);
    final attr = name.attr;
    final modeVal = attr.mode?.value ?? 0;
    final permText = _modeString(modeVal);

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(name.filename),
        content: SizedBox(
          width: 320,
          child: Column(
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          if (!isDir)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _open(name);
              },
              child: const Text('打开'),
            ),
          if (!isDir)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _download(name);
              },
              child: const Text('下载'),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _delete(name);
            },
            child: const Text('删除'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _changeMode(name);
            },
            child: const Text('修改权限'),
          ),
        ],
      ),
    );
  }

  Future<void> _changeMode(SftpName name) async {
    final current = name.attr.mode?.value ?? 0;
    final defaultMode =
        current >= 0 ? (current & 0x1FF).toRadixString(8) : '755';
    final controller = TextEditingController(text: defaultMode);
    final input = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改权限'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '八进制权限，如 755'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
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
      padding: const EdgeInsets.symmetric(vertical: AppflowySpacing.xs),
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 路径栏（可编辑直达）+ 操作按钮
        Padding(
          padding: const EdgeInsets.all(AppflowySpacing.m),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 18),
                tooltip: '上一级',
                onPressed: _isRoot ? null : _goUp,
              ),
              Expanded(
                child: TextField(
                  controller: _pathController,
                  focusNode: _pathFocus,
                  style: textTheme.bodySmall,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '远程路径，如 /home/user，回车前往',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: _onPathChanged,
                  onSubmitted: (_) {
                    setState(() => _suggestions = const []);
                    _goTo(_pathController.text);
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward, size: 18),
                tooltip: '前往',
                onPressed: () {
                  setState(() => _suggestions = const []);
                  _goTo(_pathController.text);
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: '刷新',
                onPressed: _refresh,
              ),
              TextButton.icon(
                icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                label: const Text('新建目录'),
                onPressed: _mkdir,
              ),
              TextButton.icon(
                icon: const Icon(Icons.upload_file, size: 16),
                label: const Text('上传'),
                onPressed: _upload,
              ),
            ],
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
                                      ? Icons.folder_outlined
                                      : Icons.insert_drive_file_outlined,
                                  color: isDir
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                                title: Text(entry.filename),
                                subtitle: isDir
                                    ? Text(
                                        '${_modeString(modeVal)} '
                                        '${_formatTime(entry.attr.modifyTime)}',
                                        style: textTheme.bodySmall?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      )
                                    : Text(
                                        '${_formatSize(entry.attr.size)} · '
                                        '${_modeString(modeVal)} · '
                                        '${_formatTime(entry.attr.modifyTime)}',
                                        style: textTheme.bodySmall?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                onTap: isDir
                                    ? () => _enterDir(entry)
                                    : () => _showDetails(entry),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!isDir)
                                      IconButton(
                                        icon: const Icon(Icons.download,
                                            size: 18),
                                        tooltip: '下载',
                                        onPressed: () => _download(entry),
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.info_outline,
                                          size: 18),
                                      tooltip: '详情',
                                      onPressed: () => _showDetails(entry),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
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
        AppflowySpacing.m,
        0,
        AppflowySpacing.m,
        AppflowySpacing.xs,
      ),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppflowyRadius.m),
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
                      ? Icons.folder_outlined
                      : Icons.insert_drive_file_outlined,
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
