/*
  File:        lib/main.dart
  Author:      Colin Bond
  Description: Main application file for Home AI Max Flutter app.
*/

import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'widgets/orb_visualizer.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'config.dart';
import 'package:network_info_plus/network_info_plus.dart';

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
  // Debug log state
  final List<String> _debugLog = [];
  bool _isSpeaking = false;
  late final FlutterTts _tts;
  HttpServer? _server;
  late final AudioPlayer _audioPlayer;

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
    // Optional: get TTS engine status
  _tts.getEngines.then((engines) => _addDebug('Available TTS engines: $engines')).catchError((e) => _addDebug('Error getting TTS engines: $e'));
  }
  // ...existing code...


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

  Future<void> _requestAndPlayTts(String text) async {
    try {
      final ttsBase = await ConfigManager.getTtsServerUrl();
      final uri = Uri.parse('$ttsBase/tts');
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

  // ...existing code...

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
      final webhookUrl = await ConfigManager.getWebhookUrl();
      _addDebug('Sending to webhook: $webhookUrl');
      _addDebug('Payload: $encodedBody');
      final response = await http.post(
        Uri.parse(webhookUrl),
        headers: headers,
        body: encodedBody,
      ).timeout(const Duration(seconds: 5));
      _addDebug('Response: ${response.statusCode} ${response.reasonPhrase}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Log response details for debugging
        _addDebug('Response body: ${response.body}');
        _addDebug('Response headers: ${response.headers}');

        // Try to parse reply text from the response body
        String? reply;
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
          _addDebug('Response not JSON: $e');
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
          _feedbackMessage = 'Message sent successfully!';
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

  Future<void> _registerIP() async {
    try {
      final ip = (await NetworkInterface.list()).first.addresses.first.address;
      await http.post(
        Uri.parse('http://192.168.123.128:5001/register-ip'), // Flask server IP
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ip': ip}),
      );
    } catch (e) {
      _addDebug('IP registration failed: $e');
      // print('IP registration failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Orb visual (animates when speaking)
                OrbVisualizer(isSpeaking: _isSpeaking, size: 120),
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
                      if (msg.startsWith('Message sent')) {
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
                // Debug log area
                Container(
                  alignment: Alignment.bottomLeft,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
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
        _buildMicButton(context),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.send_rounded),
          color: Theme.of(context).colorScheme.primary,
          onPressed: _controller.text.trim().isEmpty || _isLoading || _isListening ? null : _sendText,
        ),
      ],
    );
  }

  Widget _buildMicButton(BuildContext context) {
    return GestureDetector(
      onTap: _isLoading ? null : _toggleListening,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: _isListening ? Colors.redAccent : Colors.grey[800],
          shape: BoxShape.circle,
          boxShadow: _isListening
              ? [
                  BoxShadow(
                    color: Colors.redAccent.withOpacity(0.6),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ]
              : [],
        ),
        child: Icon(
          _isListening ? Icons.mic : Icons.mic_none,
          color: Colors.white,
        ),
      ),
    );
  }
}


  // ...existing code...