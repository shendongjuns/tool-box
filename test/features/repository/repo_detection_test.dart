import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/features/repository/repo_detection.dart';
import 'package:toolbox/features/repository/repo_models.dart';

void main() {
  group('detectRepoType', () {
    test('识别 SVN 地址', () {
      expect(
        detectRepoType('https://10.0.0.10/svn/example_group/branches/proj-V1.0'),
        RepoType.svn,
      );
      expect(detectRepoType('svn://10.0.0.10/repo'), RepoType.svn);
    });

    test('识别 Git 地址', () {
      expect(
        detectRepoType('https://github.com/shendongjuns/tool-box.git'),
        RepoType.git,
      );
      expect(
        detectRepoType('git@github.com:shendongjuns/tool-box.git'),
        RepoType.git,
      );
      expect(
        detectRepoType('ssh://git@github.com/x/y.git'),
        RepoType.git,
      );
    });
  });

  group('detectVersion', () {
    test('识别多条地址中的共通版本号数字部分，并排除 IP', () {
      final urls = [
        'https://10.0.0.10/svn/example_group/branches/proj-V1.0',
        'https://10.0.0.10/svn/example_group/branches/ui-V1.0',
        'https://10.0.0.10/svn/example_group/branches/config-V1.0',
      ];
      expect(detectVersion(urls), '2.8');
    });

    test('无共通版本号时返回 null', () {
      expect(
        detectVersion([
          'https://a/svn/x-V1.0',
          'https://a/svn/y-V2.0',
        ]),
        isNull,
      );
    });
  });

  group('normalizeVersion', () {
    test('去除前导 V/v 并去空白，空值返回 null', () {
      expect(normalizeVersion('V2.8'), '2.8');
      expect(normalizeVersion('v2.8'), '2.8');
      expect(normalizeVersion(' 2.8 '), '2.8');
      expect(normalizeVersion(null), isNull);
      expect(normalizeVersion(''), isNull);
    });
  });

  group('parseBatch', () {
    test('解析 SVN 批量文本，V 保留为字面量并替换版本占位符', () {
      const text = '''
https://10.0.0.10/svn/example_group/branches/proj-V1.0
https://10.0.0.10/svn/example_group/branches/ui-V1.0
https://10.0.0.10/svn/example_group/branches/config-V1.0
''';
      final repos = parseBatch(text, version: '2.8');
      expect(repos, hasLength(3));
      expect(repos[0].type, RepoType.svn);
      expect(repos[0].name, 'tz');
      expect(
        repos[0].url,
        'https://10.0.0.10/svn/example_group/branches/tz-{version}',
      );
      expect(repos[1].name, 'tz_ui');
      expect(repos[2].name, 'tz_config');
    });

    test('解析 Git 地址不替换版本、去掉 .git 后缀', () {
      final repos = parseBatch('https://github.com/shendongjuns/tool-box.git');
      expect(repos, hasLength(1));
      expect(repos[0].type, RepoType.git);
      expect(repos[0].name, 'tool-box');
      expect(repos[0].url, 'https://github.com/shendongjuns/tool-box.git');
    });
  });

  group('resolveUrl', () {
    test('替换版本占位符并补回 V 前缀', () {
      expect(
        resolveUrl('https://x/svn/tz-{version}', '2.8'),
        'https://x/svn/proj-V1.0',
      );
      // 版本号若带 V 前缀也能正确归一化
      expect(
        resolveUrl('https://x/svn/tz-{version}', 'V2.8'),
        'https://x/svn/proj-V1.0',
      );
    });

    test('无版本时替换为空', () {
      expect(resolveUrl('https://x/svn/tz-{version}', null), 'https://x/svn/tz-');
    });
  });
}
