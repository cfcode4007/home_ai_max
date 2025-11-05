/*
  File:        lib/main.dart

  Author:      Colin Fajardo

  Version:     3.5.2
               - can now receive 'speak' notifications, translate them with TTS server and fall back to local translation if unavailable
               - some redundant and outdated code such as register ip and related items removed
               - landscape mode has been vaulted due to causing issues with portrait mode

  Description: Main file that assembles, and controls the logic of the Home AI Max Flutter app.
*/


import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'widgets/orb_visualizer.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'config.dart';
import 'package:flutter/foundation.dart';


void main() {
  runApp(const HomeAIMaxApp());
}

class HomeAIMaxApp extends StatelessWidget {
  const HomeAIMaxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Home AI Max',
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.dark(
          primary: Colors.deepPurpleAccent,
          secondary: Colors.blueAccent,
        ),
        scaffoldBackgroundColor: const Color(0xFF181A20),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF23243A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final List<String> _debugLog = [];
  bool _isSpeaking = false;
  late final FlutterTts _tts;
  HttpServer? _server;
  late final AudioPlayer _audioPlayer;
  final Map<String, String> _config = {};
  bool _debugLogVisible = false;
  bool _autoSendSpeech = false;

  void _addDebug(String message) {
    setState(() {
      _debugLog.add('[${DateTime.now().toIso8601String().substring(11,19)}] $message');
      if (_debugLog.length > 10) {
        _debugLog.removeAt(0);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    // Load config early into a centralized variable used across the app
    _initConfig();
    _speech = stt.SpeechToText();
    _tts = FlutterTts();
    _audioPlayer = AudioPlayer();
    _audioPlayer.onPlayerComplete.listen((event) {
      setState(() => _isSpeaking = false);
      _addDebug('AudioPlayer: playback complete');
    });
  // start local server to receive notifications from Flask
  _startLocalServer();
    _addDebug('Initializing TTS');
    _tts.setStartHandler(() {
      setState(() => _isSpeaking = true);
      _addDebug('TTS: start handler called');
    });
    _tts.setCompletionHandler(() {
      setState(() => _isSpeaking = false);
      _addDebug('TTS: completion handler called');
    });
    _tts.setErrorHandler((msg) {
      setState(() => _isSpeaking = false);
      _addDebug('TTS: error handler called: $msg');
    });
  }

  Future<void> _initConfig() async {
    try {
      final webhook = await ConfigManager.getWebhookUrl();
      final tts = await ConfigManager.getTtsServerUrl();
      final debugVisible = await ConfigManager.getDebugLogVisible();
      final autoSend = await ConfigManager.getAutoSendSpeech();
      setState(() {
        _config['webhook'] = webhook;
        _config['tts'] = tts;
        _debugLogVisible = debugVisible;
        _autoSendSpeech = autoSend;
      });
  _addDebug('Config loaded: webhook=$webhook tts=$tts debugVisible=$debugVisible autoSend=$autoSend');
    } catch (e) {
      _addDebug('Failed to load config: $e');
    }
  }

  Future<void> _resetToDefaults() async {
    try {
      await ConfigManager.setConfigValue('webhook_url', ConfigManager.defaultWebhookUrl);
      await ConfigManager.setConfigValue('tts_server_url', ConfigManager.defaultTtsUrl);
      await _initConfig();
    } catch (e) {
      _addDebug('Failed to reset defaults: $e');
    }
  }

  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  String? _feedbackMessage;

  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _lastRecognized = '';
  bool _autoSentThisSession = false;

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    _audioPlayer.dispose();
    _server?.close(force: true);
    super.dispose();
  }

  Future<void> _startLocalServer() async {
    // Skip local server on web platform, since browsers cannot bind to network ports
    if (kIsWeb) {
      _addDebug('Local server skipped on web platform');
      return;
    }
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 5000);
      _addDebug('Local server listening on port 5000');
      _server!.listen((HttpRequest request) async {
        try {
          final path = request.uri.path;
          final method = request.method;
          final body = await utf8.decoder.bind(request).join();
          _addDebug('Incoming $method $path');
          _addDebug('Incoming body: $body');
          if (method == 'POST' && path == '/speak') {
            try {
              final data = jsonDecode(body);
              final message = (data['message'] ?? '').toString();
              if (message.isNotEmpty) {
                setState(() {
                  _feedbackMessage = message;
                });
                _addDebug('Received message: $message');
                // Request TTS audio from configured Flask server and play it
                await _requestAndPlayTts(message);
              } else {
                _addDebug('Message received but no message field');
              }
            } catch (e) {
              _addDebug('Error decoding message JSON: $e');
            }
            request.response.statusCode = 200;
            request.response.headers.set('Access-Control-Allow-Origin', '*');
            request.response.write('Received');
          } else if (method == 'OPTIONS') {
            request.response.statusCode = 200;
            request.response.headers.set('Access-Control-Allow-Origin', '*');
            request.response.headers.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
            request.response.write('OK');
          } else {
            request.response.statusCode = 404;
            request.response.write('Not found');
          }
        } catch (e) {
          _addDebug('Local server handler error: $e');
          try {
            request.response.statusCode = 500;
            request.response.write('Error');
          } catch (_) {}
        } finally {
          await request.response.close();
        }
      });
    } catch (e) {
      _addDebug('Failed to start local server: $e');
    }
  }

