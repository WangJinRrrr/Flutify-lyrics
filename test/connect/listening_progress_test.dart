import 'package:flutify_app/services/connect/receiver/listening_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seek, paused and buffering time cannot satisfy listened threshold', () {
    final progress = ListeningProgress()..anchor(0, 0, reset: true);
    expect(progress.sample(60000, 200, playing: true), isFalse);
    for (var i = 1; i <= 20; i++) {
      expect(
        progress.sample(60000 + i * 1000, 200 + i * 1000, playing: false),
        isFalse,
      );
    }
    expect(progress.milliseconds, 0);
    for (var i = 1; i <= 29; i++) {
      expect(
        progress.sample(80000 + i * 1000, 20200 + i * 1000, playing: true),
        isFalse,
      );
    }
    expect(progress.sample(110000, 50200, playing: true), isTrue);
    expect(progress.sample(111000, 51200, playing: true), isFalse);
  });
  test('small seeks are bounded by elapsed time; track reset clears count', () {
    final progress = ListeningProgress()..anchor(0, 0, reset: true);
    for (var i = 1; i <= 20; i++) {
      expect(progress.sample(i * 2000, i * 10, playing: true), isFalse);
    }
    expect(progress.milliseconds, 200);
    progress.anchor(100000, 200, reset: true);
    expect(progress.milliseconds, 0);
    expect(progress.reported, isFalse);
  });
}
