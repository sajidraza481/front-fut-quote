import 'package:meta/meta.dart';
import 'package:quote_engine/src/catalog.dart';
import 'package:quote_engine/src/rounding.dart';
import 'package:quote_engine/src/units.dart';

/// A priced line on a quote. Snapshotted when the quote is sent (BRIEF §6).
@immutable
final class LineItem {
  const new _({
    required this.code,
    required this.description,
    required this.kind,
    required this.unit,
    required this.packSizeHundredths,
    required this.qtyHundredths,
    required this.unitPrice,
    required this.isPriceOverride,
    required this.total,
  });

  /// Prices [qtyHundredths] of [item] (packs, for packed items).
  ///
  /// Material prices include the business markup inside the unit price,
  /// rounded half-up; the line total is then rounded half-up at line level
  /// (BRIEF §7). A [priceOverride] is the trader's per-quote price for an
  /// extra: used as-is, without markup, and flagged in the snapshot.
  factory price(
    CatalogItem item, {
    required int qtyHundredths,
    required int markupBasisPoints,
    int? priceOverride,
  }) {
    final listPrice = item.unitPrice;
    final int unitPrice;
    if (priceOverride != null) {
      unitPrice = priceOverride;
    } else if (listPrice == null) {
      throw ArgumentError('${item.code} has no price; validate first');
    } else {
      unitPrice = item.kind == ItemKind.material
          ? applyBasisPoints(listPrice, basisPointsPerUnit + markupBasisPoints)
          : listPrice;
    }
    return LineItem._(
      code: item.code,
      description: item.name,
      kind: item.kind,
      unit: item.unit,
      packSizeHundredths: item.packSizeHundredths,
      qtyHundredths: qtyHundredths,
      unitPrice: unitPrice,
      isPriceOverride: priceOverride != null,
      total: lineTotal(qtyHundredths: qtyHundredths, unitPrice: unitPrice),
    );
  }

  /// Price-list code.
  final String code;

  /// Shown on the quote.
  final String description;

  /// Material, labour or flat.
  final ItemKind kind;

  /// Unit of measure (inside the pack, for packed items).
  final QuantityUnit unit;

  /// Units per pack in hundredths; 100 when not packed.
  final int packSizeHundredths;

  /// Quantity in hundredths: packs for packed items (3 tins → 300),
  /// otherwise [unit]s (63.82 m² → 6382).
  final int qtyHundredths;

  /// Unit price shown to the customer, markup included, in minor units.
  final int unitPrice;

  /// True when the trader typed this price on the quote.
  final bool isPriceOverride;

  /// Line total in minor units.
  final int total;

  @override
  String toString() =>
      'LineItem($code, qty ${qtyHundredths / 100} @ $unitPrice = $total)';
}
