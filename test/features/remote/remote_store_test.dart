import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/features/remote/remote_models.dart';
import 'package:toolbox/features/remote/remote_store.dart';

/// Windows 上紧随 rename 之后的 existsSync 可能因文件系统过滤驱动
/// （如 Defender 实时扫描）短暂看不到新文件，轮询等待至多 2 秒。
bool existsEventually(String path) {
  final file = File(path);
  for (var i = 0; i < 40; i++) {
    if (file.existsSync()) return true;
    sleep(const Duration(milliseconds: 50));
  }
  return file.existsSync();
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('remote_store_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  SshConnection sampleConn() => const SshConnection(
        id: 'c1',
        name: '样例',
        host: 'example.com',
        port: 2222,
        username: 'u',
        password: 'p',
      );

  String corruptFilePath() =>
      '${tempDir.path}${Platform.pathSeparator}ssh_connections.json';

  test('save/load 往返一致', () {
    final store = RemoteStore(dir: tempDir.path);
    store.save([sampleConn()]);
    final loaded = store.load();
    expect(loaded, hasLength(1));
    expect(loaded.first.id, 'c1');
    expect(loaded.first.host, 'example.com');
    expect(loaded.first.port, 2222);
  });

  test('JSON 语法损坏：回退空列表并留底 corrupt-bak', () {
    final file = File(corruptFilePath());
    file.writeAsStringSync('{"id": "not-a-list"');
    final store = RemoteStore(dir: tempDir.path);
    expect(store.load(), isEmpty);
    expect(existsEventually('${file.path}.corrupt-bak'), isTrue,
        reason: '损坏文件应改名留底');
    expect(file.existsSync(), isFalse, reason: '原路径不应残留坏文件');
  });

  test('字段类型错误（TypeError 非 Exception）：同样回退并留底', () {
    final file = File(corruptFilePath());
    // id 为数字而非字符串，fromJson 的 as String 抛 TypeError。
    file.writeAsStringSync('[{"id": 1, "name": "n", "host": "h", '
        '"username": "u", "password": "p"}]');
    final store = RemoteStore(dir: tempDir.path);
    expect(store.load(), isEmpty);
    expect(existsEventually('${file.path}.corrupt-bak'), isTrue,
        reason: 'TypeError 属 Error，也应被捕获并留底');
  });
}
