import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/features/remote/transfer_controller.dart';
import 'package:toolbox/features/remote/transfer_store.dart';

void main() {
  late Directory tempDir;
  setUp(() { tempDir = Directory.systemTemp.createTempSync('queue_fail'); });
  tearDown(() { tempDir.deleteSync(recursive: true); });

  test('任务失败/异常后队列继续下一个', () async {
    final container = ProviderContainer(
      overrides: [transferStoreProvider.overrideWithValue(TransferStore(dir: tempDir.path))],
    );
    addTearDown(container.dispose);
    final controller = container.read(transferTasksProvider.notifier);

    final executed = <String>[];

    // 任务1 立即失败，任务2 正常完成，任务3 正常。
    final id1 = controller.add('f1', TransferDirection.upload, totalBytes: 1);
    controller.enqueue(id1, () async {
      executed.add(id1);
      controller.finish(id1, TransferStatus.failed, error: '模拟失败');
    });
    final id2 = controller.add('f2', TransferDirection.upload, totalBytes: 1);
    controller.enqueue(id2, () async {
      executed.add(id2);
      controller.finish(id2, TransferStatus.done);
    });
    final id3 = controller.add('f3', TransferDirection.upload, totalBytes: 1);
    controller.enqueue(id3, () async {
      executed.add(id3);
      controller.finish(id3, TransferStatus.done);
    });

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(executed, [id1, id2, id3], reason: '三个任务应依次执行（含失败的）');
    final tasks = container.read(transferTasksProvider);
    expect(tasks.firstWhere((t) => t.id == id1).status, TransferStatus.failed);
    expect(tasks.firstWhere((t) => t.id == id2).status, TransferStatus.done);
    expect(tasks.firstWhere((t) => t.id == id3).status, TransferStatus.done);
  });
}
