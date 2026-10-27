import 'package:meta/meta.dart';
import 'package:quote_engine/src/catalog.dart';
import 'package:quote_engine/src/fields.dart';
import 'package:quote_engine/src/line_item.dart';
import 'package:quote_engine/src/result.dart';
import 'package:quote_engine/src/units.dart';

/// Kinds of measurement a pack works with (BRIEF §7).
enum MeasurementKind {
  /// m² / ft².
  area,

  /// m / ft.
  linear,

  /// m³ / ft³.
  volume,

  /// Items.
  count,

  /// Fixed.
  flat,
}

/// A measured amount in hundredths of [unit].
@immutable
final class Quantity {
  /// Creates a quantity.
  const new(this.hundredths, this.unit);

  /// Amount in hundredths (31.91 m² → 3191).
  final int hundredths;

  /// Unit, in the price list's unit system.
  final QuantityUnit unit;

  @override
  bool operator ==(Object other) =>
      other is Quantity && other.hundredths == hundredths && other.unit == unit;

  @override
  int get hashCode => Object.hash(hundredths, unit);

  @override
  String toString() => 'Quantity(${hundredths / 100} ${unit.name})';
}

/// Output of [TradePack.quantities]: geometry turned into quantities.
@immutable
final class QuantitySet {
  /// Creates a set.
  const new({required this.measured, required this.lines});

  /// Named measured quantities (spec §2), e.g. `netWallArea`.
  final Map<String, Quantity> measured;

  /// Pack-internal quantity per price-list code, in hundredths. For items
  /// with coverage this is the area to cover, not the units to buy.
  final Map<String, int> lines;
}

/// A trade's fields, quantity rules and pricing (BRIEF §7). The PDF template
/// spec is added with on-device PDFs in Phase 1.
abstract interface class TradePack {
  /// Stable id, e.g. `painting`.
  String get id;

  /// Bumped when fields or quantity rules change; stored with measurements.
  int get schemaVersion;

  /// Measurement kinds used.
  List<MeasurementKind> get kinds;

  /// Seed catalog for a new price list.
  List<CatalogItem> defaultCatalog(UnitSystem system);

  /// Section inputs, with pack defaults and limits.
  List<FieldSpec> sectionFields();

  /// Measured quantities extras may be priced against.
  Set<String> get extraQuantityIds;

  /// Quantity source the app pre-selects when a trader adds an extra, by
  /// price-list code (e.g. window frames → `windowCount`). Extras not listed
  /// start empty for the trader to type.
  Map<String, ExtraSource> get suggestedExtraSources;

  /// Problems that stop [prices] being used with this pack.
  List<InputError> validatePriceList(PriceList prices);

  /// Geometry → quantities, in [system] units.
  QuantitySet quantities(SectionFields fields, UnitSystem system);

  /// Quantities → priced pack lines (extras are priced by the engine).
  List<LineItem> price(QuantitySet quantities, PriceList prices);
}
