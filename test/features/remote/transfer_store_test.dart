import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/features/remote/transfer_controller.dart';
import 'package:toolbox/features/remote/transfer_store.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('transfer_store_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('TransferStore 往返序列化', () {
    final store = TransferStore(dir: tempDir.path);
    final tasks = [
      TransferTask(
        id: 't1',
        fileName: 'a.tar.gz',
        direction: TransferDirection.upload,
        totalBytes: 100,
        transferredBytes: 40,
        status: TransferStatus.running,
      ),
      TransferTask(
        id: 't2',
        fileName: 'b.log',
        direction: TransferDirection.download,
        totalBytes: 50,
        transferredBytes: 50,
        status: TransferStatus.done,
      ),
      TransferTask(
        id: 't3',
        fileName: 'c.zip',
        direction: TransferDirection.download,
        totalBytes: 10,
        transferredBytes: 2,
        status: TransferStatus.failed,
        error: '网络中断',
      ),
    ];
    store.save(tasks);
    final loaded = store.load();
    expect(loaded.length, 3);
    expect(loaded[0].id, 't1');
    expect(loaded[0].direction, TransferDirection.upload);
    expect(loaded[0].status, TransferStatus.running);
    expect(loaded[0].progress, closeTo(0.4, 0.001));
    expect(loaded[1].status, TransferStatus.done);
    expect(loaded[2].status, TransferStatus.failed);
    expect(loaded[2].error, '网络中断');
  });

  test('TransferController 加载历史任务并把未完成任务标记为失败', () {
    final store = TransferStore(dir: tempDir.path);
    store.save([
      TransferTask(
        id: 't1',
        fileName: 'a.tar.gz',
        direction: TransferDirection.upload,
        totalBytes: 100,
        transferredBytes: 40,
        status: TransferStatus.running,
      ),
      TransferTask(
        id: 't2',
        fileName: 'b.log',
        direction: TransferDirection.download,
        totalBytes: 50,
        transferredBytes: 50,
        status: TransferStatus.done,
      ),
    ]);

    final container = ProviderContainer(
      overrides: [
        transferStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(transferTasksProvider.notifier);
    // build() 触发加载
    expect(container.read(transferTasksProvider).length, 2);
    // 未完成任务被标记为 failed
    final t1 = container
        .read(transferTasksProvider)
        .firstWhere((t) => t.id == 't1');
    expect(t1.status, TransferStatus.failed);
    expect(t1.error, contains('重启'));
    final t2 = container
        .read(transferTasksProvider)
        .firstWhere((t) => t.id == 't2');
    expect(t2.status, TransferStatus.done);

    // 新增任务会持久化
    controller.add('c.zip', TransferDirection.download, totalBytes: 10);
    final reloaded = store.load();
    expect(reloaded.any((t) => t.fileName == 'c.zip'), isTrue);
  });
}
