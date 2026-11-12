import 'dart:io';
import 'package:flutter/services.dart';

/// Keep macOS sandbox permission for user-selected cache folders across launches.
class CacheDirectoryAccess {
  static const _channel = MethodChannel('com.flutify/cache_directories');

  static Future<void> restore() async {
    if (Platform.isMacOS) await _channel.invokeMethod<void>('restore');
  }

  static Future<void> remember(String path) async {
    if (Platform.isMacOS) await _channel.invokeMethod<void>('remember', path);
  }
}
