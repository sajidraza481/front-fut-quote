import 'package:meta/meta.dart';
import 'package:quote_engine/src/geometry.dart';

/// Input type of a section field; drives the input UI (BRIEF §7).
enum FieldType {
  /// A [Length], metric or imperial.
  length,

  /// A whole number, e.g. coats.
  wholeNumber,

  /// Yes / no.
  toggle,

  /// One of [FieldSpec.choices].
  choice,

  /// A list of [Opening]s.
  openings,
}

/// Declares one input of a TradePack section, with its pack default and
/// limits. Labels are localised in the app by [id].
@immutable
final class FieldSpec {
  /// Creates a spec. [min]/[max] are inclusive: tenths of a millimetre for
  /// lengths, the value itself for whole numbers.
  const new({
    required this.id,
    required this.type,
    this.defaultValue,
    this.min,
    this.max,
    this.choices = const [],
  });

  /// Stable id, also the key in `measurements.inputs`.
  final String id;

  /// Input type.
  final FieldType type;

  /// Pack default; null means the field is required.
  final FieldValue? defaultValue;

  /// Inclusive lower limit.
  final int? min;

  /// Inclusive upper limit.
  final int? max;

  /// Allowed values for [FieldType.choice].
  final List<String> choices;

  /// Whether the trader must enter a value.
  bool get isRequired => defaultValue == null;
}

/// A value for a section field.
sealed class FieldValue {
  const new();

  /// The [FieldType] this value satisfies.
  FieldType get type;
}

/// A length value.
@immutable
final class LengthValue extends FieldValue {
  /// Wraps [value].
  const new(this.value);

  /// The length.
  final Length value;

  @override
  FieldType get type => FieldType.length;
}

/// A whole-number value.
@immutable
final class WholeNumberValue extends FieldValue {
  /// Wraps [value].
  const new(this.value);

  /// The number.
  final int value;

  @override
  FieldType get type => FieldType.wholeNumber;
}

/// A yes / no value.
@immutable
final class ToggleValue extends FieldValue {
  /// Wraps [value]. Positional, like the other value wrappers.
  // ignore: avoid_positional_boolean_parameters
  const new(this.value);

  /// The flag.
  final bool value;

  @override
  FieldType get type => FieldType.toggle;
}

/// A choice value.
@immutable
final class ChoiceValue extends FieldValue {
  /// Wraps [value].
  const new(this.value);

  /// The chosen option.
  final String value;

  @override
  FieldType get type => FieldType.choice;
}

/// A list of openings.
@immutable
final class OpeningsValue extends FieldValue {
  /// Wraps [value].
  const new(this.value);

  /// The openings.
  final List<Opening> value;

  @override
  FieldType get type => FieldType.openings;
}

/// What an opening is; drives `doorCount` / `windowCount`.
enum OpeningKind {
  /// A door.
  door,

  /// A window.
  window,

  /// Anything else not painted (an arch, a fitted unit).
  other,
}

/// A door, window or other area not painted; [count] identical ones.
@immutable
final class Opening {
  /// Creates an opening.
  const new({
    required this.width,
    required this.height,
    this.count = 1,
    this.kind = OpeningKind.other,
  });

  /// Door, window or other.
  final OpeningKind kind;

  /// Width.
  final Length width;

  /// Height.
  final Length height;

  /// Number of identical openings, ≥ 1.
  final int count;
}

/// Where an extra line's quantity comes from (spec §4.1).
sealed class ExtraSource {
  const new();
}

/// Quantity taken from a measured quantity the pack exposes to extras.
@immutable
final class FromQuantity extends ExtraSource {
  /// Uses the measured quantity [quantityId], e.g. `netWallArea`.
  const new(this.quantityId);

  /// Measured quantity id.
  final String quantityId;
}

/// A whole-number count typed by the trader.
@immutable
final class CountOf extends ExtraSource {
  /// [count] items, ≥ 1.
  const new(this.count);

  /// Number of items.
  final int count;
}

/// A decimal quantity typed by the trader, in the item's unit, e.g. 13.10 m
/// of skirting → 1310.
@immutable
final class Entered extends ExtraSource {
  /// [qtyHundredths] of the item's unit, > 0.
  const new(this.qtyHundredths);

  /// Quantity in hundredths.
  final int qtyHundredths;
}

/// A single flat charge (quantity 1).
@immutable
final class Flat extends ExtraSource {
  /// Flat charge.
  const new();
}

/// A trader-chosen extra line in a section.
@immutable
final class ExtraInput {
  /// Prices [itemCode] with quantity from [source], at the price-list
  /// price unless the trader set [unitPrice] for this quote.
  const new({required this.itemCode, required this.source, this.unitPrice});

  /// Price-list code.
  final String itemCode;

  /// Quantity source.
  final ExtraSource source;

  /// Per-quote price override in minor units, or null for the list price.
  /// Stored in the quote snapshot; markup is not added to it.
  final int? unitPrice;
}

/// What the trader entered for one section. Fields left out take the
/// trader's default, then the pack default.
@immutable
final class SectionInput {
  /// Creates a section input.
  const new({this.values = const {}, this.extras = const []});

  /// Field values by field id.
  final Map<String, FieldValue> values;

  /// Extra lines.
  final List<ExtraInput> extras;
}

/// Validated, fully resolved field values handed to a pack. Accessors are
/// only called for fields the pack declared, so a wrong type is a pack bug.
@immutable
final class SectionFields {
  /// Wraps resolved [values]; built by the engine after validation.
  const new(this.values);

  /// Every declared field, resolved.
  final Map<String, FieldValue> values;

  /// Length field [id].
  Length length(String id) => (values[id]! as LengthValue).value;

  /// Whole-number field [id].
  int wholeNumber(String id) => (values[id]! as WholeNumberValue).value;

  /// Toggle field [id].
  bool toggle(String id) => (values[id]! as ToggleValue).value;

  /// Choice field [id].
  String choice(String id) => (values[id]! as ChoiceValue).value;

  /// Openings field [id].
  List<Opening> openings(String id) => (values[id]! as OpeningsValue).value;
}
