import 'dart:io';

import 'package:http/http.dart' as http;

/// Per-service cooldown shared by all request paths. A rejected request fails
/// promptly; changing the query must not bypass the server's retry deadline.
class RetryAfterCooldown {
  RetryAfterCooldown({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  DateTime? _until;

  bool get active => _until != null && _now().isBefore(_until!);

  bool observe(http.Response response) {
    final header = response.headers['retry-after'];
    if (response.statusCode != 429 &&
        !(response.statusCode == 503 && header != null)) {
      return false;
    }
    final now = _now();
    var delay = const Duration(minutes: 1);
    if (header != null) {
      final seconds = int.tryParse(header.trim());
      if (seconds != null && seconds >= 0 && seconds <= 315360000) {
        delay = Duration(seconds: seconds);
      } else {
        try {
          delay = HttpDate.parse(header.trim()).difference(now);
        } on HttpException {
          // Missing/malformed dates use the conservative default above.
        }
      }
    }
    // Even Retry-After: 0 must not become a tight retry loop.
    if (delay < const Duration(seconds: 1)) delay = const Duration(seconds: 1);
    final until = now.add(delay);
    if (_until == null || until.isAfter(_until!)) _until = until;
    return true;
  }
}
