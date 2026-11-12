import 'package:flutify_app/ui/widgets/marquee_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a long title requests no frames while it rests before scrolling', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            child: MarqueeText(text: 'A very long track title that has to scroll across the bar'),
          ),
        ),
      ),
    );
    // 测量与配置各占一帧
    await tester.pump();
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);

    // 静止期内画面不变，不应逐帧重绘
    await tester.binding.delayed(const Duration(seconds: 3));
    expect(tester.binding.hasScheduledFrame, isFalse);

    // 静止结束后开始滚动，持续出帧
    await tester.binding.delayed(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
