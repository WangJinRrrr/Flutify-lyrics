import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutify_app/ui/widgets/marquee_text.dart';

const _pixelRatio = 3.25;
const _viewportWidth = 120.25;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader('MiSans')
      ..addFont(rootBundle.load('assets/fonts/MiSans/MiSans-Bold.ttf'));
    await loader.load();
  });

  for (final originX in [73.0, 73.25, 73.5, 73.75]) {
    final origin = Offset(originX, 10.25);
    testWidgets('mask covers complete physical pixels at origin $originX', (
      tester,
    ) async {
      final boundary = await _pumpMarquee(tester, origin);
      final viewport = tester.renderObject<RenderBox>(find.byType(MarqueeText));
      final viewportRect =
          viewport.localToGlobal(Offset.zero, ancestor: boundary) &
          viewport.size;
      final maskRects = _maskRectsInBoundary(boundary);
      expect(maskRects, hasLength(1));

      // Impeller's mask and hard clip need not rasterize a fractional boundary
      // identically. At 73dp * 3.25 = 237.25px, merely ending the shader at the
      // logical viewport can leave part of pixel 237 unmasked. Increasing a
      // gradient's transparent inset cannot cover pixels outside its maskRect.
      final mask = _physical(maskRects.single);
      final visible = _physical(viewportRect);
      expect(mask.left, lessThanOrEqualTo(visible.left.floorToDouble()));
      expect(mask.top, lessThanOrEqualTo(visible.top.floorToDouble()));
      expect(mask.right, greaterThanOrEqualTo(visible.right.ceilToDouble()));
      expect(mask.bottom, greaterThanOrEqualTo(visible.bottom.ceilToDouble()));
    });

    testWidgets('MiSans marquee keeps both edge strips clear at origin $originX', (
      tester,
    ) async {
      final boundary = await _pumpMarquee(tester, origin);
      final maxima = await tester.runAsync(() async {
        // Capture the ancestor, not the marquee itself: cropping at the marquee
        // would lose the fractional physical origin which triggers the native bug.
        final image = await boundary.toImage(pixelRatio: _pixelRatio);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        int brightest(double left, double right) {
          var maximum = 0;
          for (
            var x = (left * _pixelRatio).floor();
            x < (right * _pixelRatio).ceil();
            x++
          ) {
            for (var y = 0; y < image.height; y++) {
              maximum = math.max(
                maximum,
                bytes.getUint8((y * image.width + x) * 4),
              );
            }
          }
          return maximum;
        }

        final result = (
          brightest(origin.dx, origin.dx + 1),
          brightest(origin.dx + _viewportWidth - 1, origin.dx + _viewportWidth),
          brightest(origin.dx + 20, origin.dx + _viewportWidth - 20),
        );
        image.dispose();
        return result;
      });
      expect(maxima!.$1, 0);
      expect(maxima.$2, 0);
      expect(maxima.$3, greaterThan(200));
    });
  }
}

Future<RenderRepaintBoundary> _pumpMarquee(
  WidgetTester tester,
  Offset origin,
) async {
  final boundaryKey = GlobalKey();
  tester.view.devicePixelRatio = _pixelRatio;
  tester.view.physicalSize = const Size(1200, 2600);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: boundaryKey,
          child: SizedBox(
            width: 220,
            height: 50,
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                children: [
                  Positioned(
                    left: origin.dx,
                    top: origin.dy,
                    width: _viewportWidth,
                    child: const MarqueeText(
                      text: 'MMMMMMMM 测试标题渐隐边缘 WWWWWWWW 演示歌曲',
                      startDelay: Duration(milliseconds: 200),
                      edgeFadeInset: 4,
                      style: TextStyle(
                        fontFamily: 'MiSans',
                        fontSize: 14,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  return boundaryKey.currentContext!.findRenderObject()!
      as RenderRepaintBoundary;
}

List<Rect> _maskRectsInBoundary(RenderRepaintBoundary boundary) {
  final root = boundary.debugLayer! as OffsetLayer;
  final result = <Rect>[];
  void visit(ContainerLayer parent, Matrix4 transform) {
    for (
      var child = parent.firstChild;
      child != null;
      child = child.nextSibling
    ) {
      final childTransform = transform.clone();
      parent.applyTransform(child, childTransform);
      if (child is ShaderMaskLayer) {
        result.add(MatrixUtils.transformRect(childTransform, child.maskRect!));
      }
      if (child is ContainerLayer) visit(child, childTransform);
    }
  }

  // The capture is local to this boundary, so cancel its scene offset.
  visit(root, Matrix4.translationValues(-root.offset.dx, -root.offset.dy, 0));
  return result;
}

Rect _physical(Rect rect) => Rect.fromLTRB(
  rect.left * _pixelRatio,
  rect.top * _pixelRatio,
  rect.right * _pixelRatio,
  rect.bottom * _pixelRatio,
);
