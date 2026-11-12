import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 主页顶部渐变（官方桌面端效果）：顶部一团柔和的色彩铺底，随悬停的卡片封面取色变化。
///
/// 只是背景装饰：由父级 `Positioned` 固定在内容顶部（不随滚动），盖在 Scaffold 背景之上、
/// 卡片之下；颜色变化用 [AnimatedContainer] 平滑过渡；无悬停时用主题色的低透明度铺底。
class HomeTopGradient extends StatelessWidget {
  /// 悬停封面的主色；null 表示没有悬停（用默认铺底色）。
  final ValueListenable<Color?> tint;
  static const double extent = 360;

  /// 吸顶栏重绘其所在的渐变切片，遮住滚动内容且与页面背景连续。
  final double topOffset;
  final Color? background;

  const HomeTopGradient({
    super.key,
    required this.tint,
    this.topOffset = 0,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<Color?>(
      valueListenable: tint,
      builder: (context, color, _) {
        final top = (color ?? colorScheme.primary).withAlpha(
          color == null ? 30 : 64,
        );
        Color sample(double offset) {
          final tint = Color.lerp(
            top,
            top.withAlpha(0),
            (offset / extent).clamp(0, 1),
          )!;
          return background == null
              ? tint
              : Color.alphaBlend(tint, background!);
        }

        return IgnorePointer(
          child: LayoutBuilder(
            builder: (context, constraints) => AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    sample(topOffset),
                    sample(topOffset + constraints.maxHeight),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
