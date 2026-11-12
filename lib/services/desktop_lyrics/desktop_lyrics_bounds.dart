import 'dart:convert';

/// 桌面歌词窗口的位置和大小，存在偏好键 [storageKey]。
class DesktopLyricsBounds {
  static const storageKey = 'ui_desktop_lyrics_bounds';

  final double x;
  final double y;
  final double width;
  final double height;

  const DesktopLyricsBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  static const double minWidth = 280;
  static const double minHeight = 96;

  String encode() => jsonEncode({
    'x': x,
    'y': y,
    'w': width,
    'h': height,
  });

  /// 空串、损坏、非有限数或尺寸过小都返回 null，调用方改用默认位置。
  static DesktopLyricsBounds? decode(String raw) {
    if (raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final values = [json['x'], json['y'], json['w'], json['h']];
      if (values.any((value) => value is! num || !value.isFinite)) return null;
      final numbers = values.cast<num>().map((value) => value.toDouble()).toList();
      final bounds = DesktopLyricsBounds(
        x: numbers[0],
        y: numbers[1],
        width: numbers[2],
        height: numbers[3],
      );
      if (bounds.width < minWidth || bounds.height < minHeight) return null;
      return bounds;
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DesktopLyricsBounds &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);
}
