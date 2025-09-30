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

  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  String? _feedbackMessage;

  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _lastRecognized = '';

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
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
      final webhookUrl = await ConfigManager.getWebhookUrl();
      final response = await http.post(
        Uri.parse(webhookUrl),
        headers: headers,
        body: encodedBody,
      ).timeout(const Duration(seconds: 5));
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
      await _speech.stop();
      setState(() {
        _isListening = false;
      });
    } else {
      bool available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            setState(() {
              _isListening = false;
            });
          }
        },
        onError: (error) {
          setState(() {
            _isListening = false;
          });
        },
      );
      if (available) {
        setState(() {
          _isListening = true;
          _controller.clear();
        });
        _speech.listen(
          onResult: (result) {
            setState(() {
              _lastRecognized = result.recognizedWords;
              _controller.text = _lastRecognized;
              _controller.selection = TextSelection.fromPosition(
                TextPosition(offset: _controller.text.length),
              );
            });
          },
          localeId: 'en_US',
        );
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
                const OrbWidget(),
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

class OrbWidget extends StatelessWidget {
  const OrbWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF6D5DF6), Color(0xFF3A3A6A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurpleAccent.withOpacity(0.4),
            blurRadius: 32,
            spreadRadius: 4,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.bubble_chart_rounded,
          size: 48,
          color: Colors.white.withOpacity(0.85),
        ),
      ),
    );
  }
}
