import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 正在播放曲目的均衡器跳动动画。
///
/// 使用 CustomPainter 并把 AnimationController 作为 repaint 源：
/// 每帧只重绘，不触发 build / layout；暂停时停止 Ticker，零开销。
class WaveformVisualizer extends StatefulWidget {
  final bool isPlaying;
  final Color color;
  final double height;
  final int barCount;

  const WaveformVisualizer({
    super.key,
    required this.isPlaying,
    this.color = const Color(0xFF1ED760),
    this.height = 16.0,
    this.barCount = 4,
  });

  @override
  State<WaveformVisualizer> createState() => _WaveformVisualizerState();
}

class _WaveformVisualizerState extends State<WaveformVisualizer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isPlaying) _controller.repeat();
  }

  @override
  void didUpdateWidget(WaveformVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const barWidth = 3.0;
    const gap = 3.0;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(widget.barCount * barWidth + (widget.barCount - 1) * gap, widget.height),
        painter: _WaveformPainter(
          animation: _controller,
          color: widget.color,
          barCount: widget.barCount,
          barWidth: barWidth,
          gap: gap,
          active: widget.isPlaying,
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final Animation<double> animation;
  final Color color;
  final int barCount;
  final double barWidth;
  final double gap;
  final bool active;

  _WaveformPainter({
    required this.animation,
    required this.color,
    required this.barCount,
    required this.barWidth,
    required this.gap,
    required this.active,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final radius = Radius.circular(barWidth / 2);
    for (var i = 0; i < barCount; i++) {
      // 每根柱子相位错开，得到自然的起伏效果
      final phase = (animation.value * 2 * math.pi) + i * 1.7;
      final factor = active ? 0.3 + 0.7 * (0.5 + 0.5 * math.sin(phase * (1 + i * 0.15))) : 0.25;
      final h = size.height * factor;
      final x = i * (barWidth + gap);
      canvas.drawRRect(
        RRect.fromLTRBR(x, size.height - h, x + barWidth, size.height, radius),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.color != color || old.active != active || old.barCount != barCount;
}
