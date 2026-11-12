import 'package:flutify_app/l10n/l10n.dart';
import 'package:flutify_app/ui/screens/settings/widgets/proxy_auth_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 代理认证输入框：未改动不提交；离开页面补交未提交的改动；外部值变化时同步；
/// 用户名含冒号时给出提示。
void main() {
  Widget host(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(
      body: Column(
        children: [
          child,
          const TextField(key: ValueKey('other')),
        ],
      ),
    ),
  );

  final username = find.byKey(const ValueKey('proxy-username'));
  final password = find.byKey(const ValueKey('proxy-password'));

  testWidgets('内容没变：失焦不提交', (tester) async {
    final applied = <(String, String)>[];
    await tester.pumpWidget(
      host(
        ProxyAuthFields(
          username: 'u',
          password: 'p',
          onApply: (u, p) => applied.add((u, p)),
        ),
      ),
    );
    await tester.tap(username);
    await tester.tap(find.byKey(const ValueKey('other')));
    await tester.pump();
    expect(applied, isEmpty);

    await tester.enterText(password, 'p2');
    await tester.tap(find.byKey(const ValueKey('other')));
    await tester.pump();
    expect(applied, [('u', 'p2')]);
  });

  testWidgets('离开页面：未提交的改动补交', (tester) async {
    final applied = <(String, String)>[];
    await tester.pumpWidget(
      host(
        ProxyAuthFields(
          username: '',
          password: '',
          onApply: (u, p) => applied.add((u, p)),
        ),
      ),
    );
    await tester.enterText(username, ' alice ');
    await tester.enterText(password, 'secret');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(applied, [('alice', 'secret')]);
  });

  testWidgets('外部值变化（未在编辑）时同步进输入框', (tester) async {
    Widget build(String u) =>
        host(ProxyAuthFields(username: u, password: '', onApply: (_, _) {}));
    await tester.pumpWidget(build('old'));
    await tester.pumpWidget(build('new'));
    expect(tester.widget<TextField>(username).controller!.text, 'new');
  });

  testWidgets('用户名含冒号时提示代理会认证失败；密码任意字符都不提示', (tester) async {
    await tester.pumpWidget(
      host(ProxyAuthFields(username: 'u', password: '', onApply: (_, _) {})),
    );
    final warning = find.byKey(const ValueKey('proxy-username-invalid'));
    expect(warning, findsNothing);
    // HTTPS 经自建隧道认证，密码里的分号 / 空白都能带上
    await tester.enterText(password, 'a; b');
    await tester.pump();
    expect(warning, findsNothing);
    await tester.enterText(username, 'u:1');
    await tester.pump();
    expect(warning, findsOneWidget);
    await tester.enterText(username, 'u1');
    await tester.pump();
    expect(warning, findsNothing);
  });

  testWidgets('只填一项时明确提示 HTTP 代理认证不完整', (tester) async {
    await tester.pumpWidget(
      host(ProxyAuthFields(username: 'u', password: '', onApply: (_, _) {})),
    );
    expect(find.byKey(const ValueKey('proxy-auth-incomplete')), findsOneWidget);
    await tester.enterText(password, 'secret');
    await tester.pump();
    expect(find.byKey(const ValueKey('proxy-auth-incomplete')), findsNothing);
  });
}
