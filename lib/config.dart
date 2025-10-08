/*
  File:        lib/config.dart
  Author:      Colin Bond

  Description: Config file handler for Home AI Max Flutter app.
               Reads and writes a simple key-value text file for runtime-editable config.
*/

import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ConfigManager {
	static const String _fileName = 'config.txt';
	static const String defaultWebhookUrl = 'http://192.168.123.199:8123/api/webhook/chatgpt_ask';
	// static const String defaultgTTSUrl = '';

	static Future<File> _getConfigFile() async {
		final dir = await getApplicationDocumentsDirectory();
		return File('${dir.path}/$_fileName');
	}

	static Future<Map<String, String>> _readConfigMap() async {
		final file = await _getConfigFile();
		if (!(await file.exists())) {
			await file.writeAsString('webhook_url=$defaultWebhookUrl\n');
		}
		final lines = await file.readAsLines();
		final map = <String, String>{};
		for (final line in lines) {
			final idx = line.indexOf('=');
			if (idx > 0) {
				final key = line.substring(0, idx).trim();
				final value = line.substring(idx + 1).trim();
				map[key] = value;
			}
		}
		return map;
	}

	static Future<String> getWebhookUrl() async {
		final map = await _readConfigMap();
		return map['webhook_url']?.isNotEmpty == true ? map['webhook_url']! : defaultWebhookUrl;
	}

	static Future<String> getTtsServerUrl() async {
		final map = await _readConfigMap();
		// Allow configuring a separate flask server base URL; fall back to same host as webhook
		return map['tts_server_url']?.isNotEmpty == true ? map['tts_server_url']! : 'http://192.168.123.128:5001';
	}

	static Future<void> setConfigValue(String key, String value) async {
		final file = await _getConfigFile();
		final map = await _readConfigMap();
		map[key] = value;
		final content = map.entries.map((e) => '${e.key}=${e.value}').join('\n');
		await file.writeAsString(content);
	}
}