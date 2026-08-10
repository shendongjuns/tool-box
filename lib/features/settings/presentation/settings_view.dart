import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/ui/theme/appflowy_colors.dart';
import 'settings_controller.dart';

/// 设置页（常规）：存储目录配置。顶部导航通过下拉菜单进入本页。
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  /// 更改存储目录流程：选择目录 → 确认对话框（提醒重启，取消则不变更）
  /// → 确认后转移数据并重启。
  static Future<void> _changeDataDir(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(settingsControllerProvider.notifier);
    final dir = await controller.pickDirectory();
    if (dir == null) return; // 取消选择：不变更
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('更改存储目录'),
        content: const Text('更改后应用将重启，数据将全部转移到新目录。\n确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true) return; // 不同意重启：不变更

    final ok = await controller.changeDataDir(dir);
    if (!ok && context.mounted) {
      // 转移失败：提示用户（旧目录与旧配置已保留）
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目录转移失败，已保留原目录与配置')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final palette = Theme.of(context).brightness == Brightness.dark
        ? AppflowyColors.dark
        : AppflowyColors.light;
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppflowySpacing.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 配置项标题 + 解释 tooltip（点击查看说明）
              Row(
                children: [
                  Text('存储目录', style: textTheme.titleMedium),
                  const SizedBox(width: AppflowySpacing.s),
                  Tooltip(
                    message: '所有应用内容（配置/数据）存放的目录。\n'
                        '更改目录后数据将转移到新位置并重启应用。',
                    triggerMode: TooltipTriggerMode.tap,
                    waitDuration: const Duration(milliseconds: 100),
                    child: Icon(
                      Icons.info_outline,
                      size: 16,
                      color: palette.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppflowySpacing.m),
              // 当前目录 + 更改按钮（同一行，按钮在右侧）
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(AppflowySpacing.m),
                      decoration: BoxDecoration(
                        border: Border.all(color: palette.border),
                        borderRadius: BorderRadius.circular(AppflowyRadius.m),
                      ),
                      child: Text(
                        settings.dataDir,
                        style: textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppflowySpacing.m),
                  OutlinedButton.icon(
                    onPressed: () => _changeDataDir(context, ref),
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('更改存储目录'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