  // On orb press
  Future<void> _toggleListening() async {
    // When it's already listening
    if (_isListening) {
      _addDebug('Mic button pressed: stopping listening');
      await _speech.stop();
      setState(() {
        _isListening = false;
      });
      _addDebug('Listening stopped (mic button)');
    // When not listening and needs to initialize
    } else {
      _addDebug('Mic button pressed: initializing listening');
      bool available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            setState(() {
              _isListening = false;
            });
            _addDebug('Listening stopped (mic button) - status: $status');
            // Auto-send only when speech recognition is truly complete ('done' status)
            // This prevents cutting off the last word when user pauses briefly
            // In landscape mode, always auto-send since there's no text input
            final shouldAutoSend = MediaQuery.of(context).orientation == Orientation.landscape ||
                                 (_autoSendSpeech && _controller.text.trim().isNotEmpty);
            if (status == 'done' && shouldAutoSend && !_autoSentThisSession) {
              _autoSentThisSession = true;
              _addDebug('Auto-sending speech: "${_controller.text.trim()}"');
              _sendText();
            }
          }
        },
        onError: (error) {
          setState(() {
            _isListening = false;
          });
          _addDebug('Listening error: ${error.errorMsg}');
        },
      );
      // When not listening and already initialized
      if (available) {
        setState(() {
          _isListening = true;
          _controller.clear();
          _autoSentThisSession = false;
        });
        _addDebug('Listening started (mic button)');
        _speech.listen(
          onResult: (result) {
            setState(() {
              _lastRecognized = result.recognizedWords;
              _controller.text = _lastRecognized;
              _controller.selection = TextSelection.fromPosition(
                TextPosition(offset: _controller.text.length),
              );
            });
            _addDebug('Transcribing (mic button): "${result.recognizedWords}"');
          },
          localeId: 'en_US',
        );
      } else {
        _addDebug('Speech recognizer not available (mic button)');
      }
    }
  }

  Future<void> _sendText() async {
    final text = _controller.text.trim();
    final encodedBody = jsonEncode({'query': text});
    final headers = {'Content-Type': 'application/json'};
    if (text.isEmpty) return;
    setState(() {
      _isLoading = true;
      _feedbackMessage = null;
    });
    try {
      final webhookUrl = _config['webhook'] ?? await ConfigManager.getWebhookUrl();
      _addDebug('Payload: $encodedBody');
      final response = await http.post(
        Uri.parse(webhookUrl),
        headers: headers,
        body: encodedBody,
      // Timeout modified from 5 to 20 seconds for AI with reasoning effort
      ).timeout(const Duration(seconds: 20));
      _addDebug('Response: ${response.statusCode} ${response.reasonPhrase}');
      if (response.statusCode >= 200 && response.statusCode < 300) {        
        try {
          final decoded = jsonDecode(response.body);
          _addDebug('Response JSON decoded');

          if (decoded['status'] == 'ok') {
            final message = decoded['message'] ?? '';
            final audioB64 = decoded['audio_b64'];

            if (message.isNotEmpty) {
              _addDebug('Server reply: $message');
              setState(() {
                _feedbackMessage = message;
              });

              // Play audio if available
              if (audioB64 != null && audioB64.isNotEmpty) {
                _addDebug('Playing GTTS base64 audio from response');
                setState(() => _isSpeaking = true);
                try {
                  // Decode base64 audio
                  final audioBytes = base64Decode(audioB64);
                  await _audioPlayer.play(BytesSource(audioBytes));
                } catch (e) {
                  _addDebug('Base64 audio playback error: $e');
                  // Fallback to local TTS
                  await _speakReply(message);
                }
              } else {
                // No audio, use local TTS
                setState(() => _isSpeaking = true);
                await _speakReply(message);
              }
            } else {
              setState(() {
                _feedbackMessage = 'Message sent successfully! (no reply)';
              });
            }
          } else {
            // Error status from server
            final errorMessage = decoded['message'] ?? 'Unknown error';
            setState(() {
              _feedbackMessage = 'Server error: $errorMessage';
            });
          }
        } catch (e) {
          _addDebug('JSON parsing error: $e');
          setState(() {
            _feedbackMessage = 'Response parsing error: $e';
          });
        }

        _controller.clear();
      } else {
        setState(() {
          _feedbackMessage = 'Failed to send: \n${response.statusCode} ${response.reasonPhrase}';
        });
      }
    } catch (e) {
      _addDebug('Error sending: $e');
      setState(() {
        _feedbackMessage = 'Error: \n${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _requestAndPlayTts(String text) async {
    try {
      final ttsUrl = _config['tts'] ?? await ConfigManager.getTtsServerUrl();
      final uri = Uri.parse(ttsUrl);
      _addDebug('Requesting TTS from $uri');
      final resp = await http.post(uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      ).timeout(const Duration(seconds: 8));
      _addDebug('TTS response: ${resp.statusCode} ${resp.reasonPhrase}');
      _addDebug('TTS response headers: ${resp.headers}');
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final contentType = resp.headers['content-type'] ?? '';
        if (contentType.contains('audio') && resp.bodyBytes.isNotEmpty) {
          _addDebug('Playing returned audio (${resp.bodyBytes.length} bytes)');
          setState(() => _isSpeaking = true);
          try {
            await _audioPlayer.play(BytesSource(resp.bodyBytes));
          } catch (e) {
            _addDebug('AudioPlayer.play error: $e');
            // fallback to local TTS
            await _speakReply(text);
          }
        } else {
          // Not audio, maybe JSON with text reply
          _addDebug('TTS response is not audio, falling back to local TTS');
          String? reply;
          try {
            final decoded = jsonDecode(resp.body);
            if (decoded is Map) reply = decoded['reply'] ?? decoded['message'] ?? decoded['text'];
          } catch (_) {
            // ignore
          }
          await _speakReply(reply ?? text);
        }
      } else {
        _addDebug('TTS request failed: ${resp.statusCode}');
        await _speakReply(text);
      }
    } catch (e) {
      _addDebug('Error requesting TTS: $e');
      await _speakReply(text);
    }
  }

  Future<void> _speakReply(String text) async {
    try {
      _addDebug('TTS: using local TTS');
      _addDebug('TTS: preparing to speak');
      await _tts.setLanguage('en-US');
      await _tts.setPitch(1.0);
      final speakResult = await _tts.speak(text);
      _addDebug('TTS.speak returned: $speakResult');
      // some platforms return immediately and call completion handler later
    } catch (e, st) {
      _addDebug('TTS speak error: $e\n$st');
      setState(() => _isSpeaking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home AI Max'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showConfigDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Orb visual (animates when speaking or listening)
                OrbVisualizer(
                  isSpeaking: _isSpeaking,
                  isListening: _isListening,
                  size: 120,
                  onTap: _isLoading ? null : _toggleListening,
                ),
                const SizedBox(height: 48),
                _buildTextInput(context),
                const SizedBox(height: 16),
                if (_isLoading) const CircularProgressIndicator(),
                if (_feedbackMessage != null && !_isLoading)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Builder(builder: (context) {
                      final msg = _feedbackMessage!;
                      Color color;
                      final lower = msg.toLowerCase();
                      if (msg.startsWith('Message sent') || msg.startsWith('Config reloaded')) {
                        color = Colors.greenAccent;
                      } else if (lower.startsWith('error') || lower.contains('failed') || lower.contains('error')) {
                        color = Colors.redAccent;
                      } else {
                        // Normal server-returned text should be white
                        color = Colors.white;
                      }
                      return Text(
                        msg,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      );
                    }),
                  ),
                const SizedBox(height: 32),
                // Debug log area (only shown if enabled)
                if (_debugLogVisible)
                  Container(
                    alignment: Alignment.bottomLeft,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Color.fromARGB((0.7 * 255).round(), 0, 0, 0),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _debugLog.map((msg) => Text(
                          msg,
                          style: const TextStyle(fontSize: 12, color: Colors.greenAccent),
                        )).toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextInput(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            minLines: 1,
            maxLines: 5,
            style: const TextStyle(fontSize: 18),
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _sendText(),
            decoration: const InputDecoration(
              hintText: 'Type your message...'
            ),
            onChanged: (_) => setState(() {}),
            enabled: !_isLoading && !_isListening,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.send_rounded),
          color: Theme.of(context).colorScheme.primary,
          onPressed: _controller.text.trim().isEmpty || _isLoading || _isListening ? null : _sendText,
        ),
      ],
    );
  }

  Future<void> _showConfigDialog() async {
    final webhook = await ConfigManager.getWebhookUrl();
    final tts = await ConfigManager.getTtsServerUrl();
    final debugVisible = await ConfigManager.getDebugLogVisible();
    final autoSend = await ConfigManager.getAutoSendSpeech();
    if (!mounted) return;
    final webhookCtrl = TextEditingController(text: webhook);
    final ttsCtrl = TextEditingController(text: tts);
    bool debugLogVisible = debugVisible;
    bool autoSendSpeech = autoSend;
    final formKey = GlobalKey<FormState>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Settings'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 20),
              TextFormField(
                controller: webhookCtrl,
                decoration: const InputDecoration(labelText: 'Server Base URL'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Server URL cannot be empty';
                  if (!v.startsWith('http')) return 'Must be a valid URL';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: ttsCtrl,
                decoration: const InputDecoration(labelText: 'TTS Server URL'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'TTS server cannot be empty';
                  if (!v.startsWith('http')) return 'Must be a valid URL';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              StatefulBuilder(
                builder: (context, setState) => SwitchListTile(
                  title: const Text('Show Debug Log'),
                  value: debugLogVisible,
                  onChanged: (value) {
                    setState(() {
                      debugLogVisible = value;
                    });
                  },
                ),
              ),
              const SizedBox(height: 6),
              StatefulBuilder(
                builder: (context, setState) => SwitchListTile(
                  title: const Text('Auto-send Speech'),
                  value: autoSendSpeech,
                  onChanged: (value) {
                    setState(() {
                      autoSendSpeech = value;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (mounted) Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          // Save button
          TextButton(
            onPressed: () async {
              // Show confirmation dialog
              final confirmed = await showDialog<bool>(
                context: context,
                useRootNavigator: true,
                builder: (context) => AlertDialog(
                  title: const Text('Confirm Save'),
                  content: const Text('Save these settings?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ) ?? false;
              if (!confirmed) return;
              // Save entered values
              if (formKey.currentState?.validate() != true) return;
              final newWebhook = webhookCtrl.text.trim();
              final newTts = ttsCtrl.text.trim();
              await ConfigManager.setConfigValue('webhook_url', newWebhook);
              await ConfigManager.setConfigValue('tts_server_url', newTts);
              await ConfigManager.setDebugLogVisible(debugLogVisible);
              await ConfigManager.setAutoSendSpeech(autoSendSpeech);
              // Ensure the state is still mounted before using the State's context
              if (!mounted) return;
              Navigator.of(this.context).pop();
              _addDebug('Settings saved');
              // refresh in-memory config cache
              await _initConfig();
              // user-visible confirmation
              if (mounted) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Settings saved')),
                );
              }
            },
            child: const Text('Save'),
          ),
          // Reset button
          TextButton(
            onPressed: () async {
              // Show confirmation dialog
              final confirmed = await showDialog<bool>(
                context: context,
                useRootNavigator: true,
                builder: (context) => AlertDialog(
                  title: const Text('Confirm Reset'),
                  content: const Text('Reset these settings to default and save?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              ) ?? false;
              if (!confirmed) return;
              // Reset stored values to defaults
              await _resetToDefaults();
              await ConfigManager.setDebugLogVisible(false); // Reset debug log to default (disabled)
              await ConfigManager.setAutoSendSpeech(false); // Reset auto-send speech to default (disabled)
              if (!mounted) return;
              Navigator.of(this.context).pop();
              _addDebug('Settings reset to defaults');
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(content: Text('Settings reset to defaults')),
              );
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}
