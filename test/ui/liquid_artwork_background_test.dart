import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutify_app/ui/widgets/liquid_artwork_background.dart';

void main() {
  Widget host({required bool animate, bool tickers = true}) => MaterialApp(
    home: TickerMode(
      enabled: tickers,
      child: SizedBox.expand(
        child: LiquidArtworkBackground(
          imageUrl: '',
          fallback: Colors.indigo,
          animate: animate,
        ),
      ),
    ),
  );

  /// 只推进时间、不出帧，用于观察这段时间内是否有人预约了新帧。
  Future<bool> framesRequestedWithin(WidgetTester tester, Duration duration) async {
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.binding.delayed(duration);
    return tester.binding.hasScheduledFrame;
  }

  testWidgets('can remove an initially paused background without starting a ticker', (tester) async {
    await tester.pumpWidget(host(animate: false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('requests frames only when the phase advances, not every vsync', (tester) async {
    await tester.pumpWidget(host(animate: true));
    // 两次相位更新之间没有预约中的帧：高刷屏上不会每个 vsync 都整窗重绘
    expect(await framesRequestedWithin(tester, const Duration(milliseconds: 5)), isFalse);
    // 约 1/30 秒后相位前进，才预约下一帧
    expect(await framesRequestedWithin(tester, const Duration(milliseconds: 40)), isTrue);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('stops when paused or when tickers are muted, and resumes', (tester) async {
    await tester.pumpWidget(host(animate: true));
    expect(await framesRequestedWithin(tester, const Duration(milliseconds: 40)), isTrue);

    await tester.pumpWidget(host(animate: false));
    expect(await framesRequestedWithin(tester, const Duration(milliseconds: 100)), isFalse);

    await tester.pumpWidget(host(animate: true, tickers: false));
    expect(await framesRequestedWithin(tester, const Duration(milliseconds: 100)), isFalse);

    await tester.pumpWidget(host(animate: true));
    expect(await framesRequestedWithin(tester, const Duration(milliseconds: 40)), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
