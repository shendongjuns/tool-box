import 'package:flutter/widgets.dart';
import 'package:toolbox/features/remote/remote_view.dart';
import 'package:toolbox/registry/platform_type.dart';
import 'package:toolbox/registry/tool.dart';
import 'package:toolbox/registry/tool_category.dart';

/// 远程管理工具：SSH 终端 + SFTP 文件传输。
class RemoteTool extends Tool {
  RemoteTool();

  @override
  String get id => 'remote';

  @override
  String get name => '远程管理';

  @override
  String get description => 'SSH 终端连接与 SFTP 文件传输，支持多会话。';

  @override
  ToolCategory get category => ToolCategory.work;

  @override
  Set<PlatformType> get supportedPlatforms => {PlatformType.windows};

  @override
  Widget buildContent(BuildContext context) => const RemoteView();
}
