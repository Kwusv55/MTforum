import 'package:flutter/services.dart';

/// 读取当前安装包的版本信息（versionName / versionCode）。
///
/// 原生侧实现见 `MainActivity.getVersionInfo`。
class AppVersionService {
  AppVersionService._();
  static final AppVersionService instance = AppVersionService._();

  static const _channel = MethodChannel('mtforum/app_info');

  Future<Map<String, dynamic>> getCurrentVersionInfo() async {
    final raw =
        await _channel.invokeMapMethod<String, dynamic>('getVersionInfo');
    return raw ?? const <String, dynamic>{};
  }
}
