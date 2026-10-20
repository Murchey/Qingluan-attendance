import 'dart:io';
import 'package:flutter/services.dart';

abstract final class UpdatePlatform {
  static const channel = MethodChannel('qingluan/update');
  static Future<String> version() async {
    if (!Platform.isAndroid) {
      return const String.fromEnvironment('APP_VERSION', defaultValue: '1.0.3');
    }
    try {
      return await channel.invokeMethod<String>('version') ?? '1.0.3';
    } on MissingPluginException {
      return '1.0.3';
    }
  }

  static Future<bool> install(String path) async {
    if (!Platform.isAndroid) {
      throw const FormatException('请在 Android 设备上安装此 APK');
    }
    return await channel.invokeMethod<bool>('install', {'path': path}) ?? false;
  }
}
