import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/common/settings_store.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('settings_store_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('写入后读取可往返', () {
    final store = SettingsStore(dir: tempDir.path);
    store.write({'themeMode': 'dark', 'other': 1});

    final loaded = store.read();
    expect(loaded['themeMode'], 'dark');
    expect(loaded['other'], 1);
    expect(
      File('${tempDir.path}${Platform.pathSeparator}settings.json')
          .existsSync(),
      isTrue,
    );
  });

  test('文件不存在时返回空表', () {
    final store = SettingsStore(dir: tempDir.path);
    expect(store.read(), isEmpty);
  });

  test('文件损坏时返回空表', () {
    final file =
        File('${tempDir.path}${Platform.pathSeparator}settings.json');
    file.writeAsStringSync('not-json');
    final store = SettingsStore(dir: tempDir.path);
    expect(store.read(), isEmpty);
  });
}
