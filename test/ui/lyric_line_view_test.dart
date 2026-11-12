import 'package:flutify_app/ui/screens/player/lyrics/lyric_line_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 单行歌词的译文渲染：有译文时多一行小字，间奏不渲染译文。
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('译文在原文下方以小字渲染', (tester) async {
    await tester.pumpWidget(
      wrap(
        const LyricLineView(
          text: 'walking down the road',
          translation: '走在路上',
          distance: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('walking down the road'), findsOneWidget);
    expect(find.text('走在路上'), findsOneWidget);
    final original = tester.widget<Text>(find.text('walking down the road'));
    final translation = tester.widget<Text>(find.text('走在路上'));
    expect(
      translation.style?.fontSize,
      lessThan(original.style!.fontSize!),
      reason: '译文必须比原文小',
    );
  });

  testWidgets('间奏行只显示圆点，不渲染译文', (tester) async {
    await tester.pumpWidget(
      wrap(const LyricLineView(text: '', translation: '走在路上', distance: 0)),
    );
    await tester.pumpAndSettle();
    expect(find.text('走在路上'), findsNothing);
  });

  testWidgets('无译文时不渲染第二行', (tester) async {
    await tester.pumpWidget(
      wrap(const LyricLineView(text: 'walking down the road', distance: 0)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsNWidgets(1));
  });

  testWidgets('译文展开进度同步控制原文位置、透明度和行高', (tester) async {
    Future<void> show(double progress) async {
      await tester.pumpWidget(
        wrap(
          LyricLineView(
            text: 'walking down the road',
            translation: '走在路上\n寻找前方的方向',
            translationProgress: progress,
            distance: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(0);
    final collapsedY = tester.getTopLeft(find.text('walking down the road')).dy;
    final collapsedHeight = tester.getSize(find.byType(LyricLineView)).height;
    expect(find.text('走在路上\n寻找前方的方向'), findsNothing);
    await show(0.5);
    final intermediateHeight = tester
        .getSize(find.byType(LyricLineView))
        .height;
    expect(
      tester.getTopLeft(find.text('walking down the road')).dy,
      closeTo(collapsedY - 4.5, 0.01),
    );
    expect(
      tester.widget<Text>(find.text('走在路上\n寻找前方的方向')).style!.color!.a,
      closeTo(0.31, 0.01),
    );
    expect(
      find.ancestor(
        of: find.text('走在路上\n寻找前方的方向'),
        matching: find.byType(ClipRect),
      ),
      findsNothing,
      reason: '淡入时应保留完整字形，而不是裁出半截文字',
    );
    await show(1);
    final expandedHeight = tester.getSize(find.byType(LyricLineView)).height;
    expect(
      tester.getTopLeft(find.text('walking down the road')).dy,
      closeTo(collapsedY - 9, 0.01),
    );
    expect(
      intermediateHeight - collapsedHeight,
      closeTo((expandedHeight - collapsedHeight) * 0.5, 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('缺失译文和间奏不参与双语位移动画', (tester) async {
    for (final text in ['原文没有译词', '♪', '']) {
      await tester.pumpWidget(
        wrap(LyricLineView(text: text, translationProgress: 0, distance: 0)),
      );
      await tester.pumpAndSettle();
      final original = find.byType(Text);
      final collapsedY = tester.getTopLeft(original).dy;
      final collapsedHeight = tester.getSize(find.byType(LyricLineView)).height;
      await tester.pumpWidget(
        wrap(
          LyricLineView(
            text: text,
            translation: text == '原文没有译词' ? '  ' : '不应显示',
            translationProgress: 1,
            distance: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Text), findsOneWidget);
      expect(tester.getTopLeft(original).dy, collapsedY);
      expect(
        tester.getSize(find.byType(LyricLineView)).height,
        collapsedHeight,
      );
    }
  });
}
