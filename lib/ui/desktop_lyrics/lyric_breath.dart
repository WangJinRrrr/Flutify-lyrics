import 'package:flutter/widgets.dart';

import '../../services/desktop_lyrics/desktop_lyric_motion.dart';

/// 整行歌词的缓慢呼吸。暂停时停在当前姿态，不回到原点。
class LyricBreath extends StatefulWidget {
  final bool paused;
  final Widget child;

  const LyricBreath({super.key, required this.paused, required this.child});

  @override
  State<LyricBreath> createState() => _LyricBreathState();
}

class _LyricBreathState extends State<LyricBreath>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: LyricMotion.breathPeriod,
  );

  @override
  void initState() {
    super.initState();
    if (!widget.paused) _controller.repeat();
  }

  @override
  void didUpdateWidget(LyricBreath oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.paused == oldWidget.paused) return;
    if (widget.paused) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        return Transform.translate(
          offset: Offset(0, LyricMotion.breathOffsetY(t)),
          child: Transform.scale(
            scale: LyricMotion.breathScaleAt(t),
            child: child,
          ),
        );
      },
    );
  }
}
