import 'package:meta/meta.dart';
import 'package:quote_engine/src/units.dart';

/// What a price item charges for. Markup applies to [material] only.
enum ItemKind {
  /// Goods the trader buys (paint, primer). Business markup applies.
  material,

  /// Work charged by quantity.
  labour,

  /// A fixed charge.
  flat,
}

/// A priced item in a trader's price list (BRIEF §6 `price_items`).
@immutable
final class CatalogItem {
  /// Creates an item.
  ///
  /// Items consumed by area (paint) need [coverageHundredths]: area covered
  /// per [unit], in hundredths of the price list's area unit (12 m²/L →
  /// 1200). They are sold in packs of [packSizeHundredths] units (2.5 L tin →
  /// 250) after adding [wasteBasisPoints] (10 % → 1000).
  const new({
    required this.code,
    required this.name,
    required this.kind,
    required this.unit,
    required this.unitPrice,
    this.coverageHundredths,
    this.packSizeHundredths = 100,
    this.wasteBasisPoints = 0,
  }) : assert(packSizeHundredths > 0, 'pack size must be > 0'),
       assert(wasteBasisPoints >= 0, 'waste must be >= 0');

  /// Stable code, unique within a price list.
  final String code;

  /// Line description shown on the quote.
  final String name;

  /// Material, labour or flat.
  final ItemKind kind;

  /// Unit of measure; for packed items, the unit inside the pack (litre).
  final QuantityUnit unit;

  /// Price per [unit] — or per pack for packed items — in minor units,
  /// before markup. Null means the price is entered on each quote.
  final int? unitPrice;

  /// Area covered per [unit], for consumables; null otherwise.
  final int? coverageHundredths;

  /// Units per pack, in hundredths; 100 = sold by the single unit.
  final int packSizeHundredths;

  /// Waste added before rounding up to whole packs, in basis points.
  final int wasteBasisPoints;
}

/// A trader's prices for one trade, plus the business markup (BRIEF §6).
@immutable
final class PriceList {
  /// Creates a price list. Codes in [items] must be unique.
  new({
    required this.unitSystem,
    required Iterable<CatalogItem> items,
    this.markupBasisPoints = 0,
  }) : items = Map.unmodifiable({for (final i in items) i.code: i}) {
    if (markupBasisPoints < 0) {
      throw ArgumentError.value(markupBasisPoints, 'markupBasisPoints');
    }
  }

  /// Units every quantity is priced in.
  final UnitSystem unitSystem;

  /// Items by code.
  final Map<String, CatalogItem> items;

  /// Business markup on materials, in basis points (15 % → 1500).
  final int markupBasisPoints;
}
