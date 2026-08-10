import 'platform_type.dart';
import 'tool.dart';

/// 工具集中注册表：登记全部工具并按当前平台过滤。
abstract class ToolRegistry {
  /// 全部工具注册（子类集中登记）。
  List<Tool> registerAll();

  /// 当前平台可用的工具。
  List<Tool> availableTools() {
    final current = currentPlatformType;
    return registerAll()
        .where((t) => t.supportedPlatforms.contains(current))
        .toList();
  }
}
