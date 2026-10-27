import 'package:meta/meta.dart';
import 'package:quote_engine/src/rounding.dart';

/// Tenths of a millimetre per unit. Whole and half inches convert exactly.
const int _perMillimetre = 10;
const int _perMetre = 10000;
const int _perInch = 254;
const int _perFoot = 3048;

/// A length stored as integer tenths of a millimetre (ADR-001).
@immutable
class Length implements Comparable<Length> {
  /// A length of [tenthsOfMillimetre] × 0.1 mm.
  const new tenthsOfMillimetre(this.tenthsOfMillimetre)
    : assert(tenthsOfMillimetre >= 0, 'length must be non-negative');

  /// A whole number of millimetres.
  const new millimetres(int mm) : this.tenthsOfMillimetre(mm * _perMillimetre);

  /// Parses a decimal metre value such as `"3.65"` without going through
  /// floating point. Up to four decimal places (0.1 mm).
  factory parseMetres(String input) {
    final match = RegExp(r'^\s*(\d+)(?:\.(\d{1,4}))?\s*$').firstMatch(input);
    if (match == null) {
      throw FormatException('Not a metre value with ≤ 4 decimals', input);
    }
    final whole = int.parse(match.group(1)!);
    final fraction = (match.group(2) ?? '').padRight(4, '0');
    return Length.tenthsOfMillimetre(whole * _perMetre + int.parse(fraction));
  }

  /// Feet, inches and sixteenths of an inch. Fractions finer than ½ inch are
  /// rounded to the nearest 0.1 mm (max error 0.05 mm).
  factory imperial({int feet = 0, int inches = 0, int sixteenths = 0}) {
    if (feet < 0 || inches < 0 || sixteenths < 0) {
      throw ArgumentError('imperial parts must be non-negative');
    }
    return Length.tenthsOfMillimetre(
      feet * _perFoot +
          inches * _perInch +
          roundHalfUpDiv(sixteenths * _perInch, 16),
    );
  }

  /// The length in integer tenths of a millimetre.
  final int tenthsOfMillimetre;

  /// Metres in hundredths, rounded half-up (3.65 m → 365).
  int get hundredthsOfMetre =>
      roundHalfUpDiv(tenthsOfMillimetre * 100, _perMetre);

  /// Feet in hundredths, rounded half-up (44 ft → 4400).
  int get hundredthsOfFoot =>
      roundHalfUpDiv(tenthsOfMillimetre * 100, _perFoot);

  /// Sum of two lengths.
  Length operator +(Length other) =>
      Length.tenthsOfMillimetre(tenthsOfMillimetre + other.tenthsOfMillimetre);

  /// Exact rectangular area.
  Area operator *(Length other) =>
      Area._(tenthsOfMillimetre * other.tenthsOfMillimetre);

  @override
  int compareTo(Length other) =>
      tenthsOfMillimetre.compareTo(other.tenthsOfMillimetre);

  @override
  bool operator ==(Object other) =>
      other is Length && other.tenthsOfMillimetre == tenthsOfMillimetre;

  @override
  int get hashCode => tenthsOfMillimetre.hashCode;

  @override
  String toString() => 'Length($tenthsOfMillimetre × 0.1 mm)';
}

/// An exact area in square tenths of a millimetre. May be negative while
/// subtracting openings; packs clamp before pricing.
@immutable
class Area {
  const new _(this._value);

  /// No area.
  static const Area zero = Area._(0);

  static const int _perSquareMetre = _perMetre * _perMetre;
  static const int _perSquareFoot = _perFoot * _perFoot;

  final int _value;

  /// True when openings exceeded the surface they were subtracted from.
  bool get isNegative => _value < 0;

  /// Sum of two areas.
  Area operator +(Area other) => Area._(_value + other._value);

  /// Difference of two areas; may be negative.
  Area operator -(Area other) => Area._(_value - other._value);

  /// Area repeated [factor] times (e.g. a count of identical openings).
  Area operator *(int factor) => Area._(_value * factor);

  /// This area, or [zero] if negative.
  Area clampAtZero() => isNegative ? zero : this;

  /// Square metres in hundredths, rounded half-up (35.00 m² → 3500).
  int get hundredthsOfSquareMetre =>
      roundHalfUpDiv(_value * 100, _perSquareMetre);

  /// Square feet in hundredths, rounded half-up (352.00 ft² → 35200).
  int get hundredthsOfSquareFoot =>
      roundHalfUpDiv(_value * 100, _perSquareFoot);

  @override
  bool operator ==(Object other) => other is Area && other._value == _value;

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() => 'Area(${hundredthsOfSquareMetre / 100} m²)';
}
