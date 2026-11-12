import 'dart:math' as math;
import 'dart:ui';

import 'desktop_lyric_model.dart';

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

  static const waiting = GlyphPose(opacity: 0, scale: 0.9, blur: 6);
  static const active = GlyphPose(opacity: 1, scale: 1, blur: 0);
  static const passed = GlyphPose(opacity: 0.76, scale: 0.98, blur: 0);

  @override
  bool operator ==(Object other) =>
      other is GlyphPose &&
      other.opacity == opacity &&
      other.scale == scale &&
      other.blur == blur;

  @override
  int get hashCode => Object.hash(opacity, scale, blur);
}

/// 桌面歌词的动效参数。
///
/// 呼吸、入场、离场和光晕是按 classic 歌词的观感自行取值的，
/// 没有搬用其他项目的关键帧表。
class LyricMotion {
  static const breathPeriod = Duration(milliseconds: 6400);
  static const breathAmplitude = 8.0;
  static const breathScale = 0.012;

  static const lineEnterPose = LinePose(opacity: 0, scale: 0.93, blur: 9);
  static const lineSettledPose = LinePose(opacity: 1, scale: 1, blur: 0);
  static const lineExitPose = LinePose(opacity: 0, scale: 1.06, blur: 13);

  /// [t] 为 0 到 1 的周期相位。向上为负。
  static double breathOffsetY(double t) =>
      math.sin(t * math.pi * 2) * breathAmplitude;

  static double breathScaleAt(double t) =>
      1 + math.sin(t * math.pi * 2) * breathScale;
}

/// 当前行点亮时，整行共用这一个姿态；提示文案没有可点亮的歌词。
List<GlyphPose> glyphPosesFor(DesktopLyricPresentation presentation) {
  if (!presentation.lightsWholeLine) return const [];
  return const [GlyphPose.active];
}

/// 强调色的两层光晕，再加一层深色投影，方便浮在任意壁纸上。
List<Shadow> lyricGlowShadows(Color emphasis) {
  final solid = emphasis.withAlpha(0xFF);
  return [
    Shadow(color: solid.withAlpha(230), blurRadius: 12),
    Shadow(color: solid.withAlpha(115), blurRadius: 28),
    const Shadow(
      color: Color(0xD9000000),
      offset: Offset(0, 3),
      blurRadius: 9,
    ),
  ];
}
