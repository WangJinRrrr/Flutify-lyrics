import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 统一的封面/头像图片组件。
///
/// 性能要点：按实际显示尺寸 × 设备像素比设置 memCacheWidth，
/// 让 44dp 的缩略图不再解码整张 600px 原图，显著降低内存与解码耗时。
class CoverImage extends StatelessWidget {
  final String url;

  /// 显示边长（dp）。为空时通过 LayoutBuilder 取父约束宽度。
  final double? size;
  final BorderRadius? borderRadius;
  final bool circular;
  final IconData placeholderIcon;

  const CoverImage({
    super.key,
    required this.url,
    this.size,
    this.borderRadius,
    this.circular = false,
    this.placeholderIcon = Icons.music_note_rounded,
  });

  @override
  Widget build(BuildContext context) {
    Widget child = size != null
        ? SizedBox(width: size, height: size, child: _buildImage(context, size))
        : LayoutBuilder(
            builder: (context, constraints) => _buildImage(
              context,
              constraints.maxWidth.isFinite ? constraints.maxWidth : null,
            ),
          );

    if (circular) {
      child = ClipOval(child: child);
    } else if (borderRadius != null) {
      child = ClipRRect(borderRadius: borderRadius!, child: child);
    }
    return child;
  }

  Widget _buildImage(BuildContext context, double? logicalWidth) {
    final colorScheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colorScheme.surfaceContainerHigh,
      child: Center(
        child: Icon(
          placeholderIcon,
          color: colorScheme.onSurfaceVariant.withAlpha(120),
        ),
      ),
    );

    if (url.isEmpty) return placeholder;

    // 淡入由 Ticker 驱动。封面所在子树被 TickerMode 暂停时（例如歌词视图里的小封面），
    // 淡入动画停在透明、旧图又立刻移除，换歌后就只剩深色占位。暂停时直接显示新图。
    final fadeIn = TickerMode.valuesOf(context).enabled
        ? const Duration(milliseconds: 150)
        : Duration.zero;

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: _cacheWidth(context, logicalWidth),
      fadeInDuration: fadeIn,
      fadeOutDuration: Duration.zero,
      placeholder: (_, _) =>
          ColoredBox(color: colorScheme.surfaceContainerHigh),
      errorWidget: (_, _, _) => placeholder,
    );
  }

  /// 只限制宽度以保持宽高比；乘 1.5 余量，保证非正方形图片在 BoxFit.cover
  /// 裁切后依旧清晰。结果按 64px 取整，减少同一张图的缓存变体数量。
  int? _cacheWidth(BuildContext context, double? logicalWidth) {
    if (logicalWidth == null || logicalWidth <= 0) return null;
    final px = logicalWidth * MediaQuery.devicePixelRatioOf(context) * 1.5;
    return ((px / 64).ceil() * 64);
  }
}
