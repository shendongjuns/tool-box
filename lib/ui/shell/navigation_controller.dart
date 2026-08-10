import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/registry/tool.dart';

final selectedToolProvider =
    NotifierProvider<NavigationController, Tool?>(NavigationController.new);

/// 导航状态：当前选中工具。
class NavigationController extends Notifier<Tool?> {
  @override
  Tool? build() => null; // 默认显示首页（null = 首页）

  void select(Tool tool) => state = tool;

  /// 返回首页（取消选中工具）。
  void goHome() => state = null;
}
