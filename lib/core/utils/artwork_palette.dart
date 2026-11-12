import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 从专辑封面提取氛围色（Spotify 全屏播放器 / 迷你播放器的动态背景）。
///
/// 取色在 112px 缩略图上进行，结果按 URL 缓存；同一 URL 的并发请求会合并。
class ArtworkPalette {
  ArtworkPalette._();

  /// Widget 测试中图片永远不会加载，而 fromImageProvider 内部有 5 秒超时计时器，
  /// 会被判定为 pending timer，因此测试里需关闭取色。
  static bool enabled = true;

  static final Map<String, Color> _cache = {};
  static final Map<String, Future<Color?>> _pending = {};
  static int _generation = 0;
  static void clear() {
    _generation++;
    _cache.clear();
    _pending.clear();
  }

  static Color? cached(String url) => _cache[url];

  static Future<Color?> resolve(String url) {
    if (!enabled || url.isEmpty) return Future.value(null);
    final hit = _cache[url];
    if (hit != null) return Future.value(hit);

    // 回调必须是块体，否则会返回被移除的 Future 自身，导致 whenComplete 自我等待
    final generation = _generation;
    return _pending[url] ??= _extract(url, generation).whenComplete(() {
      if (generation == _generation) _pending.remove(url);
    });
  }

  static Future<Color?> _extract(String url, int generation) async {
    try {
      final scheme = await ColorScheme.fromImageProvider(
        provider: ResizeImage(
          CachedNetworkImageProvider(url),
          width: 112,
          height: 112,
        ),
        brightness: Brightness.dark,
      );
      final color = scheme.primaryContainer;
      if (generation == _generation) _cache[url] = color;
      return color;
    } catch (_) {
      return null;
    }
  }
}

/// 根据封面 URL 异步提供氛围色；取色完成前使用 [fallback]。
class ArtworkColorBuilder extends StatefulWidget {
  final String imageUrl;
  final Color fallback;
  final Widget Function(BuildContext context, Color color) builder;

  const ArtworkColorBuilder({
    super.key,
    required this.imageUrl,
    required this.fallback,
    required this.builder,
  });

  @override
  State<ArtworkColorBuilder> createState() => _ArtworkColorBuilderState();
}

class _ArtworkColorBuilderState extends State<ArtworkColorBuilder> {
  Color? _color;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(ArtworkColorBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) _resolve();
  }

  void _resolve() {
    final url = widget.imageUrl;
    _color = ArtworkPalette.cached(url) ?? _color;
    if (ArtworkPalette.cached(url) != null) return;
    ArtworkPalette.resolve(url).then((color) {
      if (!mounted || widget.imageUrl != url || color == null) return;
      setState(() => _color = color);
    });
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _color ?? widget.fallback);
}
