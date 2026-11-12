import 'dart:ui';

import 'desktop_lyric_model.dart';

// Animation numbers below are copied from Folia-major (AGPL-3.0-only),
// https://github.com/chthollyphile/folia-major
// commit a44758bbc02929225ca7304b5a4c4580d7b4e87b
//
//   src/components/visualizer/classic/Visualizer.tsx
//     lyricContainerFloat, animationIntensity "normal", breathingFloatMultiplier 1
//   src/components/visualizer/glowWordTiming.ts
//     getGlowWordLineContainerMotion, default lineTransitionMode
//   src/components/visualizer/glowWordVariants.ts
//     GLOW_WORD_ACTIVE_SCALE and the active/passed body opacity
//   src/components/visualizer/wordGlow.ts
//     glowRadii for the default reveal mode: [20, 40]
//
// Only these lyric-style numbers are included. No other Folia-major code is vendored.
// This file is a derivative of those AGPL-3.0 sources. The rest of this
// repository stays under the MIT license in ../../LICENSE; see NOTICE.

/// 一行歌词的容器姿态：透明度、缩放、模糊。
class LinePose {
  final double opacity;
  final double scale;
  final double blur;

  const LinePose({
    required this.opacity,
    required this.scale,
    required this.blur,
  });

  LinePose lerp(LinePose other, double t) {
    return LinePose(
      opacity: opacity + (other.opacity - opacity) * t,
      scale: scale + (other.scale - scale) * t,
      blur: blur + (other.blur - blur) * t,
    );
  }
}

/// 整行作为一个字形时的姿态。没有逐字时间，所以一行只会有一个姿态。
class GlyphPose {
  final double opacity;
  final double scale;
  final double blur;

  const GlyphPose({
    required this.opacity,
    required this.scale,
    required this.blur,
  });

  /// glowWordVariants.ts waiting / active / passed, plus GLOW_WORD_ACTIVE_SCALE.
  static const waiting = GlyphPose(opacity: 0, scale: 0.5, blur: 10);
  static const active = GlyphPose(opacity: 1, scale: 1.4, blur: 0);
  static const passed = GlyphPose(opacity: 0.82, scale: 1, blur: 0);

  @override
  bool operator ==(Object other) =>
      other is GlyphPose &&
      other.opacity == opacity &&
      other.scale == scale &&
      other.blur == blur;

  @override
  int get hashCode => Object.hash(opacity, scale, blur);
}

/// Folia-major classic 歌词动效参数。见文件头的来源说明。
class LyricMotion {
  /// lyricContainerFloat normal duration, in seconds.
  static const breathPeriod = Duration(milliseconds: 7000);

  /// normal distance 14 * breathingFloatMultiplier 1.
  static const breathDistance = 14.0;

  /// y keyframes: [0, -distance, 0, distance * 0.45, 0]
  static const breathOffsetKeys = <double>[0, -14, 0, 6.3, 0];

  /// scale keyframes: [1, 1 + 0.01 * multiplier, 1, 1 - 0.005 * multiplier, 1]
  static const breathScaleKeys = <double>[1, 1.01, 1, 0.995, 1];

  /// getGlowWordLineContainerMotion default initial / animate / exit.
  static const lineEnterPose = LinePose(opacity: 0, scale: 0.9, blur: 10);
  static const lineSettledPose = LinePose(opacity: 1, scale: 1, blur: 0);
  static const lineExitPose = LinePose(opacity: 0, scale: 1.1, blur: 20);

  /// exit transition duration 0.3s. The enter tween has no explicit duration,
  /// so it uses the same 0.3s framer-motion default.
  static const lineMoveDuration = Duration(milliseconds: 300);

  /// wordGlow.ts glowRadii default: inner 20, outer 40.
  static const glowInnerRadius = 20.0;
  static const glowOuterRadius = 40.0;

  /// Framer Motion's easeInOut is cubic-bezier(0.42, 0, 0.58, 1).
  static double easeInOut(double t) => _cubicBezier(0.42, 0, 0.58, 1, t);

  static double breathOffsetY(double t) =>
      _sampleLoop(breathOffsetKeys, easeInOut(t));

  static double breathScaleAt(double t) =>
      _sampleLoop(breathScaleKeys, easeInOut(t));
}

double _sampleLoop(List<double> keys, double t) {
  if (keys.isEmpty) return 0;
  if (keys.length == 1) return keys.first;
  final clamped = t.clamp(0.0, 1.0);
  final scaled = clamped * (keys.length - 1);
  final index = scaled.floor().clamp(0, keys.length - 2);
  final local = scaled - index;
  return keys[index] + (keys[index + 1] - keys[index]) * local;
}

/// Solve y for cubic-bezier(x1, y1, x2, y2) at time [t].
double _cubicBezier(double x1, double y1, double x2, double y2, double t) {
  var guess = t.clamp(0.0, 1.0);
  for (var i = 0; i < 8; i++) {
    final x = _bezierComponent(guess, x1, x2) - t;
    final dx = _bezierSlope(guess, x1, x2);
    if (dx.abs() < 1e-6) break;
    guess = (guess - x / dx).clamp(0.0, 1.0);
  }
  return _bezierComponent(guess, y1, y2);
}

double _bezierComponent(double t, double a, double b) {
  final u = 1 - t;
  return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t;
}

double _bezierSlope(double t, double a, double b) {
  final u = 1 - t;
  return 3 * u * u * a + 6 * u * t * (b - a) + 3 * t * t * (1 - b);
}

/// 当前行点亮时，整行共用这一个姿态；提示文案没有可点亮的歌词。
List<GlyphPose> glyphPosesFor(DesktopLyricPresentation presentation) {
  if (!presentation.lightsWholeLine) return const [];
  return const [GlyphPose.active];
}

/// wordGlow.ts text-shadow: `0 0 20px color, 0 0 40px color`.
List<Shadow> lyricGlowShadows(Color emphasis) {
  final solid = emphasis.withAlpha(0xFF);
  return [
    Shadow(color: solid, blurRadius: LyricMotion.glowInnerRadius),
    Shadow(color: solid, blurRadius: LyricMotion.glowOuterRadius),
  ];
}
