// Config file handler for Home AI Max
// Reads and writes a simple text file for the webhook URL

import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ConfigManager {
	static const String _fileName = 'config.txt';
	static const String defaultWebhookUrl = 'http://192.168.123.180:8123/api/webhook/chatgpt_ask';

	// Get the path to the config file
	static Future<File> _getConfigFile() async {
		final dir = await getApplicationDocumentsDirectory();
		return File('${dir.path}/$_fileName');
	}

	// Read the webhook URL from the config file, or create it with default if missing
	static Future<String> getWebhookUrl() async {
		final file = await _getConfigFile();
		if (await file.exists()) {
			final url = await file.readAsString();
			return url.trim().isEmpty ? defaultWebhookUrl : url.trim();
		} else {
			await file.writeAsString(defaultWebhookUrl);
			return defaultWebhookUrl;
		}
	}

	// Write a new webhook URL to the config file
	static Future<void> setWebhookUrl(String url) async {
		final file = await _getConfigFile();
		await file.writeAsString(url.trim());
	}
}