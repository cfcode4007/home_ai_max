# Home AI Max

Home AI Max is a Flutter app that sends text queries to a configured webhook
and reads server replies out loud. It also accepts incoming POST notifications
from a local server and can request/receive TTS audio from a companion Flask
service. The central orb visually animates while the app is speaking.

Core features

- Send text queries to a webhook and display server responses in-app.
- Speak server replies using on-device TTS (via `flutter_tts`).
- If the configured TTS server returns audio bytes, the app will play them
	directly (fallback to local TTS if playing fails).
- A local HTTP server (port 5000) accepts POST /notify to trigger speak/play.
- Central orb visualizer animates while speaking.
- In-app settings stored in SharedPreferences (editable via Settings).

How to use

1. Install and run the app on Android or other supported platforms.
2. Open Settings (gear icon) to set your Webhook URL and optional TTS Server
	 base URL. Defaults are provided.
3. Type a message and send it — the app will POST to the webhook and read any
	 reply it receives.
4. (Optional) Configure your local Flask server to accept `/register-ip` and
	 `/tts` endpoints. The app will POST its IP to `/register-ip` for local
	 notification routing, and will request `/tts` when a notification arrives.

Settings

- Settings are stored in-app using SharedPreferences; there is no external
	`config.txt` file. Use the app Settings dialog to edit the webhook and TTS
	server URLs. Save shows a confirmation; Reset restores defaults.

Developer notes

- Main code is in `lib/main.dart`.
	- Network, TTS, local server, and UI are implemented there.
	- `lib/config.dart` exposes `ConfigManager` backed by SharedPreferences.
	- `lib/widgets/orb_visualizer.dart` contains the visualizer used while
		speaking.
- Dependencies of interest: `flutter_tts`, `audioplayers`, `speech_to_text`,
	`shared_preferences`.
- To run static analysis:

```bash
flutter pub get
flutter analyze
```

Notes and troubleshooting

- Audio playback and TTS behavior may vary by device and installed TTS
	engines. Use the in-app debug area to view request/response details.
- If you were previously looking for a `config.txt` in external storage,
	settings are now persisted inside the app; use the Settings dialog.

## Settings

This app stores configuration (webhook URL and TTS server URL) in-app using
SharedPreferences. There is no longer a visible `config.txt` file on the
device. To change settings:

- Open the app and tap the Settings (gear) icon in the app bar.
- Edit the Webhook URL or TTS Server URL and press Save.

The app persists these values and uses them for outgoing requests and for
registering the device with your local TTS/Flask server.
