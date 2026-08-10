import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:toolbox/features/settings/data/app_settings.dart';
import 'package:toolbox/features/settings/presentation/settings_controller.dart';
import 'package:toolbox/ui/shell/shell_view.dart';
import 'package:toolbox/ui/theme/appflowy_colors.dart';
import 'package:toolbox/ui/theme/appflowy_theme.dart';
import 'package:toolbox/ui/theme/forui_theme.dart';
import 'package:toolbox/ui/theme/theme_controller.dart';
import 'package:toolbox/ui/window/app_window.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initAppWindow();
  // 加载配置（数据目录），保留初始值供 runApp 后使用。
  final container = ProviderContainer();
  await container.read(settingsControllerProvider.notifier).init();
  gInitialSettings = container.read(settingsControllerProvider);
  container.dispose();
  runApp(const ProviderScope(child: ToolBoxApp()));
}

class ToolBoxApp extends StatelessWidget {
  const ToolBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final themeMode = ref.watch(themeControllerProvider);
      final brightness = switch (themeMode) {
        ThemeMode.dark => Brightness.dark,
        ThemeMode.light => Brightness.light,
        ThemeMode.system => MediaQuery.platformBrightnessOf(context),
      };
      return MaterialApp(
        title: '工具箱',
        theme: AppflowyTheme.light(),
        darkTheme: AppflowyTheme.dark(),
        themeMode: themeMode,
        debugShowCheckedModeBanner: false,
        home: FTheme(
          data: buildForuiTheme(brightness),
          child: const StartupBootstrap(child: ShellView()),
        ),
      );
    });
  }
}

/// 首次启动引导：数据目录不存在时弹出「选择存储目录」对话框。
class StartupBootstrap extends ConsumerStatefulWidget {
  const StartupBootstrap({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<StartupBootstrap> createState() => _StartupBootstrapState();
}

class _StartupBootstrapState extends ConsumerState<StartupBootstrap> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFirstRun());
  }

  Future<void> _checkFirstRun() async {
    if (_checked) return;
    _checked = true;
    final controller = ref.read(settingsControllerProvider.notifier);
    if (!controller.dataDirExists) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _FirstRunDialog(
          defaultDir: AppSettings.defaultDataDir(),
          onConfirm: (dir) => controller.confirmDataDir(dir),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 首次启动对话框：提供默认目录，可选择其他目录，确认后创建。
class _FirstRunDialog extends StatefulWidget {
  const _FirstRunDialog({required this.defaultDir, required this.onConfirm});

  final String defaultDir;
  final Future<void> Function(String dir) onConfirm;

  @override
  State<_FirstRunDialog> createState() => _FirstRunDialogState();
}

class _FirstRunDialogState extends State<_FirstRunDialog> {
  late String _dir;

  @override
  void initState() {
    super.initState();
    _dir = widget.defaultDir;
  }

  Future<void> _pick() async {
    final dir = await getDirectoryPath();
    if (dir != null) setState(() => _dir = dir);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      title: const Text('欢迎使用工具箱'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('请选择数据存储目录（应用内容存放处）：', style: textTheme.bodyMedium),
          const SizedBox(height: AppflowySpacing.l),
          Container(
            width: 420,
            padding: const EdgeInsets.all(AppflowySpacing.m),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(AppflowyRadius.m),
            ),
            child: Text(
              _dir,
              style: textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: AppflowySpacing.m),
          OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('选择其他目录'),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () async {
            await widget.onConfirm(_dir);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
