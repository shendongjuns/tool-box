import 'dart:convert';
import 'dart:io';

/// 应用配置：仅存储数据目录路径。配置固定存放在
/// %APPDATA%/tool-box/settings.json（独立于数据目录，
/// 数据目录转移不影响配置读取）。
class AppSettings {
  const AppSettings({required this.dataDir});

  /// 数据目录绝对路径（所有应用内容存放处）。
  final String dataDir;

  Map<String, dynamic> toJson() => {'dataDir': dataDir};

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        dataDir: json['dataDir'] as String? ?? defaultDataDir(),
      );

  /// 默认数据目录：用户目录/tool-box。
  static String defaultDataDir() {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    return '$home${Platform.pathSeparator}tool-box';
  }
}

/// 配置存储：读写 %APPDATA%/tool-box/settings.json。
class AppSettingsStore {
  AppSettingsStore({String? appDataDir})
      : _appDataDir = appDataDir ??
            Platform.environment['APPDATA'] ??
            Platform.environment['HOME'] ??
            '.';

  final String _appDataDir;

  /// 配置目录：%APPDATA%/tool-box。
  Directory get configDir =>
      Directory('$_appDataDir${Platform.pathSeparator}tool-box');

  File get _settingsFile =>
      File('${configDir.path}${Platform.pathSeparator}settings.json');

  Future<AppSettings> load() async {
    try {
      if (!_settingsFile.existsSync()) {
        return AppSettings(dataDir: AppSettings.defaultDataDir());
      }
      final json = jsonDecode(_settingsFile.readAsStringSync());
      if (json is Map<String, dynamic>) return AppSettings.fromJson(json);
      return AppSettings(dataDir: AppSettings.defaultDataDir());
    } catch (_) {
      return AppSettings(dataDir: AppSettings.defaultDataDir());
    }
  }

  Future<void> save(AppSettings settings) async {
    try {
      configDir.createSync(recursive: true);
      _settingsFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      );
    } catch (_) {
      // 配置写入失败不影响应用运行
    }
  }
}
