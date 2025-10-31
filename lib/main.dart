/*
  File:        lib/main.dart
  
  Author:      Colin Fajardo

  Version:     3.3.9
               - improved orb to be more animated and responsive to TTS, creating a livelier UI effect
               - changed the icon inside of the orb to better represent "Home AI Max" theme
  
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

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    _audioPlayer.dispose();
    _server?.close(force: true);
    super.dispose();
  }

  Future<void> _startLocalServer() async {
    try {
      await _registerIP();
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 5000);
      _addDebug('Local server listening on port 5000');
      _server!.listen((HttpRequest request) async {
        try {
          final path = request.uri.path;
          final method = request.method;
          final body = await utf8.decoder.bind(request).join();
          _addDebug('Incoming $method $path');
          _addDebug('Incoming body: $body');
          //
          if (method == 'HEAD' && path == '/notify') {
            request.response.statusCode = 200;
            request.response.headers.set('Access-Control-Allow-Origin', '*');
            request.response.write('');
            _addDebug('Handled HEAD request for /notify');
            await request.response.close();
            return;
          }
          //
          if (method == 'POST' && path == '/notify') {
            try {
              final data = jsonDecode(body);
              final message = (data['message'] ?? '').toString();
              if (message.isNotEmpty) {
                setState(() {
                  _feedbackMessage = message;
                });
                _addDebug('Received notify message: $message');
                // Request TTS audio from configured Flask server and play it
                await _requestAndPlayTts(message);
              } else {
                _addDebug('Notify received but no message field');
              }
            } catch (e) {
              _addDebug('Error decoding notify JSON: $e');
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

  Future<void> _toggleListening() async {
    if (_isListening) {
      _addDebug('Mic button pressed: stopping listening');
      await _speech.stop();
      setState(() {
        _isListening = false;
      });
      _addDebug('Listening stopped (mic button)');
    } else {
      _addDebug('Mic button pressed: initializing listening');
      bool available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            setState(() {
              _isListening = false;
            });
            _addDebug('Listening stopped (mic button)');
            // Auto-send if enabled and there's text to send
            if (_autoSendSpeech && _controller.text.trim().isNotEmpty) {
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
      if (available) {
        setState(() {
          _isListening = true;
          _controller.clear();
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
      _addDebug('Sending to webhook: $webhookUrl');
      _addDebug('Payload: $encodedBody');
      final response = await http.post(
        Uri.parse(webhookUrl),
        headers: headers,
        body: encodedBody,
      // Timeout modified from 5 to 20 seconds for AI with reasoning effort
      ).timeout(const Duration(seconds: 20));
      _addDebug('Response: ${response.statusCode} ${response.reasonPhrase}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Log response details for debugging
        _addDebug('Response body: ${response.body}');
        _addDebug('Response headers: ${response.headers}');
        
        String? reply;        
        // Try to parse reply text from the response body
        try {
          final decoded = jsonDecode(response.body);
          _addDebug('Response JSON decoded');
          if (decoded is Map) {
            reply = decoded['reply'] ?? decoded['message'] ?? decoded['text'] ?? decoded['response'];
            _addDebug('Extracted reply key value: $reply');
          } else if (decoded is String) {
            reply = decoded;
            _addDebug('Decoded response is string');
          }
        } catch (e) {
          // _addDebug('Response not JSON: $e');
          // Not JSON: treat entire body as plain text
          if (response.body.trim().isNotEmpty) {
            reply = response.body.trim();
            _addDebug('Using raw body as reply: $reply');
          }
        }

        if (reply != null && reply.isNotEmpty) {
          _addDebug('Server reply: $reply');
          // ensure the orb animates immediately while we attempt to speak
          setState(() => _isSpeaking = true);
          _speakReply(reply);
        } else {
          setState(() {
            _feedbackMessage = 'Message sent successfully! (no reply)';
          });
        }        
        setState(() {
          _feedbackMessage = '$reply';
        });
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

  Future<void> _registerIP() async {
    try {
      final ip = (await NetworkInterface.list()).first.addresses.first.address;
      final ttsBase = _config['tts'] ?? await ConfigManager.getTtsServerUrl();
      final registerUri = Uri.parse('$ttsBase/register-ip');
      await http.post(
        registerUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ip': ip}),
      );
    } catch (e) {
      _addDebug('IP registration failed: $e');
    }
  }

  Future<void> _requestAndPlayTts(String text) async {
    try {
      final ttsBase = _config['tts'] ?? await ConfigManager.getTtsServerUrl();
      final uri = Uri.parse(ttsBase);
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
          // Not audio: maybe JSON with text reply
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
                    padding: const EdgeInsets.only(top: 12.0),
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
                const SizedBox(height: 24),
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
                decoration: const InputDecoration(labelText: 'Webhook URL'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Webhook cannot be empty';
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
          TextButton(
            onPressed: () async {
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
          TextButton(
            onPressed: () async {
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