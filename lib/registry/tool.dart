import 'package:flutter/widgets.dart';
import 'platform_type.dart';
import 'tool_category.dart';

/// 工具接口：每个工具实现此接口并在注册表中登记。
abstract class Tool {
  String get id;
  String get name;
  String get description;
  ToolCategory get category;

  /// 支持的平台集合，注册表按当前平台过滤。
  Set<PlatformType> get supportedPlatforms;

  Widget buildContent(BuildContext context);
}
