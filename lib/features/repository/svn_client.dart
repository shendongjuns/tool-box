import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 执行 svn 命令的 runner；测试中可注入假实现。
typedef SvnRunner = Future<String> Function(
  List<String> args, {
  Duration timeout,
});

/// 默认 runner：启动真实 `svn` 进程执行命令。
Future<String> defaultSvnRunner(
  List<String> args, {
  Duration timeout = const Duration(minutes: 10),
}) async {
  final Process process;
  try {
    process = await Process.start('svn', args);
  } on ProcessException {
    throw const SvnException('未找到 svn 命令，请安装 Subversion 命令行客户端'
        '（SlikSVN 或 TortoiseSVN 勾选 command line client tools）。');
  }

  // 流式阶段只收集原始字节，不在此解码：Windows 中文系统下 svn 输出为
  // GBK 编码，流式 UTF-8 解码可能因非法字节抛 FormatException 导致崩溃。
  final stdoutBytes = <int>[];
  final stderrBytes = <int>[];
  process.stdout.listen(stdoutBytes.addAll, onError: (_) {});
  process.stderr.listen(stderrBytes.addAll, onError: (_) {});

  final int exitCode;
  try {
    exitCode = await process.exitCode.timeout(timeout);
  } on TimeoutException {
    process.kill();
    throw const SvnException('svn 执行超时，已终止。');
  }
  if (exitCode != 0) {
    throw SvnException(
      'svn ${args.join(' ')}\n退出码 $exitCode\n${_decode(stderrBytes)}',
    );
  }
  return _decode(stdoutBytes);
}

/// 字节解码：优先 UTF-8，非法序列回退系统编码（Windows 中文系统为 GBK）。
String _decode(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return systemEncoding.decode(bytes);
  }
}

final svnRunnerProvider = Provider<SvnRunner>((ref) => defaultSvnRunner);

/// svn 执行失败异常。
class SvnException implements Exception {
  const SvnException(this.message);

  final String message;

  @override
  String toString() => message;
}
