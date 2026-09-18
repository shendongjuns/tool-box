import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:toolbox/common/app_log.dart';
import 'package:toolbox/common/settings_store.dart';
import 'package:toolbox/common/single_instance.dart';
import 'package:toolbox/ui/widgets/app_dialog.dart';
import 'package:toolbox/ui/window/app_navigator.dart';
import 'package:toolbox/ui/window/app_window.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// 点窗口关闭按钮（右上角 X）时的行为。
enum CloseBehavior {
  ask('每次询问', '点关闭按钮时弹框让你选择：最小化到托盘，还是彻底退出'),
  tray('最小化到托盘', '点关闭按钮后直接隐藏到托盘，程序继续在后台运行'),
  quit('彻底退出', '点关闭按钮后直接结束程序');

  const CloseBehavior(this.label, this.description);

  /// 下拉里显示的文案。
  final String label;

  /// 悬停提示里的详细说明。
  final String description;

  static CloseBehavior fromName(Object? name) => switch (name) {
    'tray' => CloseBehavior.tray,
    'quit' => CloseBehavior.quit,
    _ => CloseBehavior.ask,
  };
}

/// 关闭确认框的选择结果。
class CloseChoice {
  const CloseChoice(this.behavior, {this.remember = false});

  final CloseBehavior behavior;

  /// 用户是否勾选了「记住我的选择」。
  final bool remember;
}

/// 系统托盘常驻。
///
/// 行为：
/// - 启动时注册托盘图标与菜单（显示主窗口 / 退出）；
/// - 窗口的关闭按钮不再直接结束进程，而是按 [CloseBehavior] 处理：
///   询问 / 最小化到托盘 / 彻底退出（默认**询问**）；
/// - 左键点托盘图标或菜单「显示主窗口」恢复窗口；菜单「退出」才真正结束进程。
///
/// **关窗拦截机制**：`windowManager.setPreventClose(true)` 让 X 按钮不再直接关闭，
/// 改为回调 [onWindowClose]，由 [handleWindowClose] 决定后续动作。
/// 若托盘初始化失败则**不拦截**（`_ready == false`），避免出现
/// 「点了 X 关不掉程序」这种更糟的结果。
class AppTray with TrayListener, WindowListener {
  AppTray._();

  /// 关闭行为在 `settings.json` 里的键，取值 `ask` / `tray` / `quit`。
  static const String closeBehaviorKey = 'app.closeBehavior';

  /// 旧版本用的是布尔开关（`app.closeToTray`）；不再读取，写盘时清理掉。
  static const String _legacyCloseToTrayKey = 'app.closeToTray';

  /// 托盘图标资源键；tray_manager 会自动补上 `<exe>/data/flutter_assets/` 前缀。
  static const String _iconAsset = 'assets/tray_icon.ico';

  /// 托盘图标的悬停文案。
  static const String _tooltip = 'ToolBox（单击显示窗口）';

  static final AppTray _instance = AppTray._();

  /// 是否正在真正退出（退出流程中不再拦截关闭）。
  static bool _quitting = false;

  static bool _ready = false;

  /// 是否正在显示关闭确认框（防止连点 × 弹出多个）。
  static bool _asking = false;

  /// 托盘是否可用。false 时关闭按钮直接退出程序。
  static bool get isReady => _ready;

  /// 设置存储工厂；测试可替换成临时目录。
  static SettingsStore Function() storeFactory = SettingsStore.new;

  /// 读取关闭行为（默认「每次询问」）。
  static CloseBehavior closeBehavior() =>
      CloseBehavior.fromName(storeFactory().read()[closeBehaviorKey]);

  /// 写入关闭行为。
  static Future<void> setCloseBehavior(CloseBehavior behavior) async {
    final store = storeFactory();
    store.write(
      Map<String, dynamic>.from(store.read())
        ..remove(_legacyCloseToTrayKey)
        ..[closeBehaviorKey] = behavior.name,
    );
  }

