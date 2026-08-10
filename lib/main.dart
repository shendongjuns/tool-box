import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:toolbox/ui/shell/shell_view.dart';
import 'package:toolbox/ui/theme/appflowy_theme.dart';
import 'package:toolbox/ui/theme/forui_theme.dart';
import 'package:toolbox/ui/theme/theme_controller.dart';
import 'package:toolbox/ui/window/app_window.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initAppWindow();
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
          child: const ShellView(),
        ),
      );
    });
  }
}
