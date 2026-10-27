import 'package:quote_engine/src/catalog.dart';
import 'package:quote_engine/src/fields.dart';
import 'package:quote_engine/src/geometry.dart';
import 'package:quote_engine/src/line_item.dart';
import 'package:quote_engine/src/result.dart';
import 'package:quote_engine/src/trade_pack.dart';
import 'package:quote_engine/src/units.dart';

/// Field ids (spec §1).
abstract final class PaintingField {
  /// Room length.
  static const length = 'length';

  /// Room width.
  static const width = 'width';

  /// Wall height.
  static const height = 'height';

  /// Doors, windows and other openings.
  static const openings = 'openings';

  /// Finish coats.
  static const coats = 'coats';

  /// Paint the ceiling.
  static const includeCeiling = 'includeCeiling';

  /// One primer coat.
  static const primer = 'primer';

  /// good / fair / poor; selects the prep rate.
  static const surfaceCondition = 'surfaceCondition';

  /// Price item supplying wall paint (e.g. 5 L instead of 2.5 L tins).
  static const wallPaintItem = 'wallPaintItem';

  /// Price item supplying ceiling paint.
  static const ceilingPaintItem = 'ceilingPaintItem';

  /// Price item supplying primer.
  static const primerItem = 'primerItem';
}

/// Measured quantity ids (spec §2).
abstract final class PaintingQuantity {
  /// 2 × (length + width) × height.
  static const grossWallArea = 'grossWallArea';

  /// Σ opening areas.
  static const openingsArea = 'openingsArea';

  /// Walls minus openings, clamped at 0.
  static const netWallArea = 'netWallArea';

  /// length × width if the ceiling is painted, else 0.
  static const ceilingArea = 'ceilingArea';

  /// netWallArea + ceilingArea, counted once. Used by prep and primer.
  static const surfaceArea = 'surfaceArea';

  /// surfaceArea × coats. Used by painting labour and paint.
  static const coatedArea = 'coatedArea';

  /// 2 × (length + width), linear.
  static const perimeter = 'perimeter';

  /// Number of openings of any kind.
  static const openingsCount = 'openingsCount';

  /// Number of door openings.
  static const doorCount = 'doorCount';

  /// Number of window openings.
  static const windowCount = 'windowCount';
}

/// Price-list codes the pack prices (spec §3), in line order.
abstract final class PaintingCode {
  /// Wall labour.
  static const wallPainting = 'wall_painting';

  /// Wall paint.
  static const wallPaint = 'wall_paint';

  /// Ceiling labour.
  static const ceilingPainting = 'ceiling_painting';

  /// Ceiling paint.
  static const ceilingPaint = 'ceiling_paint';

  /// Prep, good surface.
  static const prepGood = 'prep_good';

  /// Prep, fair surface.
  static const prepFair = 'prep_fair';

  /// Prep, poor surface.
  static const prepPoor = 'prep_poor';

  /// Primer labour.
  static const primerApplication = 'primer_application';

  /// Primer material.
  static const primer = 'primer';

  /// Every code, in line order: labour before its material.
  static const List<String> all = [
    wallPainting,
    wallPaint,
    ceilingPainting,
    ceilingPaint,
    prepGood,
    prepFair,
    prepPoor,
    primerApplication,
    primer,
  ];

  /// Consumables bought in whole packs by coverage.
  static const Set<String> consumables = {wallPaint, ceilingPaint, primer};

  /// Prep code for a surface condition.
  static String prepFor(String condition) => 'prep_$condition';
}

/// Codes of the launch extras in the UK catalog (spec §4.2).
abstract final class PaintingExtra {
  /// Wall paint in 5 L tins; alternative to the 2.5 L tin.
  static const wallPaint5l = 'wall_paint_5l';

  /// Skirting boards, per linear metre typed in.
  static const skirtingBoards = 'skirting_boards';

  /// Doors, both sides, by count.
  static const doors = 'doors';

  /// Door frames / architraves, by count.
  static const doorFrames = 'door_frames';

