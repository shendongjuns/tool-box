import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:toolbox/common/app_data.dart';
import 'package:toolbox/common/app_log.dart';
import 'package:toolbox/common/single_instance.dart';
import 'package:toolbox/features/remote/sftp_temp_cleanup.dart';
import 'package:toolbox/ui/shell/shell_view.dart';
import 'package:toolbox/ui/theme/forui_theme.dart';
import 'package:toolbox/ui/theme/theme_controller.dart';
import 'package:toolbox/ui/window/app_navigator.dart';
import 'package:toolbox/ui/window/app_window.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installGlobalErrorHandlers();

  // 顺序有讲究：先确定数据目录（可能回退到用户目录），再据此初始化日志，
  // 最后取证单实例——这三步都必须发生在读写任何数据文件之前。
  AppDataDir.init();
  AppLog.init();
  SingleInstance.acquire();
  _collectStartupNotices();

  await initAppWindow();
  cleanupOpenFileTempDirs();
  runApp(const ProviderScope(child: ToolBoxApp()));
}

/// 收集启动期需要用户知晓的问题，交给 ShellView 在首帧后统一提示。
void _collectStartupNotices() {
  final dataDirWarning = AppDataDir.warning;
  if (dataDirWarning != null) StartupNotice.add(dataDirWarning);
  if (!SingleInstance.isFirst) {
    StartupNotice.add(
      '已经有一个 ToolBox 在运行。\n'
      '同时开多个窗口时，后保存的那个会覆盖先保存的数据，建议只保留一个窗口。',
    );
  }
}

/// 全局错误兜底：未捕获的同步/异步异常至少留下日志。
///
/// 没有这层兜底时，异常会静默消失，用户只看到「点了没反应」，
/// 而我们拿不到任何可排查的线索。
void installGlobalErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLog.e('flutter', details.exceptionAsString(), details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.e('async', '$error', stack);
    return true; // 视为已处理，避免升级成崩溃
  };
}

class ToolBoxApp extends StatelessWidget {
  const ToolBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final mode = ref.watch(themeControllerProvider);
        return MaterialApp(
          title: 'ToolBox',
          debugShowCheckedModeBanner: false,
          // 全局 Navigator：系统窗口关闭事件发生在 widget 树之外，
          // 需要靠它拿到 context 才能弹「关闭到托盘还是退出」的确认框。
          navigatorKey: AppNavigator.key,
          // Material 层仅作基础设施宿主（Navigator / Overlay / 系统对话框归属），
          // 不定义任何自定义 Material 样式，直接用框架默认值。
          // 全部视觉一致性由 ForUI 主题负责。
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: mode,
          builder: (context, child) {
            // 「跟随系统」在 ForUI 下没有 themeMode 参数，需自行解析为亮度。
            // 放在 builder 内：既能拿到 MaterialApp 提供的 MediaQuery，
            // 又让 FTheme 位于 Navigator 之上，弹窗/浮层同样能取到主题。
            final brightness = switch (mode) {
              ThemeMode.system => MediaQuery.platformBrightnessOf(context),
              ThemeMode.light => Brightness.light,
              ThemeMode.dark => Brightness.dark,
            };
            // FToaster：全局轻提示（showAppToast）的宿主，必须位于 Navigator 之上。
            return FTheme(
              data: AppTheme.of(brightness),
              child: WindowBrightnessSync(
                brightness: brightness,
                child: FToaster(child: child ?? const SizedBox.shrink()),
              ),
            );
          },
          home: const ShellView(),
        );
      },
    );
  }
}
