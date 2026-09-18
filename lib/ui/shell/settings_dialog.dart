import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:toolbox/common/app_log.dart';
import 'package:toolbox/common/backup_service.dart';
import 'package:toolbox/common/byte_format.dart';
import 'package:toolbox/ui/theme/app_layout.dart';
import 'package:toolbox/ui/theme/theme_controller.dart';
import 'package:toolbox/ui/widgets/app_dialog.dart';
import 'package:toolbox/ui/widgets/app_form_row.dart';
import 'package:toolbox/ui/widgets/app_toast.dart';
import 'package:toolbox/ui/widgets/app_tooltip.dart';
import 'package:toolbox/ui/window/app_tray.dart';

/// 设置弹窗。
///
/// 刻意保持极简：
/// - **只有右上角一个 ×**，没有底部操作区；
/// - 每项都是「左边名称 + 右边控件」，详细说明挂在名称的悬停提示里
///   （由 [AppFormRow] 提供），界面上不再出现成段文字；
/// - 不展示数据目录与版本号，也不做「检查更新」——更新由安装包负责，
///   安装新版本时会自动覆盖升级，程序内部再查一次版本只会多一个可能出错的入口。
Future<void> showSettingsDialog(BuildContext context) {
  return showAppDialog<void>(
    context: context,
    title: '设置',
    width: dialogWidthMedium,
    content: const _SettingsContent(),
  );
}

class _SettingsContent extends ConsumerStatefulWidget {
  const _SettingsContent();

