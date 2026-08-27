import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/features/remote/transfer_controller.dart';
import 'package:toolbox/features/remote/transfer_store.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('transfer_queue_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('上传任务排队：依次执行，可无限追加', () async {
    final container = ProviderContainer(
      overrides: [
        transferStoreProvider.overrideWithValue(TransferStore(dir: tempDir.path)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(transferTasksProvider.notifier);

    final executed = <String>[];
    final completers = <String, Completer<void>>{};

    // 追加 3 个任务。
    for (var i = 0; i < 3; i++) {
      final id = controller.add('file_$i.bin', TransferDirection.upload, totalBytes: 100);
      final c = Completer<void>();
      completers[id] = c;
      controller.enqueue(id, () async {
        executed.add(id);
        await c.future;
        controller.finish(id, TransferStatus.done);
      });
    }

    // 第一个应已启动（running），其余 pending。
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final tasks = container.read(transferTasksProvider);
    expect(tasks.where((t) => t.status == TransferStatus.running).length, 1,
        reason: '应只有一个任务在运行');
    expect(tasks.where((t) => t.status == TransferStatus.pending).length, 2);

    // 完成第一个 → 第二个启动。
    completers[tasks.first.id]!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final tasks2 = container.read(transferTasksProvider);
    expect(tasks2.where((t) => t.status == TransferStatus.running).length, 1);
    expect(executed.length, 2, reason: '完成第一个后应启动第二个');

    // 完成第二个 → 第三个启动。
    final running2 = tasks2.firstWhere((t) => t.status == TransferStatus.running);
    completers[running2.id]!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(executed.length, 3, reason: '第三个应执行');

    // 完成第三个 → 队列清空。
    final tasks3 = container.read(transferTasksProvider);
    final running3 = tasks3.firstWhere((t) => t.status == TransferStatus.running);
    completers[running3.id]!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      container.read(transferTasksProvider).where((t) => t.status == TransferStatus.pending).length,
      0,
      reason: '队列应清空',
    );
    expect(executed, hasLength(3));
  });
}
