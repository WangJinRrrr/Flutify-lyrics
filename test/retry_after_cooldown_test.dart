import 'package:flutify_app/services/network/retry_after_cooldown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  for (final header in [null, 'nonsense', '-5']) {
    test(
      '429 with invalid/missing Retry-After ($header) cools for a minute',
      () {
        var now = DateTime.utc(2026, 10, 4);
        final cooldown = RetryAfterCooldown(now: () => now);
        cooldown.observe(
          http.Response(
            '',
            429,
            headers: {if (header != null) 'retry-after': header},
          ),
        );
        now = now.add(const Duration(seconds: 59));
        expect(cooldown.active, isTrue);
        now = now.add(const Duration(seconds: 1));
        expect(cooldown.active, isFalse);
      },
    );
  }
  test('a later in-flight response cannot shorten the active cooldown', () {
    var now = DateTime.utc(2026, 10, 4);
    final cooldown = RetryAfterCooldown(now: () => now);
    cooldown.observe(http.Response('', 429, headers: {'retry-after': '120'}));
    now = now.add(const Duration(seconds: 10));
    cooldown.observe(http.Response('', 429, headers: {'retry-after': '1'}));
    now = now.add(const Duration(seconds: 109));
    expect(cooldown.active, isTrue);
    now = now.add(const Duration(seconds: 1));
    expect(cooldown.active, isFalse);
  });
}
