import 'dart:convert';

import 'package:flutify_app/services/pathfinder/desktop_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'home refresh requests fresh data and uses the current language',
    () async {
      var language = 'zh-CN';
      var requests = 0;
      final source = DesktopDataSource(
        MockClient((request) async {
          requests++;
          final body = jsonDecode(request.body) as Map;
          expect(body['variables']['facet'], 'music');
          expect(request.headers['accept-language'], language);
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'data': {
                  'home': {
                    'greeting': {'translatedBaseText': '$language:$requests'},
                  },
                },
              }),
            ),
            200,
          );
        }),
        headers: () async => {'Accept-Language': language},
        language: () => language,
      );

      expect((await source.home(facet: 'music')).greeting, 'zh-CN:1');
      expect((await source.home(facet: 'music')).greeting, 'zh-CN:2');
      language = 'ja';
      expect((await source.home(facet: 'music')).greeting, 'ja:3');
      expect(requests, 3);
    },
  );

  test('localized browse cache is reused only for the same language', () async {
    var language = 'zh-CN';
    final requestedLanguages = <String?>[];
    final source = DesktopDataSource(
      MockClient((request) async {
        requestedLanguages.add(request.headers['accept-language']);
        return http.Response('{"data":{}}', 200);
      }),
      headers: () async => {'Accept-Language': language},
      language: () => language,
    );

    await source.categories();
    await source.categories();
    language = 'ja';
    await source.categories();
    await source.categories();
    expect(requestedLanguages, ['zh-CN', 'ja']);
  });
}
