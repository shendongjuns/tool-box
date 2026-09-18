import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/ui/shell/navigation_controller.dart';

void main() {
  test('初始没有打开任何页面（activeId 为空）', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final nav = container.read(pageNavProvider);
    expect(nav.openIds, isEmpty);
    expect(nav.activeId, isNull);
  });

  test('open 打开并激活，重复 open 不重复加入', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(pageNavProvider.notifier);

    notifier.open('a');
    notifier.open('b');
    notifier.open('a');

    final nav = container.read(pageNavProvider);
    expect(nav.openIds, ['a', 'b']);
    expect(nav.activeId, 'a');
  });

  test('activate 切换到已打开页面，未打开页面无效', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(pageNavProvider.notifier);

    notifier.open('a');
    notifier.open('b');
    notifier.activate('a');
    expect(container.read(pageNavProvider).activeId, 'a');

    notifier.activate('x');
    expect(container.read(pageNavProvider).activeId, 'a');
  });

  test('close 关闭非当前页不影响激活页', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(pageNavProvider.notifier);

    notifier.open('a');
    notifier.open('b');
    notifier.activate('a');
    notifier.close('b');

    final nav = container.read(pageNavProvider);
    expect(nav.openIds, ['a']);
    expect(nav.activeId, 'a');
  });

  test('close 关闭当前页回退相邻页（优先前一页）', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(pageNavProvider.notifier);

    // 关闭最后打开的页面 → 回退到前一页
    notifier.open('a');
    notifier.open('b');
    notifier.close('b');
    expect(container.read(pageNavProvider).activeId, 'a');

    // 关闭中间页面（非最后）→ 切到前一页
    notifier.open('b');
    notifier.open('c');
    notifier.activate('b');
    notifier.close('b');
    expect(container.read(pageNavProvider).activeId, 'a');
  });

  test('close 关闭最后一页后回到空状态', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(pageNavProvider.notifier);

    notifier.open('a');
    notifier.close('a');

    final nav = container.read(pageNavProvider);
    expect(nav.activeId, isNull);
    expect(nav.openIds, isEmpty);
  });
}
