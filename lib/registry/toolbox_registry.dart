import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/registry/tool.dart';
import 'package:toolbox/registry/tool_registry.dart';

final toolboxRegistryProvider = Provider<ToolRegistry>(
  (ref) => ToolboxRegistry(),
);

/// 应用注册表：集中登记全部工具。当前无工具（纯框架壳）。
class ToolboxRegistry extends ToolRegistry {
  @override
  List<Tool> registerAll() => const [];
}
