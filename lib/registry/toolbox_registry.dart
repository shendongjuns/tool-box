import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/features/repository/repo_tool.dart';
import 'package:toolbox/registry/tool.dart';
import 'package:toolbox/registry/tool_registry.dart';

final toolboxRegistryProvider = Provider<ToolRegistry>(
  (ref) => ToolboxRegistry(),
);

/// 应用注册表：集中登记全部工具。
class ToolboxRegistry extends ToolRegistry {
  @override
  List<Tool> registerAll() => [RepositoryTool()];
}
