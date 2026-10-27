/// Unit system of a price list. Measurements may be entered in either system;
/// quantities are always expressed in the price list's system.
enum UnitSystem {
  /// m, m², litres.
  metric,

  /// ft, ft², US gallons.
  imperial,
}

/// The unit a quantity or price is expressed in.
enum QuantityUnit {
  /// Square metres.
  squareMetre,

  /// Square feet.
  squareFoot,

  /// Metres.
  metre,

  /// Feet.
  foot,

  /// Litres.
  litre,

  /// US gallons.
  usGallon,

  /// A count of items, or 1 for a flat price.
  each;

  /// Whether this is an area unit.
  bool get isArea => this == squareMetre || this == squareFoot;

  /// Whether this is a linear unit.
  bool get isLinear => this == metre || this == foot;
}

/// Area unit for a unit system.
QuantityUnit areaUnitOf(UnitSystem system) => switch (system) {
  UnitSystem.metric => QuantityUnit.squareMetre,
  UnitSystem.imperial => QuantityUnit.squareFoot,
};

/// Linear unit for a unit system.
QuantityUnit linearUnitOf(UnitSystem system) => switch (system) {
  UnitSystem.metric => QuantityUnit.metre,
  UnitSystem.imperial => QuantityUnit.foot,
};
