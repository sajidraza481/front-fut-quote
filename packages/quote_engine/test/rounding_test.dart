import 'package:quote_engine/quote_engine.dart';
import 'package:test/test.dart';

void main() {
  group('roundHalfUpDiv', () {
    test('rounds halves up', () {
      expect(roundHalfUpDiv(45, 10), 5); // 4.5 → 5
      expect(roundHalfUpDiv(44, 10), 4);
      expect(roundHalfUpDiv(46, 10), 5);
      expect(roundHalfUpDiv(50, 100), 1); // 0.5 → 1
      expect(roundHalfUpDiv(49, 100), 0);
    });

    test('is exact for whole results', () {
      expect(roundHalfUpDiv(31500, 1), 31500);
      expect(roundHalfUpDiv(0, 7), 0);
    });

    test('rounds negative halves away from zero', () {
      expect(roundHalfUpDiv(-45, 10), -5);
      expect(roundHalfUpDiv(-44, 10), -4);
    });

    test('rejects non-positive denominators', () {
      expect(() => roundHalfUpDiv(1, 0), throwsArgumentError);
      expect(() => roundHalfUpDiv(1, -1), throwsArgumentError);
    });

    test('result is within half a unit of the exact quotient', () {
      for (var n = -2000; n <= 2000; n++) {
        for (final d in [1, 2, 3, 7, 10, 100, 9290304]) {
          final r = roundHalfUpDiv(n, d);
          expect((r * d - n).abs() * 2, lessThanOrEqualTo(d), reason: '$n/$d');
        }
      }
    });
  });

  group('lineTotal', () {
    test('rounds at line level', () {
      expect(lineTotal(qtyHundredths: 1, unitPrice: 450), 5); // 4.5p → 5p
      expect(lineTotal(qtyHundredths: 6382, unitPrice: 450), 28719);
      expect(lineTotal(qtyHundredths: 3191, unitPrice: 450), 14360); // 14359.5
    });
  });

  group('applyBasisPoints', () {
    test('applies rates half-up', () {
      expect(applyBasisPoints(49492, 2000), 9898); // 9898.4
      expect(applyBasisPoints(45759, 2000), 9152); // 9151.8
      expect(applyBasisPoints(1, 5000), 1); // 0.5 → 1
      expect(applyBasisPoints(8400, 11500), 9660); // ×1.15
    });
  });
}
