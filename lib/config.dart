import 'package:shared_preferences/shared_preferences.dart';

class ConfigManager {
  static const String _keyWebhook = 'webhook_url';
  static const String _keyTts = 'tts_server_url';
  static const String _keyDebugLogVisible = 'debug_log_visible';
  static const String _keyAutoSendSpeech = 'auto_send_speech';
  static const String defaultWebhookUrl = 'http://192.168.123.199:5001/hagpt';
  static const String defaultTtsUrl = 'http://192.168.123.128:5001/tts';

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

  static Future<bool> getDebugLogVisible() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDebugLogVisible) ?? false; // Default to false (disabled)
  }

  static Future<bool> getAutoSendSpeech() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoSendSpeech) ?? false; // Default to false (manual send)
  }

  static Future<void> setConfigValue(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  static Future<void> setDebugLogVisible(bool visible) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDebugLogVisible, visible);
  }

  static Future<void> setAutoSendSpeech(bool autoSend) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoSendSpeech, autoSend);
  }
}