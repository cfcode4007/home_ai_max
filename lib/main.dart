/*
  File:        lib/main.dart
  Author:      Colin Bond
  Description: Main application file for Home AI Max Flutter app.
*/

import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;
import 'dart:convert';
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
  // Debug log state
  final List<String> _debugLog = [];

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
    _initWakeWordConfig();
  }

  Future<void> _initWakeWordConfig() async {
    _wakeWord = (await ConfigManager.getWakeWord()).toLowerCase();
    _wakeWordMaxDuration = await ConfigManager.getMaxDuration();
    _wakeWordSilenceTimeout = await ConfigManager.getSilenceTimeout();
    setState(() {});
  }

  void _toggleWakeWordMode() async {
    _addDebug('Orb pressed: toggling wake word mode ${_wakeWordMode ? 'OFF' : 'ON'}');
    if (_wakeWordMode) {
      // Turn off wake word mode
      setState(() {
        _wakeWordMode = false;
        _wakeWordActive = false;
      });
      await _speech.stop();
      _addDebug('Wake word mode OFF, listening stopped');
    } else {
      // Turn on wake word mode
      setState(() {
        _wakeWordMode = true;
        _wakeWordActive = false;
      });
      _controller.clear();
      _addDebug('Wake word mode ON, listening for wake word');
      _listenForWakeWord();
    }
  }

  void _listenForWakeWord() async {
    if (!_wakeWordMode) return;
    _addDebug('Initializing speech recognizer for wake word...');
    // Always re-initialize before listening for wake word again
    bool available = await _speech.initialize(
      onStatus: (status) {
        if (!_wakeWordMode) return;
        if (status == 'done' || status == 'notListening') {
          _addDebug('Wake word listening stopped by status: $status, restarting...');
          if (_wakeWordMode && !_wakeWordActive) {
            Future.delayed(const Duration(milliseconds: 200), _listenForWakeWord);
          }
        }
      },
      onError: (error) {
        _addDebug('Wake word listening error: "+${error.errorMsg}"');
        if (_wakeWordMode && !_wakeWordActive) {
          Future.delayed(const Duration(milliseconds: 200), _listenForWakeWord);
        }
      },
    );
    if (available) {
      _addDebug('Listening for wake word: "$_wakeWord" (continuous, no timeout)');
      await _speech.listen(
        listenMode: stt.ListenMode.dictation,
        onResult: (result) {
          if (!_wakeWordMode) return;
          final recognized = result.recognizedWords.toLowerCase();
          _addDebug('Wake word listen result: "$recognized"');
          if (!_wakeWordActive && recognized.contains(_wakeWord)) {
            // Wake word detected, start recording
            setState(() {
              _wakeWordActive = true;
            });
            _addDebug('Wake word detected! Starting transcription...');
            _controller.clear();
            _startWakeWordRecording();
          }
        },
        localeId: 'en_US',
        partialResults: true,
        // No listenFor: let it listen indefinitely for wake word
      );
    } else {
      _addDebug('Speech recognizer not available');
    }
  }

  void _startWakeWordRecording() async {
    if (!_wakeWordMode) return;
    DateTime start = DateTime.now();
    int maxDuration = _wakeWordMaxDuration;
    int silenceTimeout = _wakeWordSilenceTimeout;
    _addDebug('Transcribing started (wake word mode)');
    await _speech.listen(
      listenMode: stt.ListenMode.dictation,
      onResult: (result) {
        if (!_wakeWordMode) return;
        final now = DateTime.now();
        String recognized = result.recognizedWords;
        // Remove everything up to and including the first occurrence of the wake word (case-insensitive, word boundary)
        final wakeWordPattern = RegExp(r'(^|\b)' + RegExp.escape(_wakeWord) + r'\b', caseSensitive: false);
        final match = wakeWordPattern.firstMatch(recognized);
        if (match != null) {
          recognized = recognized.substring(match.end).trimLeft();
        }
        setState(() {
          // Always append to the latest text in the field
          String currentText = _controller.text;
          String newText = currentText.trim().isEmpty
              ? recognized
              : (currentText.trimRight() + (recognized.isNotEmpty ? ' ' : '') + recognized);
          _controller.text = newText.trimLeft();
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
        });
        _addDebug('Transcribing: "$recognized"');
        // Stop if max duration reached
        if (now.difference(start).inSeconds >= maxDuration) {
          _addDebug('Max duration reached, stopping transcription');
          _stopWakeWordRecording();
        }
      },
      localeId: 'en_US',
      partialResults: true,
      listenFor: Duration(seconds: maxDuration),
      pauseFor: Duration(seconds: silenceTimeout), // Only for transcription
      onSoundLevelChange: null,
      onDevice: false,
      cancelOnError: true,
    );
  }

  void _stopWakeWordRecording() async {
    await _speech.stop();
    setState(() {
      _wakeWordActive = false;
    });
    _addDebug('Transcribing stopped (wake word mode)');
    // Always resume listening for wake word if mode is still on
    if (_wakeWordMode) {
      _addDebug('Force re-initializing for wake word listening...');
      // Ensure recognizer is fully reset before listening again
      await Future.delayed(const Duration(milliseconds: 350));
      await _speech.cancel();
      await Future.delayed(const Duration(milliseconds: 150));
      _listenForWakeWord();
    }
  }
  // Wake word mode state
  bool _wakeWordMode = false;
  bool _wakeWordActive = false; // true when recording after wake word
  // ...existing code...
  int _wakeWordMaxDuration = 20;
  int _wakeWordSilenceTimeout = 2;
  String _wakeWord = 'Max';


  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  String? _feedbackMessage;

  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _lastRecognized = '';

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
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
                GestureDetector(
                  onTap: _isLoading ? null : _toggleWakeWordMode,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _wakeWordMode
                          ? const LinearGradient(
                              colors: [Color(0xFFB71C1C), Color(0xFF880808)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : const LinearGradient(
                              colors: [Color(0xFF6D5DF6), Color(0xFF3A3A6A)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      boxShadow: _wakeWordMode || _wakeWordActive
                          ? [
                              BoxShadow(
                                color: Colors.redAccent.withOpacity(0.6),
                                blurRadius: 32,
                                spreadRadius: 8,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: Colors.deepPurpleAccent.withOpacity(0.4),
                                blurRadius: 32,
                                spreadRadius: 4,
                                offset: const Offset(0, 8),
                              ),
                            ],
                      border: _wakeWordMode || _wakeWordActive
                          ? Border.all(color: Colors.redAccent, width: 4)
                          : null,
                    ),
                    child: Center(
                      child: Icon(
                        _wakeWordMode || _wakeWordActive ? Icons.hearing : Icons.bubble_chart_rounded,
                        size: 48,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                _buildTextInput(context),
                const SizedBox(height: 16),
                if (_isLoading) const CircularProgressIndicator(),
                if (_feedbackMessage != null && !_isLoading)
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                    child: Text(
                      _feedbackMessage!,
                      style: TextStyle(
                        color: _feedbackMessage!.startsWith('Message sent')
                            ? Colors.greenAccent
                            : Colors.redAccent,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
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
            enabled: !_isLoading && !_isListening && !_wakeWordActive,
          ),
        ),
        const SizedBox(width: 8),
        _buildMicButton(context),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.send_rounded),
          color: Theme.of(context).colorScheme.primary,
          onPressed: _controller.text.trim().isEmpty || _isLoading || _isListening || _wakeWordActive ? null : _sendText,
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
