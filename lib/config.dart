/*
  File:        lib/config.dart
  Author:      Colin Bond
  
  Description: Config manager for Home AI Max.
               Stores application settings in SharedPreferences (in-app settings).
               Public API preserved: getWebhookUrl(), getTtsServerUrl(), setConfigValue(), getConfigFilePath().
*/

import 'package:shared_preferences/shared_preferences.dart';

class ConfigManager {
  static const String _keyWebhook = 'webhook_url';
  static const String _keyTts = 'tts_server_url';
  static const String defaultWebhookUrl = 'http://192.168.123.199:8123/api/webhook/chatgpt_ask';
  static const String defaultTtsUrl = 'http://192.168.123.128:5001';

  /// Return a friendly string describing where settings are stored.
  /// Previously this used a visible config.txt; now we store settings in
  /// SharedPreferences. This method preserves the public API but returns a
  /// message the user can understand.
  static Future<String> getConfigFilePath() async {
    return 'in-app settings (SharedPreferences)';
  }

  static Future<String> getWebhookUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyWebhook) ?? defaultWebhookUrl;
  }

  static Future<String> getTtsServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyTts) ?? defaultTtsUrl;
  }

  static Future<void> setConfigValue(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }
}