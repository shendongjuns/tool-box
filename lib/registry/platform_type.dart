import 'package:flutter/foundation.dart';

enum PlatformType { windows, linux, macOS, android, ios, web }

PlatformType get currentPlatformType {
  if (kIsWeb) return PlatformType.web;
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows => PlatformType.windows,
    TargetPlatform.linux => PlatformType.linux,
    TargetPlatform.macOS => PlatformType.macOS,
    TargetPlatform.android => PlatformType.android,
    TargetPlatform.iOS => PlatformType.ios,
    TargetPlatform.fuchsia => PlatformType.linux,
  };
}