  /// Window frames and sills; count defaults to the room's windows.
  static const windowFrames = 'window_frames';

  /// Radiators, by count.
  static const radiators = 'radiators';

  /// Wallpaper removal, per m² of net wall.
  static const wallpaperRemoval = 'wallpaper_removal';

  /// Stain block / mould treatment, per m² typed in.
  static const stainBlock = 'stain_block';

  /// High access (tower / scaffold); price entered on each quote.
  static const highAccess = 'high_access';

  /// Protection and furniture moving, flat per room.
  static const protection = 'protection';
}

/// Painting TradePack (pack #1). See docs/design/painting-pack-vectors.md.
final class PaintingPack implements TradePack {
  /// Creates the pack.
  const new();

  static const _conditions = ['good', 'fair', 'poor'];

  @override
  String get id => 'painting';

  @override
  int get schemaVersion => 1;

  @override
  List<MeasurementKind> get kinds => const [
    MeasurementKind.area,
    MeasurementKind.linear,
    MeasurementKind.count,
  ];

  @override
  List<FieldSpec> sectionFields() => const [
    FieldSpec(
      id: PaintingField.length,
      type: FieldType.length,
      min: 1,
      max: 1000000,
    ),
    FieldSpec(
      id: PaintingField.width,
      type: FieldType.length,
      min: 1,
      max: 1000000,
    ),
    FieldSpec(
      id: PaintingField.height,
      type: FieldType.length,
      min: 1,
      max: 100000,
    ),
    FieldSpec(
      id: PaintingField.openings,
      type: FieldType.openings,
      defaultValue: OpeningsValue([]),
    ),
    FieldSpec(
      id: PaintingField.coats,
      type: FieldType.wholeNumber,
      defaultValue: WholeNumberValue(2),
      min: 1,
      max: 4,
    ),
    FieldSpec(
      id: PaintingField.includeCeiling,
      type: FieldType.toggle,
      defaultValue: ToggleValue(false),
    ),
    FieldSpec(
      id: PaintingField.primer,
      type: FieldType.toggle,
      defaultValue: ToggleValue(false),
    ),
    FieldSpec(
      id: PaintingField.surfaceCondition,
      type: FieldType.choice,
      defaultValue: ChoiceValue('good'),
      choices: _conditions,
    ),
    // Which tin each consumable line uses. Defaults to the pack's standard
    // item; a trader default or the room can pick another pack size.
    FieldSpec(
      id: PaintingField.wallPaintItem,
      type: FieldType.priceItem,
      defaultValue: PriceItemValue(PaintingCode.wallPaint),
    ),
    FieldSpec(
      id: PaintingField.ceilingPaintItem,
      type: FieldType.priceItem,
      defaultValue: PriceItemValue(PaintingCode.ceilingPaint),
    ),
    FieldSpec(
      id: PaintingField.primerItem,
      type: FieldType.priceItem,
      defaultValue: PriceItemValue(PaintingCode.primer),
    ),
  ];

  @override
  Set<String> get extraQuantityIds => const {
    PaintingQuantity.netWallArea,
    PaintingQuantity.ceilingArea,
    PaintingQuantity.surfaceArea,
    PaintingQuantity.perimeter,
    PaintingQuantity.openingsCount,
    PaintingQuantity.doorCount,
    PaintingQuantity.windowCount,
  };

  @override
  Map<String, ExtraSource> get suggestedExtraSources => const {
    PaintingExtra.windowFrames: FromQuantity(PaintingQuantity.windowCount),
    PaintingExtra.wallpaperRemoval: FromQuantity(PaintingQuantity.netWallArea),
    PaintingExtra.highAccess: Flat(),
    PaintingExtra.protection: Flat(),
  };

  /// All rates are placeholders the trader edits. Launch extras are in the
  /// metric (UK) catalog only until a US launch.
  @override
  List<CatalogItem> defaultCatalog(UnitSystem system) => switch (system) {
    UnitSystem.metric => const [..._metricPackItems, ..._ukExtras],
    UnitSystem.imperial => _imperialPackItems,
  };

