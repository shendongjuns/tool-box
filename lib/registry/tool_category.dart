enum ToolCategory {
  data('数据处理'),
  database('数据库管理'),
  text('文本工具'),
  encode('编解码'),
  system('设置'),
  other('其他工具');

  const ToolCategory(this.displayName);
  final String displayName;
}
