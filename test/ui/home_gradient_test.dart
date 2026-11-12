import 'dart:ui' as ui;

import 'package:flutify_app/core/utils/artwork_palette.dart';
import 'package:flutify_app/l10n/l10n.dart';
import 'package:flutify_app/models/home_feed.dart';
import 'package:flutify_app/ui/screens/home/widgets/home_shortcuts_grid.dart';
import 'package:flutify_app/ui/screens/home/widgets/home_top_gradient.dart';
import 'package:flutify_app/ui/screens/home/widgets/home_chip_bar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 主页顶部渐变：随快捷入口悬停的封面取色变化（官方桌面端效果）。
void main() {
  setUp(() => ArtworkPalette.enabled = false);

  HomeItem shortcut(String title) => HomeItem(
    kind: HomeItemKind.playlist,
    uri: 'spotify:playlist:${title.hashCode}',
    title: title,
  );

  testWidgets('渐变颜色跟随 tint：有悬停色用悬停色，无悬停用主题色低透明度', (tester) async {
    final tint = ValueNotifier<Color?>(null);
    addTearDown(tint.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 300,
                child: HomeTopGradient(tint: tint),
              ),
            ],
          ),
        ),
      ),
    );

    BoxDecoration decoration() =>
        tester
                .widget<AnimatedContainer>(
                  find.descendant(
                    of: find.byType(HomeTopGradient),
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .decoration!
            as BoxDecoration;

    final defaultTop = (decoration().gradient! as LinearGradient).colors.first;

    tint.value = const Color(0xFF3366FF);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final hoverTop = (decoration().gradient! as LinearGradient).colors.first;
    expect(hoverTop, isNot(defaultTop));
    expect(
      hoverTop.red + hoverTop.blue,
      greaterThan(hoverTop.green),
      reason: '悬停色应来自封面主色',
    );

    tint.value = null;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect((decoration().gradient! as LinearGradient).colors.first, defaultTop);
  });

  testWidgets('悬停快捷入口上报封面取色（离开时报 null）', (tester) async {
    tester.view.physicalSize = const Size(1024, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final tints = <Color?>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              HomeShortcutsGrid(
                items: [shortcut('Alpha'), shortcut('Beta')],
                desktop: true,
                onHoverTint: tints.add,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    // 鼠标移入第一个条目：上报一次（取色关闭时为 null，但上报链路必须通）
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('Alpha')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tints, isNotEmpty, reason: '悬停应触发取色上报');

    // 移出网格：上报 null（渐变还原）
    await gesture.moveTo(const Offset(1000, 780));
    await tester.pump();
    expect(tints.last, isNull);
  });

  testWidgets(
    'pinned filter row paints the same gradient slice before and after scrolling',
    (tester) async {
      final tint = ValueNotifier<Color?>(const Color(0xff117744));
      final scroll = ScrollController();
      addTearDown(tint.dispose);
      addTearDown(scroll.dispose);
      final key = GlobalKey();
      const background = Color(0xfffafafa);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: background,
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: HomeTopGradient.extent,
                      child: HomeTopGradient(tint: tint),
                    ),
                    Positioned(
                      top: 48,
                      left: 0,
                      right: 400,
                      bottom: 0,
                      child: CustomScrollView(
                        controller: scroll,
                        slivers: [
                          HomeChipBar(
                            chips: const [],
                            selected: '',
                            onSelected: (_) {},
                            background: HomeTopGradient(
                              tint: tint,
                              topOffset: 48,
                              background: background,
                            ),
                          ),
                          const SliverToBoxAdapter(
                            child: SizedBox(
                              height: 1200,
                              child: ColoredBox(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> checkPixels() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          for (final y in [49, 65, 90]) {
            for (var channel = 0; channel < 4; channel++) {
              expect(
                bytes.getUint8((y * image.width + 2) * 4 + channel),
                closeTo(
                  bytes.getUint8((y * image.width + 600) * 4 + channel),
                  1,
                ),
                reason:
                    'header must match the page at y=$y, including while pinned',
              );
            }
          }
          image.dispose();
        });
      }

      await checkPixels();
      scroll.jumpTo(200);
      await tester.pumpAndSettle();
      await checkPixels();
      tint.value = const Color(0xff442299);
      await tester.pumpAndSettle();
      await checkPixels();
    },
  );
}