  static const _metricPackItems = [
    CatalogItem(
      code: PaintingCode.wallPainting,
      name: 'Wall painting',
      kind: ItemKind.labour,
      unit: QuantityUnit.squareMetre,
      unitPrice: 450,
    ),
    CatalogItem(
      code: PaintingCode.wallPaint,
      name: 'Wall paint (2.5 L tin)',
      kind: ItemKind.material,
      unit: QuantityUnit.litre,
      unitPrice: 3000,
      coverageHundredths: 1200,
      packSizeHundredths: 250,
      wasteBasisPoints: 1000,
    ),
    CatalogItem(
      code: PaintingCode.ceilingPainting,
      name: 'Ceiling painting',
      kind: ItemKind.labour,
      unit: QuantityUnit.squareMetre,
      unitPrice: 550,
    ),
    CatalogItem(
      code: PaintingCode.ceilingPaint,
      name: 'Ceiling paint (2.5 L tin)',
      kind: ItemKind.material,
      unit: QuantityUnit.litre,
      unitPrice: 3000,
      coverageHundredths: 1200,
      packSizeHundredths: 250,
      wasteBasisPoints: 1000,
    ),
    CatalogItem(
      code: PaintingCode.prepGood,
      name: 'Preparation (good)',
      kind: ItemKind.labour,
      unit: QuantityUnit.squareMetre,
      unitPrice: 0,
    ),
    CatalogItem(
      code: PaintingCode.prepFair,
      name: 'Preparation (fair)',
      kind: ItemKind.labour,
      unit: QuantityUnit.squareMetre,
      unitPrice: 150,
    ),
    CatalogItem(
      code: PaintingCode.prepPoor,
      name: 'Preparation (poor)',
      kind: ItemKind.labour,
      unit: QuantityUnit.squareMetre,
      unitPrice: 300,
    ),
    CatalogItem(
      code: PaintingCode.primerApplication,
      name: 'Primer application',
      kind: ItemKind.labour,
      unit: QuantityUnit.squareMetre,
      unitPrice: 300,
    ),
    CatalogItem(
      code: PaintingCode.primer,
      name: 'Primer',
      kind: ItemKind.material,
      unit: QuantityUnit.litre,
      unitPrice: 1000,
      coverageHundredths: 1000,
    ),
  ];

  static const _ukExtras = [
    CatalogItem(
      code: PaintingExtra.wallPaint5l,
      name: 'Wall paint (5 L tin)',
      kind: ItemKind.material,
      unit: QuantityUnit.litre,
      unitPrice: 5500,
      coverageHundredths: 1200,
      packSizeHundredths: 500,
      wasteBasisPoints: 1000,
    ),
    CatalogItem(
      code: PaintingExtra.skirtingBoards,
      name: 'Skirting boards',
      kind: ItemKind.labour,
      unit: QuantityUnit.metre,
      unitPrice: 400,
    ),
    CatalogItem(
      code: PaintingExtra.doors,
      name: 'Doors (both sides)',
      kind: ItemKind.labour,
      unit: QuantityUnit.each,
      unitPrice: 4500,
    ),
    CatalogItem(
      code: PaintingExtra.doorFrames,
      name: 'Door frames / architraves',
      kind: ItemKind.labour,
      unit: QuantityUnit.each,
      unitPrice: 2000,
    ),
    CatalogItem(
      code: PaintingExtra.windowFrames,
      name: 'Window frames and sills',
      kind: ItemKind.labour,
      unit: QuantityUnit.each,
      unitPrice: 2500,
    ),
    CatalogItem(
      code: PaintingExtra.radiators,
      name: 'Radiators',
      kind: ItemKind.labour,
      unit: QuantityUnit.each,
      unitPrice: 2500,
    ),
    CatalogItem(
      code: PaintingExtra.wallpaperRemoval,
      name: 'Wallpaper removal',
      kind: ItemKind.labour,
      unit: QuantityUnit.squareMetre,
      unitPrice: 500,
    ),
    CatalogItem(
      code: PaintingExtra.stainBlock,
      name: 'Stain block / mould treatment',
      kind: ItemKind.labour,
      unit: QuantityUnit.squareMetre,
      unitPrice: 800,
    ),
    CatalogItem(
      code: PaintingExtra.highAccess,
      name: 'High access (tower/scaffold)',
      kind: ItemKind.flat,
      unit: QuantityUnit.each,
      unitPrice: null,
    ),
    CatalogItem(
      code: PaintingExtra.protection,
      name: 'Protection and furniture moving',
      kind: ItemKind.flat,
      unit: QuantityUnit.each,
      unitPrice: 2500,
    ),
  ];

