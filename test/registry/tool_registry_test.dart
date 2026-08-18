import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox/registry/platform_type.dart';
import 'package:toolbox/registry/tool.dart';
import 'package:toolbox/registry/tool_category.dart';
import 'package:toolbox/registry/tool_registry.dart';

class _FakeTool extends Tool {
  _FakeTool(this._id, this._platforms);
  final String _id;
  final Set<PlatformType> _platforms;

  @override
  String get id => _id;
  @override
  String get name => _id;
  @override
  String get description => 'desc';
  @override
  ToolCategory get category => ToolCategory.other;
  @override
  Set<PlatformType> get supportedPlatforms => _platforms;

  @override
  Widget buildContent(BuildContext context) => const SizedBox.shrink();
}

class _FakeRegistry extends ToolRegistry {
  @override
  List<Tool> registerAll() => [
        _FakeTool('windows-tool', {PlatformType.windows}),
        _FakeTool('desktop-tool', {PlatformType.windows, PlatformType.linux}),
        _FakeTool('mobile-tool', {PlatformType.android, PlatformType.ios}),
      ];
}

class _DuplicateRegistry extends ToolRegistry {
  @override
  List<Tool> registerAll() => [
        _FakeTool('dup', {PlatformType.windows}),
        _FakeTool('dup', {PlatformType.windows}),
        _FakeTool('unique', {PlatformType.windows}),
      ];
}

void main() {
  // flutter test 默认 defaultTargetPlatform 为 android，
  // 本项目为 Windows 桌面应用，显式固定为 windows 平台进行过滤验证。
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('availableTools 只含当前平台工具', () {
    final registry = _FakeRegistry();
    final available = registry.availableTools().map((t) => t.id).toList();
    final current = currentPlatformType;
    for (final id in available) {
      expect(
        registry.registerAll().firstWhere((t) => t.id == id).supportedPlatforms,
        contains(current),
      );
    }
    expect(available, contains('desktop-tool'));
  });

  test('availableTools 按 id 去重并保持顺序', () {
    final registry = _DuplicateRegistry();
    final ids = registry.availableTools().map((t) => t.id).toList();
    expect(ids, ['dup', 'unique']);
  });

  test('ToolCategory 七分类展示名', () {
    expect(ToolCategory.values.length, 7);
    expect(ToolCategory.work.displayName, '工作');
    expect(ToolCategory.database.displayName, '数据库管理');
  });
}
