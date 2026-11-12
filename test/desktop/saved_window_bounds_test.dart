import 'package:flutify_app/ui/shell/desktop/saved_window_bounds.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// 窗口位置记忆：解析容错，以及显示器变化后窗口是否还能找回。
void main() {
  const minimum = Size(400, 600);

  test('encode / decode round-trips position, size and maximized state', () {
    const bounds = SavedWindowBounds(Rect.fromLTWH(120, 80, 1280, 820), maximized: true);
    final decoded = SavedWindowBounds.decode(bounds.encode(), minimumSize: minimum)!;
    expect(decoded.rect, bounds.rect);
    expect(decoded.maximized, isTrue);
  });

  test('invalid or too-small data is ignored', () {
    expect(SavedWindowBounds.decode('', minimumSize: minimum), isNull);
    expect(SavedWindowBounds.decode('oops', minimumSize: minimum), isNull);
    expect(SavedWindowBounds.decode('{"x":0,"y":0,"w":"wide","h":700}', minimumSize: minimum), isNull);
    expect(SavedWindowBounds.decode('{"x":0,"y":0,"w":300,"h":700}', minimumSize: minimum), isNull);
  });

  test('reachable only when the title bar grip lies on some display', () {
    const primary = Rect.fromLTWH(0, 0, 1920, 1080);
    const secondary = Rect.fromLTWH(1920, 0, 2560, 1440);

    const onPrimary = SavedWindowBounds(Rect.fromLTWH(100, 100, 1200, 800));
    const onSecondary = SavedWindowBounds(Rect.fromLTWH(2400, 200, 1200, 800));
    // 标题栏在屏幕上方之外：即使窗口下半部分可见也拖不回来
    const aboveScreen = SavedWindowBounds(Rect.fromLTWH(100, -400, 1200, 800));

    expect(onPrimary.isReachableOn([primary]), isTrue);
    expect(onSecondary.isReachableOn([primary, secondary]), isTrue);
    expect(onSecondary.isReachableOn([primary]), isFalse, reason: '副屏拔掉后应回到默认居中');
    expect(aboveScreen.isReachableOn([primary, secondary]), isFalse);
  });
}
