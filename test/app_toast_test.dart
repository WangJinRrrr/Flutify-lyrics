import 'package:flutify_app/core/theme/md3e_theme.dart';
import 'package:flutify_app/models/appearance.dart';
import 'package:flutify_app/ui/widgets/toast/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 统一提示：内容带表现力图标块；新提示替换旧提示；带按钮的到时自动收起。
void main() {
  testWidgets('AppToast replaces the current toast and renders icon + action', (tester) async {
    late BuildContext host;
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: MD3ETheme.build(Brightness.light, AppearanceSettings.defaults, AppearanceSettings.defaults.accent),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              host = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    AppToast.show(host, '第一条');
    await tester.pumpAndSettle();
    expect(find.text('第一条'), findsOneWidget);

    AppToast.show(
      host,
      '第二条',
      icon: Icons.wifi_off_rounded,
      tone: ToastTone.error,
      actionLabel: '重试',
      onAction: () => tapped++,
    );
    await tester.pumpAndSettle();
    expect(find.text('第一条'), findsNothing, reason: '新提示替换旧提示，不排队');
    expect(find.text('第二条'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    expect(tester.widget<ToastContent>(find.byType(ToastContent)).tone, ToastTone.error);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(tapped, 1);

    AppToast.show(host, '带按钮', actionLabel: '撤销', onAction: () {});
    await tester.pumpAndSettle();
    await tester.pump(AppToast.durationWithAction + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('带按钮'), findsNothing, reason: '带按钮的提示也会到时自动收起');
  });
}
