import 'dart:math';

import 'package:flutter/material.dart';

/// OrbVisualizer shows a glowing orb that animates with vertical bars when
/// [isSpeaking] is true. Bars are simulated (randomized) to give a convincing
/// audio-visual effect without analyzing real audio.
class OrbVisualizer extends StatefulWidget {
  final bool isSpeaking;
  final double size;

  const OrbVisualizer({super.key, required this.isSpeaking, this.size = 120});

  @override
  State<OrbVisualizer> createState() => _OrbVisualizerState();
}

class _OrbVisualizerState extends State<OrbVisualizer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final Random _rng = Random();

  static const int _bars = 9;
  late final List<double> _phases;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..addListener(() => setState(() {}));
    _phases = List.generate(_bars, (i) => _rng.nextDouble() * pi * 2);
    if (widget.isSpeaking) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant OrbVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSpeaking && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.isSpeaking && _ctrl.isAnimating) {
      // ease out and stop
      _ctrl.animateTo(0.0, duration: const Duration(milliseconds: 400)).then((_) => _ctrl.stop());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glowing orb background with subtle pulsate when speaking
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: widget.isSpeaking ? size * 1.03 : size,
            height: widget.isSpeaking ? size * 1.03 : size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF7A6FF8), Color(0xFF2F2F55)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Color.fromARGB(((widget.isSpeaking ? 0.95 : 0.45) * 255).round(), 0x7A, 0x6F, 0xF8),
                  blurRadius: widget.isSpeaking ? 48 : 26,
                  spreadRadius: widget.isSpeaking ? 8 : 4,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
          ),
          // Bars overlay
          SizedBox(
            width: size * 0.82,
            height: size * 0.62,
            child: CustomPaint(
              painter: _BarsPainter(_bars, _ctrl.value, _phases, _rng, widget.isSpeaking),
            ),
          ),
          // Center icon
          Transform.scale(
            scale: widget.isSpeaking ? 1.05 : 1.0,
            child: const Icon(Icons.bubble_chart_rounded, size: 42, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final int barCount;
  final double t;
  final List<double> phases;
  final Random rng;
  final bool active;

  _BarsPainter(this.barCount, this.t, this.phases, this.rng, this.active);

  @override
  void paint(Canvas canvas, Size size) {
  final paint = Paint()..color = Color.fromARGB(((active ? 0.95 : 0.7) * 255).round(), 255, 255, 255);
    final barWidth = size.width / (barCount * 1.9);
    final gap = barWidth * 0.7;
    final baseY = size.height;
    for (int i = 0; i < barCount; i++) {
      final x = i * (barWidth + gap);
      final phase = phases[i % phases.length];
      final wave = sin(t * 2 * pi + phase) * 0.5 + 0.5; // 0..1
      final dynamicFactor = 0.25 + wave * 0.75;
      final jitter = active ? (rng.nextDouble() * 0.18) : 0.0;
      final heightFactor = (0.18 + dynamicFactor * (0.82 + jitter)).clamp(0.0, 1.0);
      final barHeight = baseY * heightFactor;
      final rect = Rect.fromLTWH(x, baseY - barHeight, barWidth, barHeight);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter oldDelegate) => true;
}
