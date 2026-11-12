import 'package:flutify_app/l10n/app_localizations.dart';
import 'package:flutify_app/models/share_target.dart';
import 'package:flutify_app/ui/widgets/share/share_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 分享面板：
/// - 手机底部面板 / 桌面对话框在各宽度、默认与最大字号下都不溢出；
/// - 复制链接 / URI / 嵌入代码写入剪贴板，按钮就地显示「已复制」后恢复；
/// - 嵌入选项（紧凑 / 深色）同步改变代码。
void main() {
  const target = ShareTarget(
    kind: ShareKind.playlist,
    id: '37i9dQZF1DXcBWIGoYBM5M',
    title: '一个非常非常长的歌单名称，用来测试标题在窄屏下的省略与换行表现 Today’s Top Hits',
    subtitle: 'Spotify',
  );

  String? clipboard;

  setUp(() {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData')
            clipboard = (call.arguments as Map)['text'] as String;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// 打开面板：一个按钮触发 [ShareSheet.show]，按窗口宽度自动选择底部面板或对话框。
  Future<void> open(
    WidgetTester tester,
    Size size, {
    double fontScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        key: ValueKey('$size-$fontScale'),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(fontScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => ShareSheet.show(context, target),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  for (final fontScale in const [1.0, 1.3]) {
    testWidgets(
      'share sheet: no overflow across sizes (font ${(fontScale * 100).round()}%)',
      (tester) async {
        addTearDown(tester.view.reset);
        const sizes = [
          Size(320, 640),
          Size(360, 600),
          Size(390, 844),
          Size(600, 900),
          Size(800, 600),
          Size(1360, 860),
        ];
        for (final size in sizes) {
          await open(tester, size, fontScale: fontScale);
          expect(find.byType(ShareSheet), findsOneWidget, reason: '$size');
          expect(tester.takeException(), isNull, reason: '$size');

          // 切到紧凑 + 深色，预览尺寸动画结束后再检查一次
          await tester.ensureVisible(find.text('紧凑'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('紧凑'));
          await tester.tap(find.byType(FilterChip));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$size compact');
        }
      },
    );
  }

  testWidgets('desktop opens a dialog, mobile a bottom sheet', (tester) async {
    addTearDown(tester.view.reset);
    await open(tester, const Size(1360, 860));
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);
    expect(find.textContaining('系统 WebView 暂不可用'), findsOneWidget);

    await open(tester, const Size(390, 844));
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('copy actions write clipboard and flash 已复制', (tester) async {
    addTearDown(tester.view.reset);
    await open(tester, const Size(1360, 860));

    await tester.tap(find.text('复制链接'));
    await tester.pump();
    expect(clipboard, target.webUrl);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('已复制'), findsOneWidget);
    // 反馈结束后恢复原文案
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('已复制'), findsNothing);
    expect(find.text('复制链接'), findsOneWidget);

    await tester.tap(find.text('复制 URI'));
    await tester.pump();
    expect(clipboard, target.uri);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 嵌入代码：紧凑 + 深色 → 复制到的代码同步变化
    await tester.tap(find.text('紧凑'));
    await tester.tap(find.byType(FilterChip));
    await tester.pumpAndSettle();
    final code = target.embedCode(size: EmbedSize.compact, dark: true);
    expect(find.text(code, findRichText: true), findsOneWidget);

    await tester.ensureVisible(find.text('复制代码'));
    await tester.tap(find.text('复制代码'));
    await tester.pump();
    expect(clipboard, code);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  });
}
