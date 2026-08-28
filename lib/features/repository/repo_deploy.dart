import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:toolbox/features/remote/remote_models.dart';
import 'package:toolbox/features/remote/ssh_session.dart';

/// 远程命令执行结果。
class RemoteCommandResult {
  const RemoteCommandResult({
    required this.exitCode,
    required this.output,
  });

  final int exitCode;
  final String output;

  bool get success => exitCode == 0;
}

/// 通过 SSH 在远程执行命令并返回退出码与输出。
///
/// 统一 UTF-8 容错解码 stdout/stderr；超时兜底 10 分钟。
Future<RemoteCommandResult> remoteExec(
  SSHClient client,
  String command, {
  Duration timeout = const Duration(minutes: 10),
}) async {
  final session = await client.execute(command).timeout(timeout);
  final sb = StringBuffer();
  await session.stdout
      .map((b) => sb.write(utf8.decode(b, allowMalformed: true)))
      .drain<void>()
      .timeout(timeout);
  final stderrSb = StringBuffer();
  await session.stderr
      .map((b) => stderrSb.write(utf8.decode(b, allowMalformed: true)))
      .drain<void>()
      .timeout(timeout);
  final exitCode = await session.waitForExit(timeout: timeout) ?? -1;
  return RemoteCommandResult(
    exitCode: exitCode,
    output: '${sb.toString().trim()}\n${stderrSb.toString().trim()}'
        .trim(),
  );
}

/// 在远程执行 svn checkout。
///
/// [username]/[password] 可选（svn 仓库认证）。
Future<RemoteCommandResult> remoteSvnCheckout(
  SSHClient client,
  String url,
  String dir, {
  String? username,
  String? password,
}) {
  return remoteSvn(client, 'checkout', url, dir,
      username: username, password: password);
}

/// 在远程执行 svn update（更新已有工作副本到最新）。
Future<RemoteCommandResult> remoteSvnUpdate(
  SSHClient client,
  String dir, {
  String? username,
  String? password,
}) {
  return remoteSvn(client, 'update', null, dir,
      username: username, password: password);
}

Future<RemoteCommandResult> remoteSvn(
  SSHClient client,
  String action,
  String? url,
  String dir, {
  String? username,
  String? password,
}) {
  final args = <String>['svn', action, '--non-interactive'];
  if (username != null && username.isNotEmpty) {
    args.add('--username');
    args.add(username);
    args.add('--password');
    args.add(password ?? '');
  }
  if (url != null) args.add(url);
  args.add(dir);
  return remoteExec(client, args.join(' '));
}

/// 判断 svn 输出是否为认证失败（E170001 / Authentication failed 等）。
bool isSvnAuthError(RemoteCommandResult result) {
  final out = result.output.toLowerCase();
  return out.contains('e170001') ||
      out.contains('authentication failed') ||
      out.contains('authorization failed') ||
      out.contains('认证失败') ||
      out.contains('username/password');
}

/// 判断远程目录是否为已 checkout 的 svn 工作副本。
Future<bool> isSvnWorkingCopy(SSHClient client, String dir) async {
  final result = await remoteExec(client, 'test -d "$dir/.svn" && echo yes');
  return result.output.trim() == 'yes';
}

/// 建立远程拉取的 SSH 连接（使用已保存连接）。
Future<SSHClient> connectForDeploy(SshConnection connection) {
  return defaultSshConnector(connection);
}
