import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/features/remote/remote_models.dart';

void main() {
  test('SshConnection JSON 往返', () {
    const conn = SshConnection(
      id: 'c1',
      name: 'prod',
      host: '192.168.1.10',
      port: 22,
      username: 'root',
      password: 'secret',
    );

    final restored = SshConnection.fromJson(conn.toJson());
    expect(restored.id, 'c1');
    expect(restored.name, 'prod');
    expect(restored.host, '192.168.1.10');
    expect(restored.port, 22);
    expect(restored.username, 'root');
    expect(restored.password, 'secret');
    expect(restored.hostLabel, '192.168.1.10:22');
  });

  test('端口缺失时默认 22', () {
    final conn = SshConnection.fromJson({
      'id': 'c1',
      'name': 'n',
      'host': 'h',
      'username': 'u',
    });
    expect(conn.port, 22);
    expect(conn.password, '');
    expect(conn.useKeyAuth, isFalse);
  });

  test('私钥认证字段 JSON 往返', () {
    const conn = SshConnection(
      id: 'c1',
      name: 'n',
      host: 'h',
      port: 22,
      username: 'u',
      password: '',
      useKeyAuth: true,
      privateKeyPath: 'C:\\Users\\me\\.ssh\\id_rsa',
      keyPassphrase: 'pass',
    );

    final restored = SshConnection.fromJson(conn.toJson());
    expect(restored.useKeyAuth, isTrue);
    expect(restored.privateKeyPath, 'C:\\Users\\me\\.ssh\\id_rsa');
    expect(restored.keyPassphrase, 'pass');
  });

  test('newRemoteId 生成唯一 id', () {
    expect(newRemoteId(), isNot(newRemoteId()));
  });
}
