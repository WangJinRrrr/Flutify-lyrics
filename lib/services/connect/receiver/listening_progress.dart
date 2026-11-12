import 'dart:math' as math;

/// Conservative listening time from advancing playback and a monotonic clock.
/// Pauses, buffering and seek jumps cannot satisfy the listening threshold.
class ListeningProgress {
  int _position = 0;
  int _time = 0;
  int milliseconds = 0;
  bool reported = false;

  void anchor(int position, int time, {bool reset = false}) {
    _position = position;
    _time = time;
    if (reset) {
      milliseconds = 0;
      reported = false;
    }
  }

  bool sample(int position, int time, {required bool playing}) {
    final delta = position - _position;
    final elapsed = math.max(0, time - _time);
    anchor(position, time);
    if (playing && delta > 0 && delta <= 3000) {
      milliseconds += math.min(delta, elapsed);
    }
    if (reported || milliseconds < 30000) return false;
    reported = true;
    return true;
  }
}
