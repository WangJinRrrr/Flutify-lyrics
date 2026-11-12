import 'package:flutify_app/l10n/app_localizations.dart';
import 'package:flutify_app/providers/auth_provider.dart';
import 'package:flutify_app/ui/navigation/content_history.dart';
import 'package:flutify_app/ui/shell/desktop/desktop_top_bar.dart';
import 'package:flutify_app/ui/shell/desktop/desktop_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _SignedOutAuth extends Fake with ChangeNotifier implements AuthProvider {
  @override
  bool get isSignedIn => false;
  @override
  String get displayName => '';
  @override
  String get username => '';
  @override
  String get avatarUrl => '';
}

void main() {
  const channel = MethodChannel('window_manager');
  final desktopPlatforms = TargetPlatformVariant({
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  });
  final calls = <String>[];
  var maximized = false;
  late TextEditingController controller;
  late FocusNode focus;
  late ContentHistory history;

  setUp(() {
    DesktopWindow.debugEnabledOverride = true;
    controller = TextEditingController(text: '残酷月光 cruel moonlight');
    focus = FocusNode();
    history = ContentHistory();
    calls.clear();
    maximized = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'isMaximized') return maximized;
          if (call.method == 'isFullScreen') return false;
          if (call.method == 'maximize') maximized = true;
          if (call.method == 'unmaximize') maximized = false;
          return null;
        });
  });

  tearDown(() {
    DesktopWindow.debugEnabledOverride = null;
    DesktopWindow.debugMacNativeWindowOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    controller.dispose();
    focus.dispose();
    history.dispose();
  });

  Future<void> pumpBar(WidgetTester tester, {double width = 1280}) async {
    DesktopWindow.debugMacNativeWindowOverride =
        defaultTargetPlatform == TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(Size(width, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => _SignedOutAuth(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: DesktopTopBar(
                history: history,
                homeSelected: true,
                onHome: () {},
                searchController: controller,
                searchFocus: focus,
                onSearchChanged: (_) {},
                onSearchSubmitted: (_) {},
                onSearchActivated: () {},
                onOpenSettings: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'mouse selection in search never starts a window drag',
    (tester) async {
      await pumpBar(tester);
      final field = tester.getRect(find.byType(TextField));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: field.centerLeft + const Offset(8, 0));
      addTearDown(mouse.removePointer);
      await mouse.down(field.centerLeft + const Offset(8, 0));
      await tester.pump(const Duration(milliseconds: 100));
      await mouse.moveBy(const Offset(1, 25));
      await tester.pump(const Duration(milliseconds: 50));
      await mouse.moveBy(const Offset(100, 0));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(calls, isNot(contains('startDragging')));
      expect(controller.selection.isValid, isTrue);
      expect(controller.selection.isCollapsed, isFalse);
    },
    variant: desktopPlatforms,
  );

  testWidgets(
    'blank title bar still drags and double-clicks to maximize and restore',
    (tester) async {
      await pumpBar(tester);
      const blank = Offset(260, 28);
      await tester.dragFrom(
        blank,
        const Offset(80, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(calls.where((m) => m == 'startDragging'), hasLength(1));
      calls.clear();
      await tester.tapAt(blank, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(blank, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(calls, contains('maximize'));
      await tester.pump(const Duration(milliseconds: 500));
      calls.clear();
      await tester.tapAt(blank, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(blank, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(calls, ['isMaximized', 'unmaximize']);
    },
    variant: desktopPlatforms,
  );

  testWidgets('search padding does not drag the window', (tester) async {
    await pumpBar(tester);
    final field = tester.getRect(find.byType(TextField));
    // The visible 40px search capsule extends above the text's hit area.
    await tester.dragFrom(
      Offset(field.left + 8, 10),
      const Offset(80, 8),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(calls, isNot(contains('startDragging')));
  }, variant: desktopPlatforms);

  testWidgets(
    'double-clicking search selects a word without maximizing',
    (tester) async {
      await pumpBar(tester);
      final field = tester.getRect(find.byType(TextField));
      final point = field.centerLeft + const Offset(8, 0);
      await tester.tapAt(point, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(point, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(controller.selection.isCollapsed, isFalse);
    },
    variant: desktopPlatforms,
  );

  testWidgets(
    'search decoration and clear button never start a window drag',
    (tester) async {
      await pumpBar(tester);
      for (final icon in [Icons.search_rounded, Icons.close_rounded]) {
        await tester.drag(
          find.byIcon(icon),
          const Offset(40, 30),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
      }
      expect(calls, isEmpty);
      await tester.tap(
        find.byIcon(Icons.close_rounded),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(controller.text, isEmpty);
      expect(focus.hasFocus, isTrue);
      expect(calls, isEmpty);
    },
    variant: desktopPlatforms,
  );

  testWidgets(
    'a vertical mouse drag inside search never moves the window',
    (tester) async {
      await pumpBar(tester);
      await tester.drag(
        find.byType(TextField),
        const Offset(0, 40),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
    },
    variant: desktopPlatforms,
  );

  for (final width in [800.0, 1360.0]) {
    testWidgets(
      'macOS blank titlebar regions remain draggable at width $width',
      (tester) async {
        await pumpBar(tester, width: width);
        final field = tester.getRect(find.byType(TextField));
        final home = tester.getRect(
          find.widgetWithIcon(IconButton, Icons.home_filled),
        );
        for (final point in [
          const Offset(90, 28),
          Offset(field.center.dx, 4),
          Offset(field.center.dx, 52),
          Offset(home.left - 8, 28),
          Offset(width - 8, 28),
        ]) {
          calls.clear();
          await tester.dragFrom(
            point,
            const Offset(30, 20),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pumpAndSettle();
          // window_manager 在 Windows 主机上拖动前先查一次全屏（isFullScreen 保护），
          // 与 TargetPlatform 变体无关；除它之外不应有 maximize 等其它调用。
          expect(
            calls.where((m) => m == 'startDragging'),
            hasLength(1),
            reason: 'blank area at $point',
          );
          expect(
            calls.where((m) => m != 'isFullScreen'),
            ['startDragging'],
            reason: 'blank area at $point',
          );
        }
        expect(tester.getSize(find.byType(DesktopTopBar)).height, 56);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'disabled desktop integration makes no native calls',
    (tester) async {
      DesktopWindow.debugEnabledOverride = false;
      await pumpBar(tester);
      await tester.dragFrom(
        const Offset(90, 28),
        const Offset(30, 20),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
