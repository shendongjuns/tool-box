import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/features/remote/remote_controller.dart';
import 'package:toolbox/features/remote/remote_models.dart';
import 'package:toolbox/features/remote/remote_store.dart';

void main() {
  late Directory tempDir;

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        remoteStoreProvider.overrideWithValue(RemoteStore(dir: tempDir.path)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('remote_controller_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('新增连接并持久化', () {
    final container = makeContainer();
    final notifier = container.read(sshConnectionsProvider.notifier);
    notifier.add(const SshConnection(
      id: 'c1',
      name: 'prod',
      host: '192.168.1.10',
      port: 22,
      username: 'root',
      password: 'secret',
    ));

    final loaded = RemoteStore(dir: tempDir.path).load();
    expect(loaded, hasLength(1));
    expect(loaded.single.name, 'prod');
    expect(loaded.single.password, 'secret');
  });

  test('更新连接并持久化', () {
    final container = makeContainer();
    final notifier = container.read(sshConnectionsProvider.notifier);
    notifier.add(const SshConnection(
      id: 'c1',
      name: 'prod',
      host: 'h',
      port: 22,
      username: 'u',
      password: 'p',
    ));

    notifier.update(const SshConnection(
      id: 'c1',
      name: 'prod-2',
      host: 'h2',
      port: 2222,
      username: 'u2',
      password: 'p2',
    ));
    final loaded = RemoteStore(dir: tempDir.path).load();
    expect(loaded.single.name, 'prod-2');
    expect(loaded.single.host, 'h2');
    expect(loaded.single.port, 2222);
  });

  test('删除连接并持久化', () {
    final container = makeContainer();
    final notifier = container.read(sshConnectionsProvider.notifier);
    notifier.add(const SshConnection(
      id: 'c1',
      name: 'n',
      host: 'h',
      port: 22,
      username: 'u',
      password: 'p',
    ));
    notifier.delete('c1');
    expect(container.read(sshConnectionsProvider), isEmpty);
    expect(RemoteStore(dir: tempDir.path).load(), isEmpty);
  });
}
