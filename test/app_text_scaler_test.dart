import 'package:flutify_app/core/theme/app_text_scaler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double fontSize) =>
      fontSize <= 16 ? fontSize * 2 : fontSize * 1.5;
  @override
  double get textScaleFactor => 2;
}

void main() {
  test('app font preference preserves the system nonlinear scaling curve', () {
    const system = _NonlinearScaler();
    const scaler = AppTextScaler(system, 1.2);
    expect(scaler.scale(14), 33.6);
    expect(scaler.scale(32), closeTo(57.6, 0.000001));
    expect(const AppTextScaler(system, 1).scale(32), system.scale(32));
  });
}
