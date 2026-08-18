import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/features/repository/svn_client.dart';

void main() {
  test('SvnException 消息透传', () {
    const e = SvnException('出错');
    expect(e.toString(), '出错');
  });

  test('svnRunnerProvider 默认使用 defaultSvnRunner', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(svnRunnerProvider), same(defaultSvnRunner));
  });
}
