import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 页面导航状态：打开的页面会话与当前激活页。
///
/// [openIds] 为页面打开顺序（单实例去重）；[activeId] 为当前激活页，
/// `null` 表示「当前没有打开任何页面」（内容区显示空状态提示）。
/// 页面以工具 id 为 key（注册表每次可能新建 Tool 实例，不能用实例引用做比较）。
class PageNavState {
  const PageNavState({
    required this.openIds,
    required this.activeId,
  });

  final List<String> openIds;
  final String? activeId;

  PageNavState copyWith({List<String>? openIds, String? activeId}) =>
      PageNavState(openIds: openIds ?? this.openIds, activeId: activeId);
}

final pageNavProvider = NotifierProvider<PageNavController, PageNavState>(
  PageNavController.new,
);

/// 页面会话导航：打开 / 切换 / 关闭。
///
/// 切换只改变激活页，**已打开页面保活**（widget 树不销毁）；
/// 仅 [close] 关闭页面会话，页面状态随之释放。
class PageNavController extends Notifier<PageNavState> {
  @override
  PageNavState build() => const PageNavState(openIds: [], activeId: null);

  /// 打开页面（未打开则加入并按打开顺序激活）。
  void open(String toolId) {
    final openIds = [...state.openIds];
    if (!openIds.contains(toolId)) openIds.add(toolId);
    state = PageNavState(openIds: openIds, activeId: toolId);
  }

  /// 切换到已打开的页面。
  void activate(String toolId) {
    if (!state.openIds.contains(toolId)) return;
    state = state.copyWith(activeId: toolId);
  }

  /// 关闭页面：从打开列表移除；关闭的是当前页时切到相邻页
  /// （优先前一页），无剩余页面则回到空状态。
  void close(String toolId) {
    final openIds = state.openIds.where((id) => id != toolId).toList();
    if (state.activeId != toolId) {
      state = PageNavState(openIds: openIds, activeId: state.activeId);
      return;
    }
    if (openIds.isEmpty) {
      state = const PageNavState(openIds: [], activeId: null);
      return;
    }
    final closedIndex = state.openIds.indexOf(toolId);
    final nextIndex = closedIndex > 0 ? closedIndex - 1 : 0;
    state = PageNavState(openIds: openIds, activeId: openIds[nextIndex]);
  }
}