  static const _imperialPackItems = [
    CatalogItem(
      code: PaintingCode.wallPainting,
      name: 'Wall painting',
      kind: ItemKind.labour,
      unit: QuantityUnit.squareFoot,
      unitPrice: 45,
    ),
    CatalogItem(
      code: PaintingCode.wallPaint,
      name: 'Wall paint',
      kind: ItemKind.material,
      unit: QuantityUnit.usGallon,
      unitPrice: 4200,
      coverageHundredths: 35000,
    ),
    CatalogItem(
      code: PaintingCode.ceilingPainting,
      name: 'Ceiling painting',
      kind: ItemKind.labour,
      unit: QuantityUnit.squareFoot,
      unitPrice: 55,
    ),
    CatalogItem(
      code: PaintingCode.ceilingPaint,
      name: 'Ceiling paint',
      kind: ItemKind.material,
      unit: QuantityUnit.usGallon,
      unitPrice: 3800,
      coverageHundredths: 35000,
    ),
    CatalogItem(
      code: PaintingCode.prepGood,
      name: 'Preparation (good)',
      kind: ItemKind.labour,
      unit: QuantityUnit.squareFoot,
      unitPrice: 0,
    ),
    CatalogItem(
      code: PaintingCode.prepFair,
      name: 'Preparation (fair)',
      kind: ItemKind.labour,
      unit: QuantityUnit.squareFoot,
      unitPrice: 14,
    ),
    CatalogItem(
      code: PaintingCode.prepPoor,
      name: 'Preparation (poor)',
      kind: ItemKind.labour,
      unit: QuantityUnit.squareFoot,
      unitPrice: 28,
    ),
    CatalogItem(
      code: PaintingCode.primerApplication,
      name: 'Primer application',
      kind: ItemKind.labour,
      unit: QuantityUnit.squareFoot,
      unitPrice: 30,
    ),
    CatalogItem(
      code: PaintingCode.primer,
      name: 'Primer',
      kind: ItemKind.material,
      unit: QuantityUnit.usGallon,
      unitPrice: 3500,
      coverageHundredths: 30000,
    ),
  ];

  @override
  List<InputError> validatePriceList(PriceList prices) {
    final area = areaUnitOf(prices.unitSystem);
    final volume = switch (prices.unitSystem) {
      UnitSystem.metric => QuantityUnit.litre,
      UnitSystem.imperial => QuantityUnit.usGallon,
    };
    return [
      for (final code in PaintingCode.all)
        if (prices.items[code] case final item?) ...[
          if (item.unit !=
              (PaintingCode.consumables.contains(code) ? volume : area))
            InputError(code, 'unitMismatch'),
          if (PaintingCode.consumables.contains(code) &&
              (item.coverageHundredths ?? 0) <= 0)
            InputError(code, 'missingCoverage'),
          // Pack lines are priced from the price list only.
          if (item.unitPrice == null) InputError(code, 'priceRequired'),
        ] else
          InputError(code, 'missingPriceItem'),
    ];
  }

