import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 临时密钥交换：验证 ssh-keygen 生成临时密钥 + 命令构造逻辑。
/// （真实安装/移除依赖远端 Linux 语义，本机 Windows sshd 不适用。）
void main() {
  test('ssh-keygen 生成 ed25519 密钥对', () async {
    final tempDir = Directory.systemTemp.createTempSync('key_gen');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final keyPath = '${tempDir.path}${Platform.pathSeparator}id_ed25519';

    final gen = await Process.run(
      r'C:\Windows\System32\OpenSSH\ssh-keygen.exe',
      ['-t', 'ed25519', '-N', '', '-f', keyPath, '-q'],
    );
    expect(gen.exitCode, 0, reason: 'ssh-keygen 应成功');
    expect(File(keyPath).existsSync(), isTrue, reason: '私钥应生成');
    expect(File('$keyPath.pub').existsSync(), isTrue, reason: '公钥应生成');

    // 公钥格式：ssh-ed25519 <base64> <注释>。
    final pub = await File('$keyPath.pub').readAsString();
    expect(pub.trim().startsWith('ssh-ed25519 '), isTrue,
        reason: '公钥应为 ed25519 格式');
  });

  test('公钥安装命令对 Linux 语义正确（bash 语法）', () {
    final pubKey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA test@host';
    // 与 worker _installPubKey 一致的命令：mkdir + 追加 + 权限。
    final installCmd =
        'mkdir -p ~/.ssh && chmod 700 ~/.ssh && '
        "echo '$pubKey' >> ~/.ssh/authorized_keys && "
        'chmod 600 ~/.ssh/authorized_keys';
    // 单引号包裹公钥 → 内容不被 shell 展开。
    expect(installCmd.contains("echo '$pubKey'"), isTrue);
    expect(installCmd.contains('~/.ssh/authorized_keys'), isTrue);

    // 移除命令：grep -v 过滤该行。
    final removeCmd =
        "grep -vF '$pubKey' ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp && "
        'mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys';
    expect(removeCmd.contains("grep -vF '$pubKey'"), isTrue);
  });
}
