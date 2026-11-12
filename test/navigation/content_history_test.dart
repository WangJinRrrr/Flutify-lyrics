import 'package:flutify_app/ui/navigation/content_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内容区「后退 / 前进」历史（顶栏 ‹ › 与鼠标侧键共用）的浏览器语义。
void main() {
  late ContentHistory history;
  late GlobalKey<NavigatorState> navigatorKey;

  Future<void> pumpNav(WidgetTester tester) async {
    history = ContentHistory();
    navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [history],
        home: const Scaffold(body: Text('home')),
      ),
    );
  }

  Future<void> pushPage(WidgetTester tester, String label) async {
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => Scaffold(body: Text(label))),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('后退记录被弹出的页面，前进用原 builder 重放', (tester) async {
    await pumpNav(tester);
    await pushPage(tester, 'detail');
    expect(find.text('detail'), findsOneWidget);
    expect(history.canGoBack, isTrue);
    expect(history.canGoForward, isFalse);

    history.back();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(history.canGoBack, isFalse);
    expect(history.canGoForward, isTrue);

    history.forward();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    expect(history.canGoBack, isTrue);
    expect(history.canGoForward, isFalse);
  });

  testWidgets('打开新页面清空前进栈', (tester) async {
    await pumpNav(tester);
    await pushPage(tester, 'a');
    history.back();
    await tester.pumpAndSettle();
    expect(history.canGoForward, isTrue);

    await pushPage(tester, 'b');
    expect(find.text('b'), findsOneWidget);
    expect(history.canGoForward, isFalse);
  });

  testWidgets('popToRoot 回到根页并清空前进栈', (tester) async {
    await pumpNav(tester);
    await pushPage(tester, 'a');
    await pushPage(tester, 'b');
    history.back();
    await tester.pumpAndSettle();
    expect(history.canGoForward, isTrue);

    history.popToRoot();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(history.canGoBack, isFalse);
    expect(history.canGoForward, isFalse);
  });

  testWidgets('根页面后退与空前进栈都是无操作', (tester) async {
    await pumpNav(tester);
    history.back();
    history.forward();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
