import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/md3e_colors.dart';

/// Flutify 品牌标：连续曲率圆角方块（superellipse）+ 薄荷 → 品牌绿 → 深青绿三段对角渐变
/// （叠左上径向光泽）+ 白色均衡器声波字形（三条全圆角竖波，中条最高）。
///
/// 与应用图标同一套比例：母版见 `tool/brand/generate_logo.py`（生成 `assets/brand/flutify_logo.svg`
/// 及各平台图标），改几何时两处一起改。纯矢量绘制，任意尺寸清晰；[glow] 为登录页添加柔和的品牌色光晕。
class FlutifyMark extends StatelessWidget {
  final double size;
  final bool glow;

  const FlutifyMark({super.key, this.size = 72, this.glow = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: MD3EColors.spotifyGreen.withAlpha(70),
                  blurRadius: size * 0.6,
                  spreadRadius: -size * 0.12,
                  offset: Offset(0, size * 0.18),
                ),
              ]
            : null,
      ),
      child: CustomPaint(painter: _MarkPainter()),
    );
  }
}

class _MarkPainter extends CustomPainter {
  // 与 generate_logo.py 保持一致的几何（边长为 1）
  static const _greenMint = Color(0xFF63EA8E);
  static const _greenBrand = Color(0xFF1ED760);
  static const _greenDeep = Color(0xFF0B7A3E);
  static const _n = 5.0;
  static const _t = 0.105;
  static const _barXs = [0.32, 0.50, 0.68];
  static const _barTops = [0.355, 0.240, 0.320];
  static const _barBots = [0.645, 0.760, 0.680];

  /// superellipse |x|^n + |y|^n = 1 的轮廓（n = 5，接近 iOS 图标的连续曲率圆角）。
  static Path _plate(double s) {
    const steps = 160;
    final path = Path();
    final c = s / 2;
    for (var i = 0; i < steps; i++) {
      final a = 2 * math.pi * i / steps;
      final ca = math.cos(a), sa = math.sin(a);
      final x = c + c * ca.sign * math.pow(ca.abs(), 2 / _n);
      final y = c + c * sa.sign * math.pow(sa.abs(), 2 / _n);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final rect = Offset.zero & size;

    final plate = _plate(s);
    canvas.drawPath(
      plate,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_greenMint, _greenBrand, _greenDeep],
          stops: [0.0, 0.52, 1.0],
        ).createShader(rect),
    );

    // 左上径向光泽 + 顶部高光描边，增加立体感
    canvas.drawPath(
      plate,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.64, -0.8),
          radius: 0.9,
          colors: [Colors.white.withAlpha(41), Colors.white.withAlpha(0)],
        ).createShader(rect),
    );
    canvas.drawPath(
      plate,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, s * 0.012)
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [Colors.white.withAlpha(80), Colors.white.withAlpha(0)],
        ).createShader(rect),
    );

    // 字形：三条全圆角均衡器声波（中条最高，左右起伏）
    final ink = Paint()..color = Colors.white;
    final r = Radius.circular(_t / 2 * s);
    for (var i = 0; i < 3; i++) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          (_barXs[i] - _t / 2) * s,
          _barTops[i] * s,
          (_barXs[i] + _t / 2) * s,
          _barBots[i] * s,
          r,
        ),
        ink,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
