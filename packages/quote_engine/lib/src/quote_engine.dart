import 'package:meta/meta.dart';
import 'package:quote_engine/src/catalog.dart';
import 'package:quote_engine/src/fields.dart';
import 'package:quote_engine/src/line_item.dart';
import 'package:quote_engine/src/result.dart';
import 'package:quote_engine/src/rounding.dart';
import 'package:quote_engine/src/trade_pack.dart';
import 'package:quote_engine/src/units.dart';

/// One room or area of a quote.
@immutable
final class QuoteSection {
  /// Creates a section.
  const new({required this.name, required this.input});

  /// Trader's label, e.g. "Living room".
  final String name;

  /// What the trader entered.
  final SectionInput input;
}

/// The parts of a quote the engine prices.
@immutable
final class Quote {
  /// Creates a quote.
  const new({required this.sections});

  /// Sections in display order.
  final List<QuoteSection> sections;
}

/// Tax on the subtotal, rounded half-up once. Prices are tax-exclusive.
@immutable
final class TaxRule {
  /// Tax at [basisPoints] (20 % → 2000).
  const new(this.basisPoints) : assert(basisPoints >= 0, 'rate < 0');

  /// No tax.
  static const TaxRule none = TaxRule(0);

  /// Rate in basis points.
  final int basisPoints;
}

/// Priced lines of one section.
@immutable
final class SectionTotals {
  /// Creates section totals.
  const new({required this.name, required this.lines});

  /// Section name.
  final String name;

  /// Pack lines then extras; zero-quantity and 0p lines omitted.
  final List<LineItem> lines;

  /// Sum of line totals.
  int get subtotal => lines.fold(0, (sum, l) => sum + l.total);
}

/// Priced quote. All amounts in minor units.
@immutable
final class QuoteTotals {
  /// Creates totals.
  const new({
    required this.sections,
    required this.subtotal,
    required this.tax,
  });

  /// Per-section lines.
  final List<SectionTotals> sections;

  /// Σ line totals.
  final int subtotal;

  /// Tax on [subtotal].
  final int tax;

  /// [subtotal] + [tax].
  int get total => subtotal + tax;

  /// Every line, in order.
  Iterable<LineItem> get lines => sections.expand((s) => s.lines);
}

/// Prices a quote. Pure: same inputs → same totals (ADR-001).
final class QuoteEngine {
  /// Creates the engine.
  const new();

  /// Validates and prices [quote]. Field values resolve section value →
  /// [traderDefaults] → pack default. Errors in sections are reported as
  /// `sections[i].<field>`.
  Result<QuoteTotals> compute(
    Quote quote,
    TradePack pack,
    PriceList prices,
    TaxRule tax, {
    Map<String, FieldValue> traderDefaults = const {},
  }) {
    final errors = <InputError>[...pack.validatePriceList(prices)];
    final specs = pack.sectionFields();
    final sections = <SectionTotals>[];

    for (final (i, section) in quote.sections.indexed) {
      void report(List<InputError> found) => errors.addAll(
        found.map(
          (e) => InputError('sections[$i].${e.field}', e.code, e.detail),
        ),
      );
      final resolved = _resolveFields(
        specs,
        section.input,
        traderDefaults,
        prices,
      );
      if (resolved.errors.isNotEmpty) {
        report(resolved.errors);
        continue;
      }
      final quantities = pack.quantities(
        SectionFields(resolved.values),
        prices.unitSystem,
      );
      final extraErrors = _validateExtras(
        section.input.extras,
        pack,
        prices,
        quantities,
      );
      if (extraErrors.isNotEmpty) {
        report(extraErrors);
        continue;
      }
      if (errors.isNotEmpty) continue; // only collecting errors from here on
      sections.add(
        SectionTotals(
          name: section.name,
          lines:
              [
                    ...pack.price(quantities, prices),
                    ..._priceExtras(section.input.extras, quantities, prices),
                  ]
                  .where((l) => l.unitPrice > 0)
                  .toList(), // 0p rates: no line (spec §3)
        ),
      );
    }

    if (errors.isNotEmpty) return Invalid(errors);
    final subtotal = sections.fold(0, (sum, s) => sum + s.subtotal);
    return Ok(
      QuoteTotals(
        sections: sections,
        subtotal: subtotal,
        tax: applyBasisPoints(subtotal, tax.basisPoints),
      ),
    );
  }

