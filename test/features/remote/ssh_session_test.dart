import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/features/remote/remote_models.dart';
import 'package:toolbox/features/remote/ssh_session.dart';

void main() {
  const conn = SshConnection(
    id: 'c1',
    name: 'prod',
    host: 'h',
    port: 22,
    username: 'u',
    password: 'p',
  );

  test('连接失败时状态为 error', () async {
    final container = ProviderContainer(
      overrides: [
        sshConnectorProvider.overrideWithValue((connection) async {
          throw Exception('认证失败');
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(sshSessionsProvider.notifier).open(conn);
    final handle = container.read(sshSessionsProvider)[conn.id]!;
    expect(handle.status.value, SshSessionStatus.error);
    expect(handle.error.value, contains('认证失败'));
  });

  test('连接失败后仍保留会话以便展示错误，close 后移除', () async {
    final container = ProviderContainer(
      overrides: [
        sshConnectorProvider.overrideWithValue((connection) async {
          throw Exception('boom');
        }),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(sshSessionsProvider.notifier);
    await notifier.open(conn);
    expect(container.read(sshSessionsProvider), contains(conn.id));

    notifier.close(conn.id);
    expect(container.read(sshSessionsProvider), isEmpty);
  });

  test('同一连接重复打开不重复创建会话', () async {
    var connectCalls = 0;
    final container = ProviderContainer(
      overrides: [
        sshConnectorProvider.overrideWithValue((connection) async {
          connectCalls++;
          throw Exception('boom');
        }),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(sshSessionsProvider.notifier);
    await notifier.open(conn);
    await notifier.open(conn);

    expect(connectCalls, 1);
    expect(container.read(sshSessionsProvider).length, 1);
  });
}
