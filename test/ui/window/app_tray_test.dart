import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/common/settings_store.dart';
import 'package:toolbox/ui/window/app_tray.dart';

/// 关闭行为的读写（纯数据层，不触碰托盘插件）。
///
/// 覆盖用户反馈的「设置里那个开关点了不生效」：改为三态 `app.closeBehavior`
/// 之后，写入必须能被读回，并且**旧版本的布尔键不再影响行为**。
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('app_tray_test');
    // 用临时目录替换设置存储，避免污染真实数据目录
    AppTray.storeFactory = () => SettingsStore(dir: dir.path);
  });

  tearDown(() {
    AppTray.storeFactory = SettingsStore.new;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  SettingsStore store() => SettingsStore(dir: dir.path);

  test('默认「每次询问」', () {
    expect(AppTray.closeBehavior(), CloseBehavior.ask);
  });

  test('写入后可读回（三个取值都能往返）', () async {
    for (final behavior in CloseBehavior.values) {
      await AppTray.setCloseBehavior(behavior);
      expect(AppTray.closeBehavior(), behavior);
    }
  });

  test('旧版本的布尔开关 app.closeToTray 不再影响行为，且会被清理', () async {
    store().write({'app.closeToTray': false});
    // 旧键被忽略：仍然是默认的「每次询问」
    expect(AppTray.closeBehavior(), CloseBehavior.ask);

    await AppTray.setCloseBehavior(CloseBehavior.tray);
    expect(store().read().containsKey('app.closeToTray'), isFalse);
    expect(AppTray.closeBehavior(), CloseBehavior.tray);
  });

  test('未知取值按「每次询问」兜底（手改坏文件不至于让程序关不掉）', () {
    store().write({AppTray.closeBehaviorKey: 'something-else'});
    expect(AppTray.closeBehavior(), CloseBehavior.ask);
  });

  test('每个取值都有可读的标签与说明', () {
    for (final behavior in CloseBehavior.values) {
      expect(behavior.label, isNotEmpty);
      expect(behavior.description, isNotEmpty);
    }
  });
}
