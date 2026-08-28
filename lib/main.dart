import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/features/remote/sftp_temp_cleanup.dart';
import 'package:toolbox/ui/shell/shell_view.dart';
import 'package:toolbox/ui/theme/mochi_cat_theme.dart';
import 'package:toolbox/ui/theme/theme_controller.dart';
import 'package:toolbox/ui/window/app_window.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initAppWindow();
  cleanupOpenFileTempDirs();
  runApp(const ProviderScope(child: ToolBoxApp()));
}

class ToolBoxApp extends StatelessWidget {
  const ToolBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final themeMode = ref.watch(themeControllerProvider);
      return MaterialApp(
        title: '工具箱',
        theme: MochiCatTheme.light(),
        darkTheme: MochiCatTheme.dark(),
        themeMode: themeMode,
        debugShowCheckedModeBanner: false,
        home: const ShellView(),
      );
    });
  }
}
