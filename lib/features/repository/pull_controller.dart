import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/features/repository/repo_detection.dart';
import 'package:toolbox/features/repository/repo_models.dart';
import 'package:toolbox/features/repository/svn_client.dart';

/// 单个仓库的拉取状态。
enum PullStatus {
  pending('待拉取'),
  pulling('拉取中'),
  success('成功'),
  skipped('跳过'),
  failed('失败');

  const PullStatus(this.label);
  final String label;
}

/// 单个仓库的拉取结果明细。
class PullItemResult {
  const PullItemResult({
    required this.repoName,
    required this.action,
    required this.ok,
    this.error,
  });

  final String repoName;

  /// 执行的操作：checkout（首次拉取）/ update（更新）。
  final String action;
  final bool ok;
  final String? error;
}

/// 拉取结果汇总。
class PullSummary {
  const PullSummary({
    required this.success,
    required this.skipped,
    required this.failed,
    this.results = const [],
  });

  final int success;
  final int skipped;
  final int failed;

  /// 每个仓库的明细（名称 + 操作类型 + 结果）。
  final List<PullItemResult> results;
}

/// 一键拉取进度：仓库 id -> 状态。
final repoPullControllerProvider =
    NotifierProvider<RepoPullController, Map<String, PullStatus>>(
  RepoPullController.new,
);

/// 一键拉取分组内 SVN 仓库，逐仓库更新状态。
class RepoPullController extends Notifier<Map<String, PullStatus>> {
  bool _running = false;

  @override
  Map<String, PullStatus> build() => const {};

  /// 是否正在拉取（拉取中禁用按钮）。
  bool get running => _running;

  /// 本地拉取分组内全部 SVN 仓库；返回汇总。
  ///
  /// 分组未绑定文件夹时返回 null；Git 仓库跳过；目标目录已存在且非空时
  /// 执行 **svn update**（更新到最新），否则 **svn checkout**（首次拉取）。
  /// 单个仓库失败不影响其余仓库。
  Future<PullSummary?> pullGroup(RepoGroup group) async {
    final localPath = group.localPath;
    if (localPath == null || localPath.trim().isEmpty) return null;
    if (_running) return null;

    _running = true;
    var success = 0;
    var skipped = 0;
    var failed = 0;
    final results = <PullItemResult>[];
    final statuses = <String, PullStatus>{
      for (final r in group.repos) r.id: PullStatus.pending,
    };
    state = statuses;

    for (final repo in group.repos) {
      if (repo.type != RepoType.svn) {
        statuses[repo.id] = PullStatus.skipped;
        skipped++;
        state = {...statuses};
        continue;
      }

      final url = resolveUrl(repo.url, group.version);
      // 目标目录用解析后的地址末段（含版本号，如 proj-V1.0）。
      final target =
          '$localPath${Platform.pathSeparator}${deriveRepoDirName(url)}';
      final dir = Directory(target);
      final exists = dir.existsSync() && dir.listSync().isNotEmpty;

      statuses[repo.id] = PullStatus.pulling;
      state = {...statuses};
      try {
        if (exists) {
          // 已有代码 → 更新到最新。
          await ref.read(svnRunnerProvider)(
            ['update', '--non-interactive', target],
          );
          results.add(PullItemResult(
            repoName: repo.name,
            action: 'update',
            ok: true,
          ));
        } else {
          // 首次拉取 → checkout。
          await ref.read(svnRunnerProvider)(
            ['checkout', '--non-interactive', url, target],
          );
          results.add(PullItemResult(
            repoName: repo.name,
            action: 'checkout',
            ok: true,
          ));
        }
        statuses[repo.id] = PullStatus.success;
        success++;
      } on Exception {
        statuses[repo.id] = PullStatus.failed;
        failed++;
        results.add(PullItemResult(
          repoName: repo.name,
          action: exists ? 'update' : 'checkout',
          ok: false,
        ));
      }
      state = {...statuses};
    }

    _running = false;
    return PullSummary(
      success: success,
      skipped: skipped,
      failed: failed,
      results: results,
    );
  }

  /// 设置单个仓库的拉取状态（单仓库操作时更新图标）。
  void setRepoStatus(String repoId, PullStatus status) {
    state = {...state, repoId: status};
  }

  /// 清除拉取状态。
  void reset() => state = const {};
}
