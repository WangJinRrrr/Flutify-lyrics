import 'dart:io';

import 'package:flutify_app/services/lyrics/lrclib_client.dart';
import 'package:flutify_app/services/lyrics/netease_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final source in ['lrclib', 'netease']) {
    for (final status in [429, 503]) {
      for (final dateHeader in [false, true]) {
        test(
          '$source $status respects ${dateHeader ? 'HTTP date' : 'seconds'} across queries',
          () async {
            var now = DateTime.utc(2026, 10, 4, 12);
            var requests = 0;
            final sleeps = <Duration>[];
            final deadline = now.add(const Duration(seconds: 120));
            final client = MockClient((_) async {
              requests++;
              return requests == 1
                  ? http.Response(
                      '',
                      status,
                      headers: {
                        'retry-after': dateHeader
                            ? HttpDate.format(deadline)
                            : '120',
                      },
                    )
                  : http.Response('{}', 200);
            });
            final lrc = LrclibClient(
              client,
              now: () => now,
              sleep: (d) async => sleeps.add(d),
            );
            final ne = NeteaseClient(
              client,
              now: () => now,
              sleep: (d) async => sleeps.add(d),
            );
            Future<bool> search() async => source == 'lrclib'
                ? (await lrc.search(track: 'Song')).networkError
                : (await ne.search('Song')).networkError;
            Future<bool> lookup() async => source == 'lrclib'
                ? (await lrc.get(track: 'Other', artist: 'Artist')).networkError
                : (await ne.lyric(42)).networkError;

            expect(await search(), isTrue);
            now = deadline.subtract(const Duration(milliseconds: 1));
            expect(await lookup(), isTrue);
            expect(requests, 1);
            expect(
              sleeps,
              isEmpty,
              reason: 'Do not hold the lyrics UI waiting for a retry',
            );
            now = deadline;
            expect(await lookup(), isFalse);
            expect(requests, 2);
          },
        );
      }
    }
  }
}