  ({Map<String, FieldValue> values, List<InputError> errors}) _resolveFields(
    List<FieldSpec> specs,
    SectionInput input,
    Map<String, FieldValue> traderDefaults,
    PriceList prices,
  ) {
    final errors = <InputError>[];
    final values = <String, FieldValue>{};
    final known = {for (final s in specs) s.id};
    for (final id in input.values.keys) {
      if (!known.contains(id)) errors.add(InputError(id, 'unknownField'));
    }
    for (final spec in specs) {
      final value =
          input.values[spec.id] ?? traderDefaults[spec.id] ?? spec.defaultValue;
      if (value == null) {
        errors.add(InputError(spec.id, 'required'));
        continue;
      }
      final problem = _check(spec, value, prices);
      if (problem != null) {
        errors.add(InputError(spec.id, problem));
        continue;
      }
      values[spec.id] = value;
    }
    return (values: values, errors: errors);
  }

  String? _check(FieldSpec spec, FieldValue value, PriceList prices) {
    if (value.type != spec.type) return 'wrongType';
    bool inRange(int v) =>
        (spec.min == null || v >= spec.min!) &&
        (spec.max == null || v <= spec.max!);
    return switch (value) {
      LengthValue(:final value) when !inRange(value.tenthsOfMillimetre) =>
        'outOfRange',
      WholeNumberValue(:final value) when !inRange(value) => 'outOfRange',
      ChoiceValue(:final value) when !spec.choices.contains(value) =>
        'invalidChoice',
      OpeningsValue(:final value)
          when value.any(
            (o) =>
                o.count < 1 ||
                o.width.tenthsOfMillimetre == 0 ||
                o.height.tenthsOfMillimetre == 0,
          ) =>
        'outOfRange',
      PriceItemValue(:final code) when prices.items[code] == null =>
        'unknownItem',
      PriceItemValue(:final code) when !_canReplace(spec, code, prices) =>
        'unitMismatch',
      _ => null,
    };
  }

  /// A chosen item must be a packed material sold in the same unit as the
  /// pack's standard item for that line (litres for litres). The standard
  /// item itself is checked by [TradePack.validatePriceList].
  bool _canReplace(FieldSpec spec, String code, PriceList prices) {
    final standardCode = switch (spec.defaultValue) {
      PriceItemValue(:final code) => code,
      _ => null,
    };
    if (code == standardCode) return true;
    final item = prices.items[code]!;
    return item.kind == ItemKind.material &&
        item.coverageHundredths != null &&
        item.unit == prices.items[standardCode]?.unit;
  }

  List<InputError> _validateExtras(
    List<ExtraInput> extras,
    TradePack pack,
    PriceList prices,
    QuantitySet quantities,
  ) {
    final errors = <InputError>[];
    for (final (i, extra) in extras.indexed) {
      final field = 'extras[$i]';
      final item = prices.items[extra.itemCode];
      if (item == null) {
        errors.add(InputError(field, 'unknownItem', extra.itemCode));
        continue;
      }
      final problem = switch (extra.source) {
        FromQuantity(:final quantityId)
            when !pack.extraQuantityIds.contains(quantityId) =>
          'unknownQuantity',
        // An extra priced per m² must use an area quantity, and so on.
        FromQuantity(:final quantityId)
            when quantities.measured[quantityId]?.unit != item.unit =>
          'unitMismatch',
        CountOf(:final count) when count < 1 => 'outOfRange',
        CountOf() ||
        // Counted in items, or in packs for a consumable sold in packs.
        Flat()
            when item.unit != QuantityUnit.each &&
                item.coverageHundredths == null =>
          'unitMismatch',
        Entered(:final qtyHundredths) when qtyHundredths <= 0 => 'outOfRange',
        // Whole items are counted, not typed as decimals.
        Entered() when item.unit == QuantityUnit.each => 'unitMismatch',
        _ when extra.unitPrice == null && item.unitPrice == null =>
          'priceRequired',
        _ when (extra.unitPrice ?? 0) < 0 => 'outOfRange',
        _ => null,
      };
      if (problem != null) errors.add(InputError(field, problem));
    }
    return errors;
  }

  List<LineItem> _priceExtras(
    List<ExtraInput> extras,
    QuantitySet quantities,
    PriceList prices,
  ) => [
    for (final extra in extras)
      if (_extraQuantity(extra.source, quantities) case final qty when qty > 0)
        LineItem.price(
          prices.items[extra.itemCode]!,
          qtyHundredths: qty,
          markupBasisPoints: prices.markupBasisPoints,
          priceOverride: extra.unitPrice,
        ),
  ];

  int _extraQuantity(ExtraSource source, QuantitySet quantities) =>
      switch (source) {
        FromQuantity(:final quantityId) =>
          quantities.measured[quantityId]!.hundredths,
        CountOf(:final count) => count * 100,
        Entered(:final qtyHundredths) => qtyHundredths,
        Flat() => 100,
      };
}
