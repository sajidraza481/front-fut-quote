/// Integer rounding used everywhere money or quantities are rounded.
///
/// "Half-up" is commercial rounding: halves round away from zero, so
/// 4.5 → 5 and −4.5 → −5. For the non-negative values the painting pack
/// produces this is ordinary half-up.
int roundHalfUpDiv(int numerator, int denominator) {
  if (denominator <= 0) {
    throw ArgumentError.value(denominator, 'denominator', 'must be > 0');
  }
  final magnitude = (numerator.abs() * 2 + denominator) ~/ (denominator * 2);
  return numerator < 0 ? -magnitude : magnitude;
}

/// Basis points: 10 000 bp = 100 %.
const int basisPointsPerUnit = 10000;

/// `amount × bp / 10 000`, rounded half-up.
int applyBasisPoints(int amount, int basisPoints) =>
    roundHalfUpDiv(amount * basisPoints, basisPointsPerUnit);

/// Line total for a quantity in hundredths (e.g. 63.82 m² → 6382) at a unit
/// price in minor units, rounded half-up at line level.
int lineTotal({required int qtyHundredths, required int unitPrice}) =>
    roundHalfUpDiv(qtyHundredths * unitPrice, 100);
