import 'package:flutter/widgets.dart';

/// Apply the app preference after the system's per-font-size scaling curve.
/// Sampling scale(1) would discard Android's nonlinear accessibility scaling.
@immutable
class AppTextScaler extends TextScaler {
  const AppTextScaler(this.system, this.factor);

  final TextScaler system;
  final double factor;

  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is AppTextScaler &&
      other.system == system &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(system, factor);
}
