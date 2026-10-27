import 'dart:math';

import 'package:quote_engine/quote_engine.dart';
import 'package:test/test.dart';

const _pack = PaintingPack();
const _engine = QuoteEngine();
const _vat = TaxRule(2000);

PriceList _metric({int markup = 0, List<CatalogItem> extra = const []}) =>
    PriceList(
      unitSystem: UnitSystem.metric,
      markupBasisPoints: markup,
      items: [..._pack.defaultCatalog(UnitSystem.metric), ...extra],
    );

LengthValue _m(String metres) => LengthValue(Length.parseMetres(metres));

SectionInput _room({
  Map<String, FieldValue> fields = const {},
  List<ExtraInput> extras = const [],
}) => SectionInput(
  values: {
    PaintingField.length: _m('4'),
    PaintingField.width: _m('3'),
    PaintingField.height: _m('2.5'),
    ...fields,
  },
  extras: extras,
);

Result<QuoteTotals> _compute(
  SectionInput input, {
  PriceList? prices,
  Map<String, FieldValue> traderDefaults = const {},
}) => _engine.compute(
  Quote(
    sections: [QuoteSection(name: 'Room', input: input)],
  ),
  _pack,
  prices ?? _metric(),
  _vat,
  traderDefaults: traderDefaults,
);

QuoteTotals _ok(Result<QuoteTotals> result) => switch (result) {
  Ok(:final value) => value,
  Invalid(:final errors) => fail('unexpected errors: $errors'),
};

List<InputError> _errors(Result<QuoteTotals> result) => switch (result) {
  Ok() => fail('expected errors'),
  Invalid(:final errors) => errors,
};