  @override
  QuantitySet quantities(SectionFields fields, UnitSystem system) {
    final length = fields.length(PaintingField.length);
    final width = fields.length(PaintingField.width);
    final height = fields.length(PaintingField.height);
    final openings = fields.openings(PaintingField.openings);
    final coats = fields.wholeNumber(PaintingField.coats);
    final condition = fields.choice(PaintingField.surfaceCondition);

    final halfPerimeter = length + width;
    final gross = halfPerimeter * height * 2;
    final openingsArea = openings.fold(
      Area.zero,
      (sum, o) => sum + o.width * o.height * o.count,
    );
    final ceiling = fields.toggle(PaintingField.includeCeiling)
        ? length * width
        : Area.zero;

    int area(Area a) => switch (system) {
      UnitSystem.metric => a.hundredthsOfSquareMetre,
      UnitSystem.imperial => a.hundredthsOfSquareFoot,
    };
    int count([OpeningKind? kind]) =>
        openings
            .where((o) => kind == null || o.kind == kind)
            .fold(0, (sum, o) => sum + o.count) *
        100;
    final perimeter = halfPerimeter + halfPerimeter;
    final netWall = area((gross - openingsArea).clampAtZero());
    final ceilingArea = area(ceiling);
    final surface = netWall + ceilingArea;
    final primer = fields.toggle(PaintingField.primer) ? surface : 0;

    final areaUnit = areaUnitOf(system);
    return QuantitySet(
      measured: {
        PaintingQuantity.grossWallArea: Quantity(area(gross), areaUnit),
        PaintingQuantity.openingsArea: Quantity(area(openingsArea), areaUnit),
        PaintingQuantity.netWallArea: Quantity(netWall, areaUnit),
        PaintingQuantity.ceilingArea: Quantity(ceilingArea, areaUnit),
        PaintingQuantity.surfaceArea: Quantity(surface, areaUnit),
        PaintingQuantity.coatedArea: Quantity(surface * coats, areaUnit),
        PaintingQuantity.perimeter: Quantity(switch (system) {
          UnitSystem.metric => perimeter.hundredthsOfMetre,
          UnitSystem.imperial => perimeter.hundredthsOfFoot,
        }, linearUnitOf(system)),
        PaintingQuantity.openingsCount: Quantity(count(), QuantityUnit.each),
        PaintingQuantity.doorCount: Quantity(
          count(OpeningKind.door),
          QuantityUnit.each,
        ),
        PaintingQuantity.windowCount: Quantity(
          count(OpeningKind.window),
          QuantityUnit.each,
        ),
      },
      // coatedArea split by surface, because walls and ceilings have
      // separate rates; prep and primer use surfaceArea (never × coats).
      lines: {
        PaintingCode.wallPainting: netWall * coats,
        PaintingCode.wallPaint: netWall * coats,
        PaintingCode.ceilingPainting: ceilingArea * coats,
        PaintingCode.ceilingPaint: ceilingArea * coats,
        PaintingCode.prepFor(condition): surface,
        PaintingCode.primerApplication: primer,
        PaintingCode.primer: primer,
      },
      itemCodes: {
        PaintingCode.wallPaint: fields.priceItem(PaintingField.wallPaintItem),
        PaintingCode.ceilingPaint: fields.priceItem(
          PaintingField.ceilingPaintItem,
        ),
        PaintingCode.primer: fields.priceItem(PaintingField.primerItem),
      },
    );
  }

  @override
  List<LineItem> price(QuantitySet quantities, PriceList prices) => [
    for (final code in PaintingCode.all)
      if (quantities.lines[code] case final qty? when qty > 0)
        if (prices.items[quantities.itemCodes[code] ?? code]! case final item)
          LineItem.price(
            item,
            qtyHundredths: PaintingCode.consumables.contains(code)
                ? _wholePacks(qty, item) * 100
                : qty,
            markupBasisPoints: prices.markupBasisPoints,
          ),
  ];

  /// Packs to buy: ⌈area ÷ coverage × (1 + waste) ÷ pack size⌉, computed
  /// exactly with no intermediate rounding (spec §3).
  static int _wholePacks(int areaHundredths, CatalogItem item) {
    final numerator = areaHundredths * (10000 + item.wasteBasisPoints) * 100;
    final denominator =
        item.coverageHundredths! * 10000 * item.packSizeHundredths;
    return (numerator + denominator - 1) ~/ denominator;
  }
}
