import 'package:flutter/widgets.dart';
import 'package:toolbox/registry/platform_type.dart';
import 'package:toolbox/registry/tool.dart';
import 'package:toolbox/registry/tool_category.dart';
import '../presentation/settings_view.dart';

class SettingsTool extends Tool {
  @override
  String get id => 'tool-settings';
  @override
  String get name => '常规';
  @override
  String get description => '配置应用数据存储目录';
  @override
  ToolCategory get category => ToolCategory.system;
  @override
  Set<PlatformType> get supportedPlatforms => {PlatformType.windows};
  @override
  Widget buildContent(BuildContext context) => const SettingsView();
}