  @override
  ConsumerState<_SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends ConsumerState<_SettingsContent> {
  /// 关闭窗口时的行为。
  CloseBehavior _behavior = AppTray.closeBehavior();

  /// 备份操作进行中（导出/导入都是「弹系统对话框 + 读写磁盘」的长操作，
  /// 期间把按钮置灰，避免重复触发两次落盘）。
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeControllerProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppFormRow(
          label: '关闭窗口时',
          description:
              '点窗口右上角 × 时的行为。选「每次询问」会在关闭时弹框让你挑，'
              '并可勾选「记住我的选择」把结果固定下来。',
          child: FSelect<CloseBehavior>(
            control: FSelectControl<CloseBehavior>.lifted(
              value: _behavior,
              onChange: (value) {
                if (value == null) return;
                setState(() => _behavior = value);
                unawaited(AppTray.setCloseBehavior(value));
              },
            ),
            items: {for (final b in CloseBehavior.values) b.label: b},
          ),
        ),
        const SizedBox(height: AppLayout.gapLg),
        AppFormRow(
          label: '外观',
          description: '「跟随系统」会随 Windows 的浅色 / 深色设置自动切换。',
          child: FSelect<ThemeMode>(
            control: FSelectControl<ThemeMode>.lifted(
              value: themeMode,
              onChange: (value) {
                if (value == null) return;
                ref.read(themeControllerProvider.notifier).setMode(value);
              },
            ),
            items: const {
              '跟随系统': ThemeMode.system,
              '浅色': ThemeMode.light,
              '深色': ThemeMode.dark,
            },
          ),
        ),
        const SizedBox(height: AppLayout.gapXl),
        const FDivider(),
        const SizedBox(height: AppLayout.gapLg),
        const _SectionTitle(
          '数据备份',
          tip: '备份内容就是数据目录本身：SSH 连接、仓库分组、传输任务、界面设置与日志，'
              '换台电脑时整份带走即可。',
        ),
        const SizedBox(height: AppLayout.gapSm),
        AppFormRow(
          label: '导出备份',
          labelWidth: _backupLabelWidth,
          description:
              '把全部数据打包成一个 zip 文件（文件名带日期时间）。'
              '文件里同时写了一份清单，导入时会先校验它，避免选错文件。',
          child: _ActionButton(
            label: '导出到 zip…',
            enabled: !_busy,
            onPress: _exportBackup,
          ),
        ),
        const SizedBox(height: AppLayout.gapMd),
        AppFormRow(
          label: '导入备份',
          labelWidth: _backupLabelWidth,
          description:
              '用备份里的内容覆盖当前数据（不是合并）。覆盖前会自动把当前数据'
              '留一份副本到数据目录的 $BackupService.snapshotDirName 下，'
              '导入完成后应用需要重启才会生效。',
          child: _ActionButton(
            label: '从 zip 恢复…',
            enabled: !_busy,
            onPress: _importBackup,
          ),
        ),
        const SizedBox(height: AppLayout.gapMd),
        AppFormRow(
          label: '格式化数据',
          labelWidth: _backupLabelWidth,
          description:
              '清空全部数据（连接、设置、仓库分组、传输任务、日志），回到刚装好的状态。'
              '格式化前会强制先导出一份备份放到数据目录旁边，'
              '备份没写成功就不会删任何数据；格式化后应用需要重启。',
          child: _ActionButton(
            label: '清空全部数据…',
            enabled: !_busy,
            destructive: true,
            onPress: _formatData,
          ),
        ),
        const SizedBox(height: AppLayout.gapXl),
        const FDivider(),
        const SizedBox(height: AppLayout.gapLg),
        const _SectionTitle(
          '快捷键',
          tip: '终端获得焦点时，这些组合键会让给终端（例如 Ctrl+W 在 bash 里是删除前一个词）。',
        ),
        const SizedBox(height: AppLayout.gapSm),
        // 左缩进到控件列：快捷键列表与上方下拉框左缘对齐，整块看起来是一列。
        Padding(
          padding: const EdgeInsets.only(
            left: AppLayout.formLabelWidth + AppLayout.gapMd,
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ShortcutRow('Ctrl + N', '新建 SSH 连接'),
              _ShortcutRow('Ctrl + W', '关闭当前会话'),
              _ShortcutRow('Ctrl + Tab', '下一个会话'),
              _ShortcutRow('Ctrl + Shift + Tab', '上一个会话'),
              _ShortcutRow('Esc', '关闭弹窗'),
            ],
          ),
        ),
      ],
    );
  }

  /// 「导出备份 / 导入备份」四个字比默认名称列宽（其他行都是 2~3 字），
  /// 单独放宽一点，否则名称会被省略号截掉。
  static const double _backupLabelWidth = AppLayout.formLabelWidth + 16;

  // ---------------- 导出 ----------------

  Future<void> _exportBackup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = BackupService.buildZip();
      // 保存对话框由系统提供：用户在对话框里选路径，插件负责把字节写进去；
      // 返回 null 表示用户取消。
      final target = await FilePicker.saveFile(
        dialogTitle: '导出备份',
        fileName: BackupService.defaultFileName(),
        bytes: bytes,
      );
      if (target == null) return;
      if (!mounted) return;
      showAppToast(
        context,
        '已导出备份：${_fileNameFromUri(target)}（${formatBytes(bytes.length)}）',
      );
    } catch (e) {
      AppLog.e('settings', '导出备份失败：$e');
      if (mounted) showAppToast(context, '导出备份失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------- 导入 ----------------

  Future<void> _importBackup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: '选择备份文件',
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (picked.isEmpty) return;
      final path = picked.first.path;
      if (path == null) return;
      if (!mounted) return;

      final confirmed = await _confirmImport(path);
      if (!confirmed) return;
      if (!mounted) return;

      final result = BackupService.importFrom(path);
      if (!mounted) return;
      if (!result.success) {
        showAppToast(context, result.message, error: true);
        return;
      }
      await _afterDataReplaced(
        title: '导入完成',
        detail: '${result.message}，已用备份覆盖当前数据。',
      );
    } catch (e) {
      AppLog.e('settings', '导入备份失败：$e');
      if (mounted) showAppToast(context, '导入备份失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 覆盖前的确认：这里是**破坏性操作**，必须先把后果说清楚。
  Future<bool> _confirmImport(String path) async {
    final theme = context.theme;
    final ok = await showAppDialog<bool>(
      context: context,
      title: '用备份覆盖当前数据？',
      width: dialogWidthSmall,
      content: Text(
        '备份文件：${_fileNameFromPath(path)}\n\n'
        '当前的连接、设置、仓库等数据会被这份备份替换掉。'
        '覆盖前会自动把当前数据留一份副本，万一选错了还能取回。',
        style: theme.typography.body.sm.copyWith(
          height: 1.6,
          color: theme.colors.mutedForeground,
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
          child: const Text('覆盖并导入'),
        ),
      ],
    );
    return ok == true;
  }

  // ---------------- 格式化 ----------------

  Future<void> _formatData() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // 备份落点先算出来给用户看：让他知道万一后悔了去哪儿找。
      final backupPath = BackupService.formatBackupPath();
      if (!mounted) return;
      final confirmed = await _confirmFormat(backupPath);
      if (!confirmed) return;
      if (!mounted) return;

      final result = BackupService.formatData();
      if (!mounted) return;
      if (!result.success) {
        showAppToast(context, result.message, error: true);
        return;
      }
      await _afterDataReplaced(
        title: '已格式化',
        detail:
            '${result.message}，备份保存到：\n${result.backupPath}\n\n'
            '需要恢复时，用上面的「从 zip 恢复」选中这个文件即可。',
      );
    } catch (e) {
      AppLog.e('settings', '格式化数据失败：$e');
      if (mounted) showAppToast(context, '格式化失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 格式化前的确认：先把「会删什么、备份放哪」说清楚。
  Future<bool> _confirmFormat(String backupPath) async {
    final theme = context.theme;
    final ok = await showAppDialog<bool>(
      context: context,
      title: '清空全部数据？',
      width: dialogWidthSmall,
      content: Text(
        '会删除：SSH 连接、界面设置、仓库分组、传输任务、运行日志。\n\n'
        '删除前会强制先备份一份到：\n$backupPath\n\n'
        '备份没写成功就不会删除任何数据。',
        style: theme.typography.body.sm.copyWith(
          height: 1.6,
          color: theme.colors.mutedForeground,
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
          variant: FButtonVariant.destructive,
          onPress: () => Navigator.pop(context, true),
          child: const Text('清空并格式化'),
        ),
      ],
    );
    return ok == true;
  }

  // ---------------- 数据被整体替换后的收尾 ----------------

  /// 导入 / 格式化完成后的收尾。
  ///
  /// 这两件事都会把内存里的旧数据变成「不该再落盘」的状态（[JsonStoreIo.frozen]），
  /// 所以必须引导用户重启，否则界面显示的还是旧数据。
  Future<void> _afterDataReplaced({
    required String title,
    required String detail,
  }) async {
    final theme = context.theme;
    final restart = await showAppDialog<bool>(
      context: context,
      title: title,
      width: dialogWidthSmall,
      content: Text(
        '$detail\n\n'
        '为避免运行中的界面把刚变更的数据覆盖回去，这一步之后程序不会再写入任何数据。',
        style: theme.typography.body.sm.copyWith(
          height: 1.6,
          color: theme.colors.mutedForeground,
        ),
      ),
      actions: [
        FButton(
          mainAxisSize: MainAxisSize.min,
          variant: FButtonVariant.primary,
          onPress: () => Navigator.pop(context, true),
          child: const Text('立即重启'),
        ),
      ],
    );

    if (restart != true) {
      // 用户选择稍后自己重启（或直接关掉了弹窗）：写入已被拦住，数据是安全的，
      // 但必须明确提醒——不重启的话看到的还是旧数据。
      if (mounted) showAppToast(context, '$title，请重启应用后生效');
      return;
    }

    try {
      await AppTray.relaunch();
    } catch (e) {
      AppLog.e('settings', '重启失败：$e');
      if (mounted) {
        showAppToast(context, '重启失败，请手动重新打开应用', error: true);
      }
    }
  }

  /// 只取出文件名（提示里显示完整路径会把提示条撑得很长）。
  static String _fileNameFromUri(Uri uri) => _fileNameFromPath(uri.toFilePath());

  static String _fileNameFromPath(String path) {
    final index = path.lastIndexOf(RegExp(r'[\\/]'));
    return index < 0 ? path : path.substring(index + 1);
  }

}

/// 设置项右侧的动作按钮（统一样式与对齐）。
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.enabled,
    required this.onPress,
    this.destructive = false,
  });

  final String label;
  final bool enabled;
  final Future<void> Function() onPress;

  /// 破坏性操作（格式化）用危险色，别让它看起来和「导出」一样无害。
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FButton(
          mainAxisSize: MainAxisSize.min,
          variant: destructive
              ? FButtonVariant.destructive
              : FButtonVariant.outline,
          size: FButtonSizeVariant.sm,
          onPress: enabled ? () => unawaited(onPress()) : null,
          child: Text(label),
        ),
      ],
    );
  }
}

/// 小节标题，可选一个悬停说明（长文案不再直接铺在界面上）。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.tip});

  final String text;
  final String? tip;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      text,
      style: context.theme.typography.body.sm.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
    if (tip == null) return title;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        title,
        const SizedBox(width: 6),
        AppTooltip(
          message: tip!,
          child: Icon(
            FLucideIcons.info,
            size: 13,
            color: context.theme.colors.mutedForeground,
          ),
        ),
      ],
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow(this.keys, this.action);

  final String keys;
  final String action;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 138,
            child: Text(
              keys,
              style: theme.typography.body.xs.copyWith(
                color: theme.colors.mutedForeground,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            child: Text(action, style: theme.typography.body.xs),
          ),
        ],
      ),
    );
  }
}
