import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/features/settings/domain/settings_tool.dart';
import 'package:toolbox/registry/tool.dart';
import 'package:toolbox/registry/tool_registry.dart';

final toolboxRegistryProvider = Provider<ToolRegistry>(
  (ref) => ToolboxRegistry(),
);

/// 应用注册表：集中登记全部工具。
class ToolboxRegistry extends ToolRegistry {
  // 工具实例缓存为 final 字段：避免每次 registerAll 新建实例，
  // 保证导航与内容区持有同一实例。
  final List<Tool> _tools = [SettingsTool()];

  @override
  List<Tool> registerAll() => List.unmodifiable(_tools);
}