void main() {
  group('defaults', () {
    test('pack defaults: 2 coats, good prep at 0p, no ceiling or primer', () {
      final codes = _ok(_compute(_room())).lines.map((l) => l.code);
      expect(codes, [PaintingCode.wallPainting, PaintingCode.wallPaint]);
    });

    test('default catalogs pass price-list validation', () {
      for (final system in UnitSystem.values) {
        final prices = PriceList(
          unitSystem: system,
          items: _pack.defaultCatalog(system),
        );
        expect(_pack.validatePriceList(prices), isEmpty, reason: '$system');
      }
    });

    test('suggested extra sources point at real items and quantities', () {
      final codes = _pack
          .defaultCatalog(UnitSystem.metric)
          .map((i) => i.code)
          .toSet();
      for (final MapEntry(:key, :value)
          in _pack.suggestedExtraSources.entries) {
        expect(codes, contains(key));
        if (value case FromQuantity(:final quantityId)) {
          expect(_pack.extraQuantityIds, contains(quantityId));
        }
      }
    });

    test('trader default applies when the room does not override it', () {
      final totals = _ok(
        _compute(
          _room(),
          traderDefaults: {PaintingField.coats: const WholeNumberValue(3)},
        ),
      );
      expect(totals.lines.first.qtyHundredths, 3500 * 3);
    });

    test('room value beats trader default', () {
      final totals = _ok(
        _compute(
          _room(fields: {PaintingField.coats: const WholeNumberValue(1)}),
          traderDefaults: {PaintingField.coats: const WholeNumberValue(3)},
        ),
      );
      expect(totals.lines.first.qtyHundredths, 3500);
    });
  });

  group('validation', () {
    test('missing required dimensions', () {
      final errors = _errors(_compute(const SectionInput()));
      expect(errors, [
        const InputError('sections[0].length', 'required'),
        const InputError('sections[0].width', 'required'),
        const InputError('sections[0].height', 'required'),
      ]);
    });

    test('limits, types, choices and unknown fields', () {
      final errors = _errors(
        _compute(
          _room(
            fields: {
              PaintingField.coats: const WholeNumberValue(5),
              PaintingField.height: _m('10.0001'),
              PaintingField.primer: const WholeNumberValue(1),
              PaintingField.surfaceCondition: const ChoiceValue('bad'),
              'corners': const WholeNumberValue(4),
            },
          ),
        ),
      );
      expect(
        errors,
        unorderedEquals([
          const InputError('sections[0].corners', 'unknownField'),
          const InputError('sections[0].height', 'outOfRange'),
          const InputError('sections[0].coats', 'outOfRange'),
          const InputError('sections[0].primer', 'wrongType'),
          const InputError('sections[0].surfaceCondition', 'invalidChoice'),
        ]),
      );
    });

    test('zero-sized dimension and opening count', () {
      final errors = _errors(
        _compute(
          _room(
            fields: {
              PaintingField.width: _m('0'),
              PaintingField.openings: OpeningsValue([
                Opening(
                  width: Length.parseMetres('1'),
                  height: Length.parseMetres('1'),
                  count: 0,
                ),
              ]),
            },
          ),
        ),
      );
      expect(errors, [
        const InputError('sections[0].width', 'outOfRange'),
        const InputError('sections[0].openings', 'outOfRange'),
      ]);
    });

    test('price list missing an item or coverage', () {
      final items = [..._pack.defaultCatalog(UnitSystem.metric)]
        ..removeWhere((i) => i.code == PaintingCode.prepPoor);
      final paint = items.indexWhere((i) => i.code == PaintingCode.wallPaint);
      items[paint] = const CatalogItem(
        code: PaintingCode.wallPaint,
        name: 'Wall paint',
        kind: ItemKind.material,
        unit: QuantityUnit.litre,
        unitPrice: 1200,
      );
      final errors = _errors(
        _compute(
          _room(),
          prices: PriceList(unitSystem: UnitSystem.metric, items: items),
        ),
      );
      expect(errors, [
        const InputError(PaintingCode.wallPaint, 'missingCoverage'),
        const InputError(PaintingCode.prepPoor, 'missingPriceItem'),
      ]);
    });

    test('metric catalog on an imperial price list is rejected', () {
      final errors = _errors(
        _compute(
          _room(),
          prices: PriceList(
            unitSystem: UnitSystem.imperial,
            items: _pack.defaultCatalog(UnitSystem.metric),
          ),
        ),
      );
      expect(errors, hasLength(PaintingCode.all.length));
      expect(errors.map((e) => e.code).toSet(), {'unitMismatch'});
    });

    test('extras: unknown item, unknown quantity, unit mismatch, count', () {
      const perM2 = CatalogItem(
        code: 'mould',
        name: 'Mould treatment',
        kind: ItemKind.labour,
        unit: QuantityUnit.squareMetre,
        unitPrice: 150,
      );
      final errors = _errors(
        _compute(
          _room(
            extras: const [
              ExtraInput(itemCode: 'nope', source: Flat()),
              ExtraInput(
                itemCode: 'mould',
                source: FromQuantity('grossWallArea'),
              ),
              ExtraInput(itemCode: 'mould', source: FromQuantity('perimeter')),
              ExtraInput(itemCode: 'mould', source: CountOf(2)),
              ExtraInput(itemCode: 'mould', source: Flat()),
            ],
          ),
          prices: _metric(extra: [perM2]),
        ),
      );
      expect(errors, [
        const InputError('sections[0].extras[0]', 'unknownItem'),
        const InputError('sections[0].extras[1]', 'unknownQuantity'),
        const InputError('sections[0].extras[2]', 'unitMismatch'),
        const InputError('sections[0].extras[3]', 'unitMismatch'),
        const InputError('sections[0].extras[4]', 'unitMismatch'),
      ]);
    });

    test('extras: typed quantity, price required, bad override', () {
      final errors = _errors(
        _compute(
          _room(
            extras: const [
              ExtraInput(itemCode: PaintingExtra.highAccess, source: Flat()),
              ExtraInput(
                itemCode: PaintingExtra.skirtingBoards,
                source: Entered(0),
              ),
              ExtraInput(itemCode: PaintingExtra.doors, source: Entered(150)),
              ExtraInput(
                itemCode: PaintingExtra.radiators,
                source: CountOf(1),
                unitPrice: -1,
              ),
            ],
          ),
        ),
      );
      expect(errors, [
        const InputError('sections[0].extras[0]', 'priceRequired'),
        const InputError('sections[0].extras[1]', 'outOfRange'),
        const InputError('sections[0].extras[2]', 'unitMismatch'),
        const InputError('sections[0].extras[3]', 'outOfRange'),
      ]);
    });

    test('pack items without a list price are rejected', () {
      final items = [
        for (final i in _pack.defaultCatalog(UnitSystem.metric))
          if (i.code == PaintingCode.wallPainting)
            CatalogItem(
              code: i.code,
              name: i.name,
              kind: i.kind,
              unit: i.unit,
              unitPrice: null,
            )
          else
            i,
      ];
      expect(
        _pack.validatePriceList(
          PriceList(unitSystem: UnitSystem.metric, items: items),
        ),
        [const InputError(PaintingCode.wallPainting, 'priceRequired')],
      );
    });

    test('errors from every section are reported', () {
      final result = _engine.compute(
        const Quote(
          sections: [
            QuoteSection(name: 'A', input: SectionInput()),
            QuoteSection(name: 'B', input: SectionInput()),
          ],
        ),
        _pack,
        _metric(),
        _vat,
      );
      expect(_errors(result).map((e) => e.field).toSet(), {
        for (final s in ['sections[0]', 'sections[1]'])
          for (final f in ['length', 'width', 'height']) '$s.$f',
      });
    });
  });

  group('pricing', () {
    test('markup rounds half-up inside the unit price', () {
      final line = LineItem.price(
        const CatalogItem(
          code: 'x',
          name: 'x',
          kind: ItemKind.material,
          unit: QuantityUnit.litre,
          unitPrice: 999,
        ),
        qtyHundredths: 100,
        markupBasisPoints: 1500,
      );
      expect(line.unitPrice, 1149); // 1148.85
      expect(line.total, 1149);
    });

    test('markup never applies to labour or flat items', () {
      for (final kind in [ItemKind.labour, ItemKind.flat]) {
        final line = LineItem.price(
          CatalogItem(
            code: 'x',
            name: 'x',
            kind: kind,
            unit: QuantityUnit.each,
            unitPrice: 999,
          ),
          qtyHundredths: 100,
          markupBasisPoints: 1500,
        );
        expect(line.unitPrice, 999);
      }
    });

    test('a 0p prep rate omits the prep line', () {
      final totals = _ok(_compute(_room())); // default good prep = 0p
      expect(
        totals.lines.map((l) => l.code),
        isNot(contains(PaintingCode.prepGood)),
      );
      // 70 m² × 450p + ⌈70 ÷ 12 × 1.1 ÷ 2.5 = 2.57⌉ = 3 tins × 3000p
      expect(totals.subtotal, 31500 + 9000);
    });

    test('paint rounds up to whole packs after waste', () {
      LineItem paint(int coatedHundredths, {int waste = 0, int pack = 100}) {
        final prices = PriceList(
          unitSystem: UnitSystem.metric,
          items: [
            for (final i in _pack.defaultCatalog(UnitSystem.metric))
              if (i.code == PaintingCode.wallPaint)
                CatalogItem(
                  code: i.code,
                  name: i.name,
                  kind: i.kind,
                  unit: i.unit,
                  unitPrice: 1000,
                  coverageHundredths: 1000, // 10 m²/L
                  packSizeHundredths: pack,
                  wasteBasisPoints: waste,
                )
              else
                i,
          ],
        );
        return _pack
            .price(
              QuantitySet(
                measured: const {},
                lines: {PaintingCode.wallPaint: coatedHundredths},
              ),
              prices,
            )
            .single;
      }

      expect(paint(5000).qtyHundredths, 500); // exactly 5 L
      expect(paint(5001).qtyHundredths, 600); // 5.001 L → 6
      expect(paint(5000, pack: 250).qtyHundredths, 200); // 5 L = 2 tins
      expect(paint(5001, pack: 250).qtyHundredths, 300);
      // 5 L × 1.10 = 5.5 L → 3 tins of 2.5 L, not 2.
      expect(paint(5000, waste: 1000, pack: 250).qtyHundredths, 300);
      // 4.5 L × 1.10 = 4.95 L → 2 tins: waste applied before rounding.
      expect(paint(4500, waste: 1000, pack: 250).qtyHundredths, 200);
      final tins = paint(5000, pack: 250);
      expect(tins.packSizeHundredths, 250);
      expect(tins.total, 2000); // 2 tins × 1000p per tin
    });

    group('tin size chosen per room', () {
      LineItem paintLine(QuoteTotals totals, String code) =>
          totals.lines.singleWhere((l) => l.code == code);

      test('default is the 2.5 L tin', () {
        // 70 m² coated ÷ 12 × 1.10 ÷ 2.5 = 2.57 → 3 tins × 3000p
        final line = paintLine(_ok(_compute(_room())), PaintingCode.wallPaint);
        expect(
          (line.qtyHundredths, line.packSizeHundredths, line.total),
          (300, 250, 9000),
        );
      });

      test('a room can use 5 L tins instead', () {
        final totals = _ok(
          _compute(
            _room(
              fields: {
                PaintingField.wallPaintItem: const PriceItemValue(
                  PaintingExtra.wallPaint5l,
                ),
              },
            ),
          ),
        );
        // 70 ÷ 12 × 1.10 ÷ 5 = 1.28 → 2 tins × 5500p, in the wall paint slot.
        expect(totals.lines.map((l) => l.code), [
          PaintingCode.wallPainting,
          PaintingExtra.wallPaint5l,
        ]);
        final line = paintLine(totals, PaintingExtra.wallPaint5l);
        expect(
          (line.qtyHundredths, line.packSizeHundredths, line.total),
          (200, 500, 11000),
        );
      });

      test('a trader default applies, and a room can switch back', () {
        const fiveLitre = {
          PaintingField.wallPaintItem: PriceItemValue(
            PaintingExtra.wallPaint5l,
          ),
        };
        final byDefault = _ok(_compute(_room(), traderDefaults: fiveLitre));
        expect(
          byDefault.lines.map((l) => l.code),
          contains(PaintingExtra.wallPaint5l),
        );
        final switchedBack = _ok(
          _compute(
            _room(
              fields: {
                PaintingField.wallPaintItem: const PriceItemValue(
                  PaintingCode.wallPaint,
                ),
              },
            ),
            traderDefaults: fiveLitre,
          ),
        );
        expect(
          switchedBack.lines.map((l) => l.code),
          contains(PaintingCode.wallPaint),
        );
      });

      test('primer uses the same pack mechanism', () {
        const primerTin = CatalogItem(
          code: 'primer_2_5l',
          name: 'Primer (2.5 L tin)',
          kind: ItemKind.material,
          unit: QuantityUnit.litre,
          unitPrice: 2500,
          coverageHundredths: 1000,
          packSizeHundredths: 250,
          wasteBasisPoints: 1000,
        );
        final totals = _ok(
          _compute(
            _room(
              fields: {
                PaintingField.primer: const ToggleValue(true),
                PaintingField.primerItem: const PriceItemValue('primer_2_5l'),
              },
            ),
            prices: _metric(extra: [primerTin]),
          ),
        );
        // 35 m² ÷ 10 × 1.10 ÷ 2.5 = 1.54 → 2 tins × 2500p
        final line = paintLine(totals, 'primer_2_5l');
        expect((line.qtyHundredths, line.total), (200, 5000));
      });

      test('the chosen item must be a packed material in the same unit', () {
        const gallons = CatalogItem(
          code: 'paint_gal',
          name: 'Paint (gallon)',
          kind: ItemKind.material,
          unit: QuantityUnit.usGallon,
          unitPrice: 4200,
          coverageHundredths: 35000,
        );
        final errors = _errors(
          _compute(
            _room(
              fields: {
                PaintingField.wallPaintItem: const PriceItemValue('nope'),
                PaintingField.ceilingPaintItem: const PriceItemValue(
                  PaintingCode.wallPainting,
                ),
                PaintingField.primerItem: const PriceItemValue('paint_gal'),
              },
            ),
            prices: _metric(extra: [gallons]),
          ),
        );
        expect(errors, [
          const InputError('sections[0].wallPaintItem', 'unknownItem'),
          const InputError('sections[0].ceilingPaintItem', 'unitMismatch'),
          const InputError('sections[0].primerItem', 'unitMismatch'),
        ]);
      });
    });

    test('prep and primer use surfaceArea, never multiplied by coats', () {
      final totals = _ok(
        _compute(
          _room(
            fields: {
              PaintingField.coats: const WholeNumberValue(3),
              PaintingField.primer: const ToggleValue(true),
              PaintingField.surfaceCondition: const ChoiceValue('fair'),
            },
          ),
        ),
      );
      int qty(String code) =>
          totals.lines.singleWhere((l) => l.code == code).qtyHundredths;
      expect(qty(PaintingCode.wallPainting), 3500 * 3);
      expect(qty(PaintingCode.prepFair), 3500);
      expect(qty(PaintingCode.primerApplication), 3500);
    });

    test('extras: typed quantity, window count and per-quote price', () {
      final totals = _ok(
        _compute(
          _room(
            fields: {
              PaintingField.openings: OpeningsValue([
                Opening(
                  width: Length.parseMetres('1.2'),
                  height: Length.parseMetres('1'),
                  count: 2,
                  kind: OpeningKind.window,
                ),
              ]),
            },
            extras: const [
              ExtraInput(
                itemCode: PaintingExtra.skirtingBoards,
                source: Entered(1310),
              ),
              ExtraInput(
                itemCode: PaintingExtra.windowFrames,
                source: FromQuantity(PaintingQuantity.windowCount),
              ),
              ExtraInput(
                itemCode: PaintingExtra.highAccess,
                source: Flat(),
                unitPrice: 12000,
              ),
            ],
          ),
        ),
      );
      final extras = totals.lines.skip(2).toList();
      expect(extras.map((l) => (l.code, l.qtyHundredths, l.total)), [
        (PaintingExtra.skirtingBoards, 1310, 5240),
        (PaintingExtra.windowFrames, 200, 5000),
        (PaintingExtra.highAccess, 100, 12000),
      ]);
      expect(extras.map((l) => l.isPriceOverride), [false, false, true]);
    });

    test('a price override on a material extra is used without markup', () {
      final totals = _ok(
        _compute(
          _room(
            extras: const [
              ExtraInput(
                itemCode: PaintingExtra.wallPaint5l,
                source: CountOf(1),
                unitPrice: 5000,
              ),
            ],
          ),
          prices: _metric(markup: 1500),
        ),
      );
      final line = totals.lines.last;
      expect(line.unitPrice, 5000);
      expect(line.isPriceOverride, isTrue);
    });

    test('imperial measurements on a metric price list', () {
      // 13 ft 1½ in ≈ 4.0005 m: same room as 4 × 3 × 2.5 m within rounding.
      final totals = _ok(
        _compute(
          SectionInput(
            values: {
              PaintingField.length: LengthValue(
                Length.imperial(feet: 13, inches: 1, sixteenths: 8),
              ),
              PaintingField.width: _m('3'),
              PaintingField.height: _m('2.5'),
            },
          ),
        ),
      );
      expect(totals.lines.first.qtyHundredths, 7000); // 35.0025 → 35.00 m²
    });

    test('metric measurements on an imperial price list', () {
      final totals = _ok(
        _engine.compute(
          Quote(
            sections: [
              QuoteSection(
                name: 'Room',
                input: SectionInput(
                  values: {
                    PaintingField.length: LengthValue(
                      Length.imperial(feet: 12),
                    ),
                    PaintingField.width: LengthValue(Length.imperial(feet: 10)),
                    PaintingField.height: _m('2.4384'), // exactly 8 ft
                  },
                ),
              ),
            ],
          ),
          _pack,
          PriceList(
            unitSystem: UnitSystem.imperial,
            items: _pack.defaultCatalog(UnitSystem.imperial),
          ),
          TaxRule.none,
        ),
      );
      expect(totals.lines.first.qtyHundredths, 35200 * 2);
    });

    test('measured quantities exposed to extras', () {
      final q = _pack.quantities(
        SectionFields({
          PaintingField.length: _m('4'),
          PaintingField.width: _m('3'),
          PaintingField.height: _m('2.5'),
          PaintingField.openings: OpeningsValue([
            Opening(
              width: Length.parseMetres('0.9'),
              height: Length.parseMetres('2.1'),
              count: 2,
              kind: OpeningKind.door,
            ),
            Opening(
              width: Length.parseMetres('0.1'),
              height: Length.parseMetres('0.1'),
            ),
          ]),
          PaintingField.coats: const WholeNumberValue(2),
          PaintingField.includeCeiling: const ToggleValue(true),
          PaintingField.primer: const ToggleValue(false),
          PaintingField.surfaceCondition: const ChoiceValue('good'),
          PaintingField.wallPaintItem: const PriceItemValue(
            PaintingCode.wallPaint,
          ),
          PaintingField.ceilingPaintItem: const PriceItemValue(
            PaintingCode.ceilingPaint,
          ),
          PaintingField.primerItem: const PriceItemValue(PaintingCode.primer),
        }),
        UnitSystem.metric,
      );
      expect(q.measured, {
        PaintingQuantity.grossWallArea: const Quantity(
          3500,
          QuantityUnit.squareMetre,
        ),
        PaintingQuantity.openingsArea: const Quantity(
          379,
          QuantityUnit.squareMetre,
        ),
        PaintingQuantity.netWallArea: const Quantity(
          3121,
          QuantityUnit.squareMetre,
        ),
        PaintingQuantity.ceilingArea: const Quantity(
          1200,
          QuantityUnit.squareMetre,
        ),
        PaintingQuantity.surfaceArea: const Quantity(
          4321,
          QuantityUnit.squareMetre,
        ),
        PaintingQuantity.coatedArea: const Quantity(
          8642,
          QuantityUnit.squareMetre,
        ),
        PaintingQuantity.perimeter: const Quantity(1400, QuantityUnit.metre),
        PaintingQuantity.openingsCount: const Quantity(300, QuantityUnit.each),
        PaintingQuantity.doorCount: const Quantity(200, QuantityUnit.each),
        PaintingQuantity.windowCount: const Quantity(0, QuantityUnit.each),
      });
      expect(_pack.extraQuantityIds, everyElement(isIn(q.measured.keys)));
    });

    test('multiple sections add up before tax is applied once', () {
      final result = _ok(
        _engine.compute(
          Quote(
            sections: [
              QuoteSection(name: 'A', input: _room()),
              QuoteSection(name: 'B', input: _room()),
            ],
          ),
          _pack,
          _metric(),
          _vat,
        ),
      );
      // Default catalog: 31 500 labour + 3 tins (9 000), no prep line.
      expect(result.subtotal, 40500 * 2);
      expect(result.tax, 16200);
      expect(result.sections.map((s) => s.name), ['A', 'B']);
    });
  });

  group('properties', () {
    // Fixed seed: deterministic in CI. The engine itself never uses randomness.
    final random = Random(20261027);
    Length rand(int min, int max) =>
        Length.millimetres(min + random.nextInt(max - min + 1));

    test('totals are non-negative and lines match qty × price', () {
      for (var i = 0; i < 500; i++) {
        final result = _compute(
          SectionInput(
            values: {
              PaintingField.length: LengthValue(rand(1, 20000)),
              PaintingField.width: LengthValue(rand(1, 20000)),
              PaintingField.height: LengthValue(rand(1, 6000)),
              PaintingField.openings: OpeningsValue([
                for (var o = random.nextInt(4); o > 0; o--)
                  Opening(
                    width: rand(1, 3000),
                    height: rand(1, 3000),
                    count: 1 + random.nextInt(3),
                  ),
              ]),
              PaintingField.coats: WholeNumberValue(1 + random.nextInt(4)),
              PaintingField.includeCeiling: ToggleValue(random.nextBool()),
              PaintingField.primer: ToggleValue(random.nextBool()),
              PaintingField.surfaceCondition: ChoiceValue(
                const ['good', 'fair', 'poor'][random.nextInt(3)],
              ),
            },
          ),
          prices: _metric(markup: random.nextInt(5000)),
        );
        final totals = _ok(result);
        expect(totals.subtotal, greaterThanOrEqualTo(0));
        expect(totals.total, greaterThanOrEqualTo(totals.subtotal));
        for (final line in totals.lines) {
          expect(line.qtyHundredths, greaterThan(0));
          final exact = line.qtyHundredths * line.unitPrice;
          expect((line.total * 100 - exact).abs() * 2, lessThanOrEqualTo(100));
        }
      }
    });
  });
}
