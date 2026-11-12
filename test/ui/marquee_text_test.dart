import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutify_app/ui/widgets/marquee_text.dart';

void main() {
  test('uses a slower default speed and a four-second pause', () {
    const marquee = MarqueeText(text: 'Long title');

    expect(marquee.startDelay, const Duration(seconds: 4));
    expect(marquee.pixelsPerSecond, 30);
    expect(marquee.edgeFadeInset, 0);
  });

  for (final viewportWidth in [12.25, 120.25]) {
    testWidgets('inset mask preserves the title start at $viewportWidth', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: viewportWidth,
              child: const MarqueeText(
                text: 'A very long song title that needs room',
                edgeFadeInset: 2,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final maskFinder = find.bySubtype<ShaderMask>();
      Future<List<int>> edgeAlphas() async {
        final mask = tester.widget<ShaderMask>(maskFinder);
        final bounds = Offset.zero & tester.getSize(maskFinder);
        return (await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)..scale(3);
          canvas.drawRect(
            bounds,
            Paint()..shader = mask.shaderCallback(bounds),
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(
            (bounds.width * 3).ceil(),
            (bounds.height * 3).ceil(),
          );
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final middleRow = image.height ~/ 2;
          final alphas = [
            for (final column in [0, 1, image.width - 2, image.width - 1])
              bytes.getUint8((middleRow * image.width + column) * 4 + 3),
          ];
          image.dispose();
          picture.dispose();
          return alphas;
        }))!;
      }

      expect(await edgeAlphas(), [255, 255, 0, 0]);
      await tester.pump(const Duration(seconds: 6));
      expect(await edgeAlphas(), [0, 0, 0, 0]);
    });
  }

  testWidgets('keeps both edges covered while the title scrolls a full loop', (
    tester,
  ) async {
    // 真实合成：白字黑底经过 ShaderMask 后逐帧读取两端 1 逻辑像素的亮度。
    // 回归点：起步时左渐隐带不能随位移从 0 慢慢长出来（首字会硬切出左缘），
    // 收尾时也不能跟着尾字一起收窄（尾字会以不透明状态贴边移出）。
    const pixelRatio = 3.0;
    const gap = 40.0;
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: const ColoredBox(
              color: Colors.black,
              child: SizedBox(
                width: 120,
                child: MarqueeText(
                  text: 'A very long song title that needs room',
                  edgeFadeInset: 4,
                  gap: gap,
                  startDelay: Duration(milliseconds: 200),
                  style: TextStyle(fontSize: 14, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final controller = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
    final position = controller.position;
    final contentWidth =
        (position.maxScrollExtent + position.viewportDimension - gap) / 2;

    Future<(int, int)> edgeBrightness() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      return (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: pixelRatio);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final edge = pixelRatio.ceil();
        int brightest(int from, int to) {
          var value = 0;
          for (var x = from; x < to; x++) {
            for (var y = 0; y < image.height; y++) {
              final red = bytes.getUint8((y * image.width + x) * 4);
              if (red > value) value = red;
            }
          }
          return value;
        }

        final result = (
          brightest(0, edge),
          brightest(image.width - edge, image.width),
        );
        image.dispose();
        return result;
      }))!;
    }

    var previousOffset = 0.0;
    var checkedFrames = 0;
    while (true) {
      await tester.pump(const Duration(milliseconds: 16));
      final offset = controller.offset;
      if (offset < previousOffset) break; // 已回到下一轮起点
      previousOffset = offset;
      if (offset < 1) continue;

      final (left, right) = await edgeBrightness();
      // 第一份标题仍压在左缘上时，最外 1 逻辑像素必须完全遮住。
      if (offset <= contentWidth) {
        expect(left, 0, reason: 'left edge at offset $offset');
      }
      expect(right, 0, reason: 'right edge at offset $offset');
      checkedFrames++;
    }
    expect(previousOffset, greaterThan(contentWidth));
    expect(checkedFrames, greaterThan(100));
  });

  testWidgets('keeps a title that fits static', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 240,
            child: MarqueeText(
              text: 'Short title',
              style: TextStyle(fontSize: 14),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Short title'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MarqueeText),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
  });

  testWidgets('scrolls an overflowing title after the initial pause', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            child: MarqueeText(
              text: 'A very long song title that needs room',
              startDelay: Duration(milliseconds: 500),
              pixelsPerSecond: 100,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final scrollView = find.descendant(
      of: find.byType(MarqueeText),
      matching: find.byType(SingleChildScrollView),
    );
    expect(scrollView, findsOneWidget);
    expect(
      find.descendant(
        of: scrollView,
        matching: find.text('A very long song title that needs room'),
      ),
      findsNWidgets(2),
    );
    final scrollController = tester
        .widget<SingleChildScrollView>(scrollView)
        .controller!;
    expect(scrollController.offset, 0);

    await tester.pump(const Duration(milliseconds: 600));

    expect(scrollController.offset, greaterThan(0));
  });

  testWidgets('fades an overflowing title at both edges', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            child: MarqueeText(text: 'A very long song title that needs room'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(MarqueeText),
        matching: find.bySubtype<ShaderMask>(),
      ),
      findsOneWidget,
    );
  });

  testWidgets('does not animate when animations are disabled', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 120,
              child: MarqueeText(
                text: 'A very long song title that needs room',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(MarqueeText),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
  });
}
