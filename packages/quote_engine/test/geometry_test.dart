import 'package:quote_engine/quote_engine.dart';
import 'package:test/test.dart';

void main() {
  group('Length', () {
    test('parses metres without floating point', () {
      expect(Length.parseMetres('3.65').tenthsOfMillimetre, 36500);
      expect(Length.parseMetres('2').tenthsOfMillimetre, 20000);
      expect(Length.parseMetres('0.0001').tenthsOfMillimetre, 1);
      expect(Length.parseMetres(' 4.5 '), const Length.millimetres(4500));
    });

    test('rejects malformed metre input', () {
      for (final bad in ['', '-1', '1.23456', 'abc', '1,5', '.5']) {
        expect(
          () => Length.parseMetres(bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    test('converts imperial exactly for whole and half inches', () {
      expect(Length.imperial(feet: 1), Length.parseMetres('0.3048'));
      expect(Length.imperial(inches: 1).tenthsOfMillimetre, 254);
      expect(Length.imperial(sixteenths: 8).tenthsOfMillimetre, 127);
      expect(Length.imperial(feet: 12, inches: 6).tenthsOfMillimetre, 38100);
    });

    test('rounds fine inch fractions to the nearest 0.1 mm', () {
      expect(Length.imperial(sixteenths: 1).tenthsOfMillimetre, 16); // 15.875
    });

    test('rejects negative imperial parts', () {
      expect(() => Length.imperial(feet: -1), throwsArgumentError);
    });
  });

  group('Area', () {
    test('metric rectangle in hundredths of m²', () {
      final wall =
          (Length.parseMetres('4') + Length.parseMetres('3')) *
          Length.parseMetres('2.5');
      expect((wall * 2).hundredthsOfSquareMetre, 3500);
    });

    test('rounds half-up to 0.01 m²', () {
      final ceiling = Length.parseMetres('3.65') * Length.parseMetres('2.75');
      expect(ceiling.hundredthsOfSquareMetre, 1004); // 10.0375
    });

    test('imperial rectangle in hundredths of ft²', () {
      final wall = Length.imperial(feet: 44) * Length.imperial(feet: 8);
      expect(wall.hundredthsOfSquareFoot, 35200);
    });

    test('converts between unit systems', () {
      final sqFt = Length.imperial(feet: 1) * Length.imperial(feet: 1);
      expect(sqFt.hundredthsOfSquareMetre, 9); // 0.0929 m²
      final sqM = Length.parseMetres('1') * Length.parseMetres('1');
      expect(sqM.hundredthsOfSquareFoot, 1076); // 10.7639 ft²
    });

    test('subtracting openings can go negative, then clamps to zero', () {
      final wall = Length.parseMetres('6') * Length.parseMetres('1');
      final openings = Length.parseMetres('2') * Length.parseMetres('2') * 2;
      final net = wall - openings;
      expect(net.isNegative, isTrue);
      expect(net.clampAtZero(), Area.zero);
    });
  });
}
