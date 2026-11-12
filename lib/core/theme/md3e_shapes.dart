import 'package:flutter/material.dart';

/// Material 3 Expressive (MD3E) Shape Tokens
/// Google M3 Expressive emphasizes extreme corner contrast:
/// Stadium pills for actions & chips, 24-28dp organic radii for cards and containers.
class MD3EShapes {
  MD3EShapes._();

  static const double radiusExtraSmall = 4.0;
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 16.0;
  static const double radiusLarge = 24.0;
  static const double radiusExtraLarge = 28.0;
  static const double radiusFull = 999.0;

  // Border Radii
  static const BorderRadius roundedSmall = BorderRadius.all(Radius.circular(radiusSmall));
  static const BorderRadius roundedMedium = BorderRadius.all(Radius.circular(radiusMedium));
  static const BorderRadius roundedLarge = BorderRadius.all(Radius.circular(radiusLarge));
  static const BorderRadius roundedExtraLarge = BorderRadius.all(Radius.circular(radiusExtraLarge));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(radiusFull));

  // Bottom Sheet Corner Radii
  static const BorderRadius topSheet = BorderRadius.vertical(top: Radius.circular(32.0));

  // Expressive Shape Borders
  static const ShapeBorder pillShape = StadiumBorder();
  static const ShapeBorder cardShape = RoundedRectangleBorder(
    borderRadius: roundedLarge,
  );
  static const ShapeBorder sheetShape = RoundedRectangleBorder(
    borderRadius: topSheet,
  );
  static const ShapeBorder buttonShape = RoundedRectangleBorder(
    borderRadius: pill,
  );
}
