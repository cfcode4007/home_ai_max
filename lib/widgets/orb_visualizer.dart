import 'package:flutter/material.dart';

/// OrbVisualizer shows a glowing orb that animates when [isSpeaking] is true.
/// When [isListening] is true, the orb turns red and expands.
class OrbVisualizer extends StatefulWidget {
  final bool isSpeaking;
  final bool isListening;
  final double size;
  final VoidCallback? onTap;

  const OrbVisualizer({
    super.key,
    required this.isSpeaking,
    this.isListening = false,
    this.size = 120,
    this.onTap,
  });

  @override
  State<OrbVisualizer> createState() => _OrbVisualizerState();
}

class _OrbVisualizerState extends State<OrbVisualizer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..addListener(() => setState(() {}));
    if (widget.isSpeaking) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant OrbVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isActive = widget.isSpeaking || widget.isListening;
    if (isActive && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!isActive && _ctrl.isAnimating) {
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
    final isActive = widget.isSpeaking || widget.isListening;
    final displaySize = isActive ? size * 1.1 : size;

    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: displaySize,
        height: displaySize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Glowing orb background with subtle pulsate when speaking or listening
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: isActive ? displaySize * 1.03 : displaySize,
              height: isActive ? displaySize * 1.03 : displaySize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: widget.isListening
                    ? const LinearGradient(
                        colors: [Color(0xFFFF5252), Color(0xFF8B0000)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : const LinearGradient(
                        colors: [Color(0xFF7A6FF8), Color(0xFF2F2F55)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                boxShadow: [
                  BoxShadow(
                    color: widget.isListening
                        ? Color.fromARGB(((isActive ? 0.95 : 0.45) * 255).round(), 0xFF, 0x52, 0x52)
                        : Color.fromARGB(((isActive ? 0.95 : 0.45) * 255).round(), 0x7A, 0x6F, 0xF8),
                    blurRadius: isActive ? 48 : 26,
                    spreadRadius: isActive ? 8 : 4,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
            ),
            // Center icon
            Transform.scale(
              scale: isActive ? 1.05 : 1.0,
              child: Icon(
                widget.isListening ? Icons.mic : Icons.bubble_chart_rounded,
                size: 42,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