  /// 在窗口就绪后初始化托盘。失败不抛出——退化为「关闭即退出」。
  static Future<void> init() async {
    try {
      await trayManager.setIcon(_iconAsset);
      await trayManager.setToolTip(_tooltip);
      await _refreshMenu();
      trayManager.addListener(_instance);
      windowManager.addListener(_instance);
      // 拦截关闭：X 按钮交给 handleWindowClose 处理。
      await windowManager.setPreventClose(true);
      _ready = true;
      AppLog.i('tray', '托盘已就绪（关闭窗口时：${closeBehavior().label}）');
    } catch (e) {
      _ready = false;
      AppLog.w('tray', '托盘初始化失败，关闭按钮将直接退出程序：$e');
    }
  }

  static Future<void> _refreshMenu() async {
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(
            key: 'show',
            label: '显示主窗口',
            onClick: (_) => unawaited(showWindow()),
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'quit',
            label: '退出 ToolBox',
            onClick: (_) => unawaited(quit()),
          ),
        ],
      ),
    );
  }

  /// 显示并聚焦主窗口（同时恢复到任务栏）。
  static Future<void> showWindow() async {
    try {
      await windowManager.setSkipTaskbar(false);
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      AppLog.w('tray', '显示主窗口失败：$e');
    }
  }

  /// 隐藏到托盘：从任务栏移除，只保留托盘图标。
  static Future<void> hideToTray() async {
    try {
      await windowManager.setSkipTaskbar(true);
      await windowManager.hide();
      AppLog.i('tray', '已最小化到托盘');
    } catch (e) {
      AppLog.w('tray', '隐藏到托盘失败：$e');
    }
  }

  /// 真正退出应用。
  ///
  /// **顺序是有讲究的**，为的是「点完立刻消失」这个体感：
  ///
  /// 1. **先把窗口藏起来**。`windowManager.destroy()` 内部只是
  ///    `PostQuitMessage`（见 window_manager 的 Windows 实现），它**不销毁窗口**；
  ///    窗口要等 `wWinMain` 返回、Flutter 引擎把渲染线程拆完才消失，
  ///    这段时间窗口停在最后一帧、看起来就是「点了退出却卡住一会儿」。
  ///    隐藏是同步生效的，用户按下按钮的瞬间界面就没了。
  /// 2. 再落盘窗口尺寸（隐藏后仍可读），避免最后一次缩放丢失。
  /// 3. 销毁托盘图标：进程退出时 Windows 不会自动清图标，会留下「幽灵图标」
  ///    （要鼠标划过才消失）。
  /// 4. 最后挂一个**兜底计时器**：万一引擎拆除卡住，到点直接结束进程，
  ///    绝不能出现「点了退出关不掉」。
  static Future<void> quit() async {
    if (_quitting) return; // 重复调用（连点 / 托盘菜单）直接忽略
    _quitting = true;
    _shutdown();
  }

  /// 退出流程本体（不重复判断 [_quitting]，供 [quit] 与 [relaunch] 复用）。
  static Future<void> _shutdown() async {
    AppLog.i('tray', '开始退出');
    await _hideNow();
    await WindowGeometry.saveNow();
    try {
      await trayManager.destroy();
    } catch (e) {
      AppLog.w('tray', '销毁托盘图标失败：$e');
    }
    try {
      await windowManager.setPreventClose(false);
    } catch (_) {
      // 忽略：下面的 destroy 会直接结束窗口。
    }

    // 兜底：引擎拆除正常只需 100~200ms；超过 [_exitFallback] 仍未退出就强杀，
    // 避免用户面对一个「界面没了但进程还在」的僵尸。
    Timer(_exitFallback, () => exit(0));

    try {
      await windowManager.destroy();
    } catch (e) {
      AppLog.w('tray', '销毁窗口失败，改为强制结束进程：$e');
      exit(0);
    }
  }

  /// 兜底强杀等待时长。
  static const Duration _exitFallback = Duration(milliseconds: 800);

  /// 隐藏主窗口（同步生效），失败不影响后续退出。
  static Future<void> _hideNow() async {
    try {
      await windowManager.hide();
    } catch (e) {
      AppLog.w('tray', '隐藏窗口失败：$e');
    }
  }

  /// 重启应用：拉起新进程后立即退出自己。
  ///
  /// 用于「导入备份」这类必须重启才生效的操作。
  /// 注意先 [SingleInstance.release]：不释放的话新进程会弹「已有一个实例在运行」。
  static Future<void> relaunch() async {
    if (_quitting) return;
    _quitting = true;
    try {
      final exe = Platform.resolvedExecutable;
      await Process.start(
        exe,
        const [],
        workingDirectory: File(exe).parent.path,
        mode: ProcessStartMode.detached,
      );
      AppLog.i('tray', '已拉起新进程，准备退出当前进程');
    } catch (e) {
      // 拉不起来就放弃重启，让界面继续跑（总比退出后什么都没有好）。
      _quitting = false;
      AppLog.e('tray', '重启失败：$e');
      rethrow;
    }
    SingleInstance.release();
    await _hideNow();
    try {
      await trayManager.destroy();
    } catch (_) {
      // 新进程会重建托盘图标，这里失败不影响结果。
    }
    Timer(_exitFallback, () => exit(0));
    try {
      await windowManager.destroy();
    } catch (_) {
      exit(0);
    }
  }

  /// 处理窗口关闭请求（X 按钮 / Alt+F4）。
  static Future<void> handleWindowClose() async {
    if (_quitting) return; // 已经在退出流程里，放行

    switch (closeBehavior()) {
      case CloseBehavior.tray:
        await _saveGeometryAndHide();
      case CloseBehavior.quit:
        await quit();
      case CloseBehavior.ask:
        if (_asking) return; // 已经在问了，忽略重复的关窗请求
        _asking = true;
        try {
          await _askThenAct();
        } finally {
          _asking = false;
        }
    }
  }

  /// 询问用户，并按选择执行（未勾选「记住」则只影响本次）。
  static Future<void> _askThenAct() async {
    final context = AppNavigator.context;
    // 拿不到 UI（界面还没搭好）或托盘不可用：直接退出，这是最不意外的结果。
    if (context == null || !_ready) {
      await quit();
      return;
    }

    final choice = await showCloseDialog(context);
    if (choice == null) return; // 用户取消（含点右上角 X）：保持运行
    if (choice.remember) await setCloseBehavior(choice.behavior);

    if (choice.behavior == CloseBehavior.tray) {
      await _saveGeometryAndHide();
    } else {
      await quit();
    }
  }

  /// 隐藏前先把窗口尺寸落盘（防抖窗口内直接关窗会丢最后一次缩放）。
  static Future<void> _saveGeometryAndHide() async {
    await WindowGeometry.saveNow();
    await hideToTray();
  }

  /// 关闭确认框：最小化到托盘 / 彻底退出，可勾选「记住」。
  static Future<CloseChoice?> showCloseDialog(BuildContext context) {
    final remember = ValueNotifier<bool>(false);
    return showAppDialog<CloseChoice>(
      context: context,
      title: '关闭 ToolBox',
      width: dialogWidthSmall,
      content: ValueListenableBuilder<bool>(
        valueListenable: remember,
        builder: (context, value, _) => FCheckbox(
          value: value,
          onChange: (v) => remember.value = v,
          label: const Text('记住我的选择，下次不再询问'),
        ),
      ),
      actions: [
        FButton(
          mainAxisSize: MainAxisSize.min,
          variant: FButtonVariant.outline,
          onPress: () => Navigator.pop(
            context,
            CloseChoice(CloseBehavior.quit, remember: remember.value),
          ),
          child: const Text('彻底退出'),
        ),
        FButton(
          mainAxisSize: MainAxisSize.min,
          variant: FButtonVariant.primary,
          onPress: () => Navigator.pop(
            context,
            CloseChoice(CloseBehavior.tray, remember: remember.value),
          ),
          child: const Text('最小化到托盘'),
        ),
      ],
    );
  }

  // ---------------- TrayListener ----------------

  @override
  void onTrayIconMouseDown() => unawaited(showWindow());

  @override
  void onTrayIconRightMouseDown() => unawaited(trayManager.popUpContextMenu());

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(showWindow());
      case 'quit':
        unawaited(quit());
    }
  }

  // ---------------- WindowListener ----------------

  @override
  void onWindowClose() => unawaited(handleWindowClose());
}
