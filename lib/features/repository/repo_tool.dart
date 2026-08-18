import 'package:flutter/widgets.dart';
import 'package:toolbox/features/repository/repo_view.dart';
import 'package:toolbox/registry/platform_type.dart';
import 'package:toolbox/registry/tool.dart';
import 'package:toolbox/registry/tool_category.dart';

/// 代码仓库管理工具。
class RepositoryTool extends Tool {
  RepositoryTool();

  @override
  String get id => 'repository';

  @override
  String get name => '代码仓库管理';

  @override
  String get description => '管理 SVN / Git 仓库地址，支持分组与版本变量。';

  @override
  ToolCategory get category => ToolCategory.work;

  @override
  Set<PlatformType> get supportedPlatforms => {PlatformType.windows};

  @override
  Widget buildContent(BuildContext context) => const RepositoryView();
}
