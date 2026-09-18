import 'package:flutter/widgets.dart';

/// 全局根 Navigator 的引用。
///
/// 有些交互发生在 widget 树之外（最典型的是**系统窗口关闭事件**：
/// window_manager 的回调里没有 `BuildContext`），但需要弹一个对话框询问用户。
/// 这里挂一个全局 key 给 `MaterialApp.navigatorKey`，让这些地方也能拿到
/// 可用的 `BuildContext`。
abstract final class AppNavigator {
  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

  /// 可安全用于 `showDialog` 的 context；界面尚未搭好时为 null。
  ///
  /// 取的是 **Overlay 的 context**（而不是 `key.currentContext`）：
  /// `key.currentContext` 就是 Navigator 自身的 context，而
  /// `Navigator.of(context)` 只会向上找祖先 Navigator —— 从 Navigator 自己的
  /// context 出发是找不到的（会直接抛「No Navigator widget found」）。
  /// Overlay 位于 Navigator 内部，从它出发能找到根 Navigator。
  static BuildContext? get context => key.currentState?.overlay?.context;
}
