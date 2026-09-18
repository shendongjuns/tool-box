import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/common/json_file_recovery.dart';
import 'package:toolbox/common/json_store_io.dart';

/// 数据安全基座的行为约定（对应审计的 P0-2 / P1-1 / P1-7）：
/// * 写入必须原子（临时文件 + rename），任何时刻主文件都完整；
/// * 主文件损坏时自动回退上一版，而不是让用户面对空数据；
/// * 单条记录坏掉只跳过它，其余数据照常载入；
/// * 损坏文件留底备份名带时间戳，第二次损坏也能备份成功。
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('json_store_io_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  String pathOf(String name) => '${dir.path}${Platform.pathSeparator}$name';

  test('写入成功后主文件完整，且不残留临时文件', () {
    final path = pathOf('data.json');
    expect(JsonStoreIo.write(path, {'a': 1}, tag: 'test'), isTrue);

    expect(File(path).existsSync(), isTrue);
    expect(File('$path${JsonStoreIo.tmpSuffix}').existsSync(), isFalse);
    expect(jsonDecode(File(path).readAsStringSync()), {'a': 1});
  });

  test('覆盖写入时保留上一版到 .prev（可回滚）', () {
    final path = pathOf('data.json');
    JsonStoreIo.write(path, {'v': 1}, tag: 'test');
    JsonStoreIo.write(path, {'v': 2}, tag: 'test');

    expect(jsonDecode(File(path).readAsStringSync()), {'v': 2});
    final prev = File('$path${JsonStoreIo.prevSuffix}');
    expect(prev.existsSync(), isTrue);
    expect(jsonDecode(prev.readAsStringSync()), {'v': 1});
  });

  test('主文件损坏时自动回退上一版并标记 fallback', () {
    final path = pathOf('data.json');
    JsonStoreIo.write(path, {'v': 1}, tag: 'test');
    JsonStoreIo.write(path, {'v': 2}, tag: 'test');
    // 模拟「写一半被杀」：主文件被截断成非法 JSON
    File(path).writeAsStringSync('{"v": 2');

    final result = JsonStoreIo.read(path, tag: 'test');
    expect(result.fallback, isTrue);
    expect(result.data, {'v': 1});
    expect(result.error, isNotNull);
  });

  test('主文件与上一版都损坏时返回空数据并给出错误描述', () {
    final path = pathOf('data.json');
    File(path).writeAsStringSync('not json');
    File('$path${JsonStoreIo.prevSuffix}').writeAsStringSync('also broken');

    final result = JsonStoreIo.read(path, tag: 'test');
    expect(result.data, isNull);
    expect(result.fallback, isFalse);
    expect(result.error, isNotNull);
  });

  test('文件不存在时返回空数据（首次运行路径）', () {
    final result = JsonStoreIo.read(pathOf('missing.json'), tag: 'test');
    expect(result.data, isNull);
    expect(result.error, isNull);
  });

  test('逐条解析：坏条目被跳过，其余完好数据照常载入', () {
    final raw = [
      {'id': 'a', 'port': 22},
      'this is not a map',
      {'port': 22}, // 缺 id → 由 parse 抛错，跳过
      {'id': 'b', 'port': '2222'},
    ];

    final parsed = JsonStoreIo.parseList<Map<String, dynamic>>(
      raw,
      (json) {
        final id = json['id'];
        if (id is! String) throw const FormatException('缺少 id');
        return json;
      },
      tag: 'test',
    );

    expect(parsed.length, 2);
    expect(parsed.map((e) => e['id']), ['a', 'b']);
  });

  test('损坏备份文件名带时间戳，第二次损坏也能备份', () {
    final path = pathOf('data.json');
    File(path).writeAsStringSync('broken-1');
    final first = backupCorruptJsonFile(path, 'e1');
    expect(first, isNotNull);
    expect(first!.endsWith('.corrupt-bak'), isTrue);

    File(path).writeAsStringSync('broken-2');
    final second = backupCorruptJsonFile(path, 'e2');
    expect(second, isNotNull);
    expect(second, isNot(first)); // 不会因为「同名已存在」而失败
    expect(File(first).readAsStringSync(), 'broken-1');
    expect(File(second!).readAsStringSync(), 'broken-2');
  });

  test('文件不存在时备份返回 null（不抛错）', () {
    expect(backupCorruptJsonFile(pathOf('missing.json'), 'e'), isNull);
  });
}
