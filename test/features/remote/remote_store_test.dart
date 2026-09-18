import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/features/remote/remote_models.dart';
import 'package:toolbox/features/remote/remote_store.dart';

/// 目录下的损坏备份文件（名带时间戳，按后缀匹配）。
///
/// Windows 上紧随 rename 之后的目录列举可能因文件系统过滤驱动
/// （如 Defender 实时扫描）短暂看不到新文件，因此轮询等待至多 2 秒。
List<File> _corruptBackups(Directory dir) {
  for (var i = 0; i < 40; i++) {
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.corrupt-bak'))
        .toList();
    if (files.isNotEmpty) return files;
    sleep(const Duration(milliseconds: 50));
  }
  return const [];
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

  test('JSON 语法损坏：回退空列表并留底 corrupt-bak（名带时间戳）', () {
    final file = File(corruptFilePath());
    file.writeAsStringSync('{"id": "not-a-list"');
    final store = RemoteStore(dir: tempDir.path);
    expect(store.load(), isEmpty);
    expect(_corruptBackups(tempDir), isNotEmpty, reason: '损坏文件应改名留底');
    expect(file.existsSync(), isFalse, reason: '原路径不应残留坏文件');
  });

  test('字段类型宽松：数字 id / 字符串端口都能救回（P1-1）', () {
    final file = File(corruptFilePath());
    // 旧版本或用外部工具改过的文件里，数字可能被写成字符串、id 可能是数字。
    // 这里应逐条宽松解析而不是整份丢弃。
    file.writeAsStringSync('[{"id": 1, "name": "n", "host": "h", '
        '"username": "u", "password": "p", "port": "2222"}]');
    final store = RemoteStore(dir: tempDir.path);
    final loaded = store.load();
    expect(loaded, hasLength(1));
    expect(loaded.first.id, '1');
    expect(loaded.first.port, 2222);
    expect(_corruptBackups(tempDir), isEmpty, reason: '数据合法就不该留底备份');
  });

  test('单条坏记录被跳过，其余连接照常载入', () {
    final file = File(corruptFilePath());
    file.writeAsStringSync('[' 
        '{"id": "ok-1", "name": "n1", "host": "h1", "username": "u"},'
        '{"name": "缺少 id，应被跳过"},'
        '"不是对象，应被跳过",'
        '{"id": "ok-2", "name": "n2", "host": "h2", "username": "u"}'
        ']');
    final store = RemoteStore(dir: tempDir.path);
    final loaded = store.load();
    expect(loaded.map((e) => e.id), ['ok-1', 'ok-2']);
    expect(_corruptBackups(tempDir), isEmpty);
  });
}
