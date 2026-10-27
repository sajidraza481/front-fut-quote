// Runs every golden vector in test/vectors/ (spec: docs/design/
// painting-pack-vectors.md). Expected values are approved hand calculations;
// never regenerate them from engine output.
import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';
import 'package:quote_engine/quote_engine.dart';
import 'package:test/test.dart';

typedef Json = Map<String, Object?>;

const _packs = <String, TradePack>{'painting': PaintingPack()};

void main() {
  final schema = JsonSchema.create(
    File('test/vectors/schema.json').readAsStringSync(),
  );
  final files =
      Directory('test/vectors')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) => f.path.endsWith('.json') && !f.path.endsWith('schema.json'),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('v11 uses the default UK catalog unchanged', () {
    final v11 = files.singleWhere((f) => f.path.contains('v11-'));
    final doc = jsonDecode(v11.readAsStringSync()) as Json;
    String describe(CatalogItem i) =>
        '${i.code}|${i.name}|${i.kind.name}|${i.unit.name}|${i.unitPrice}|'
        '${i.coverageHundredths}|${i.packSizeHundredths}|${i.wasteBasisPoints}';
    expect(
      _priceList(doc['priceList']! as Json).items.values.map(describe),
      const PaintingPack().defaultCatalog(UnitSystem.metric).map(describe),
    );
  });

  test(
    'vector files exist',
    () => expect(files, hasLength(greaterThanOrEqualTo(11))),
  );

  for (final file in files) {
    final raw = jsonDecode(file.readAsStringSync());
    final doc = raw as Json;
    group(doc['id'], () {
      test('matches schema', () {
        final result = schema.validate(raw);
        expect(result.isValid, isTrue, reason: result.errors.join('\n'));
      });

      test('computes the approved lines and totals', () {
        final pack = _packs[doc['pack']]!;
        final result = const QuoteEngine().compute(
          Quote(
            sections: [for (final s in _list(doc['sections'])) _section(s)],
          ),
          pack,
          _priceList(doc['priceList']! as Json),
          TaxRule(doc['taxBasisPoints']! as int),
          traderDefaults: _fields(
            (doc['traderDefaults'] ?? <String, Object?>{}) as Json,
          ),
        );
        final totals = switch (result) {
          Ok(:final value) => value,
          Invalid(:final errors) => fail('invalid input: $errors'),
        };
        final expected = doc['expected']! as Json;
        expect([
          for (final l in totals.lines)
            {
              'code': l.code,
              'qtyHundredths': l.qtyHundredths,
              'unitPrice': l.unitPrice,
              'total': l.total,
            },
        ], expected['lines']);
        expect(totals.subtotal, expected['subtotal'], reason: 'subtotal');
        expect(totals.tax, expected['tax'], reason: 'tax');
        expect(totals.total, expected['total'], reason: 'total');
      });
    });
  }
}

List<Json> _list(Object? value) => (value! as List<Object?>).cast<Json>();

PriceList _priceList(Json json) => PriceList(
  unitSystem: UnitSystem.values.byName(json['unitSystem']! as String),
  markupBasisPoints: json['markupBasisPoints']! as int,
  items: [
    for (final i in _list(json['items']))
      CatalogItem(
        code: i['code']! as String,
        name: i['name']! as String,
        kind: ItemKind.values.byName(i['kind']! as String),
        unit: QuantityUnit.values.byName(i['unit']! as String),
        unitPrice: i['unitPrice'] as int?,
        coverageHundredths: i['coverageHundredths'] as int?,
        packSizeHundredths: (i['packSizeHundredths'] ?? 100) as int,
        wasteBasisPoints: (i['wasteBasisPoints'] ?? 0) as int,
      ),
  ],
);

QuoteSection _section(Json json) => QuoteSection(
  name: json['name']! as String,
  input: SectionInput(
    values: _fields(json['fields']! as Json),
    extras: [
      for (final e in _list(json['extras'] ?? <Object?>[]))
        ExtraInput(
          itemCode: e['item']! as String,
          source: switch (e) {
            {'quantity': final String id} => FromQuantity(id),
            {'count': final int n} => CountOf(n),
            {'entered': final int qty} => Entered(qty),
            _ => const Flat(),
          },
          unitPrice: e['unitPrice'] as int?,
        ),
    ],
  ),
);

Map<String, FieldValue> _fields(Json json) => {
  for (final MapEntry(:key, :value) in json.entries)
    key: switch (value) {
      final Json length => LengthValue(_length(length)),
      final List<Object?> openings => OpeningsValue([
        for (final o in openings.cast<Json>())
          Opening(
            width: _length(o['width']! as Json),
            height: _length(o['height']! as Json),
            count: (o['count'] ?? 1) as int,
            kind: OpeningKind.values.byName((o['kind'] ?? 'other') as String),
          ),
      ]),
      final int n => WholeNumberValue(n),
      final bool b => ToggleValue(b),
      final String s => ChoiceValue(s),
      _ => throw FormatException('Unsupported field value for $key: $value'),
    },
};

Length _length(Json json) => switch (json) {
  {'m': final String m} => Length.parseMetres(m),
  _ => Length.imperial(
    feet: json['ft']! as int,
    inches: (json['in'] ?? 0) as int,
    sixteenths: (json['sixteenths'] ?? 0) as int,
  ),
};
