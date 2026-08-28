/// 应用元信息。
///
/// 版本号单一来源：与 pubspec.yaml 的 `version` 保持一致
/// （CI 发布时以 git tag 为准，通过 --build-name 覆盖 exe 内嵌版本）。
library;

/// 应用显示名。
const String appName = 'ToolBox';

/// 应用版本号。
const String appVersion = '1.4.0';
