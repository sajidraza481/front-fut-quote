import 'package:meta/meta.dart';

/// Outcome of an engine call: a value, or the reasons it could not be
/// computed. The engine never throws for bad user input.
sealed class Result<T> {
  const new();
}

/// Success.
@immutable
final class Ok<T> extends Result<T> {
  /// Wraps [value].
  const new(this.value);

  /// The computed value.
  final T value;
}

/// Failure with one or more input errors.
@immutable
final class Invalid<T> extends Result<T> {
  /// Wraps [errors]; must not be empty.
  const new(this.errors);

  /// What was wrong with the input.
  final List<InputError> errors;
}

/// Why an input was rejected. [field] is a field id, an extra's index
/// (`extras[0]`) or a price-list code.
@immutable
final class InputError {
  /// Creates an error for [field] with a machine-readable [code].
  const new(this.field, this.code, [this.detail = '']);

  /// Which input was wrong.
  final String field;

  /// Stable error code for the UI to localise, e.g. `required`, `outOfRange`.
  final String code;

  /// Developer detail; never shown to users, never contains personal data.
  final String detail;

  @override
  bool operator ==(Object other) =>
      other is InputError && other.field == field && other.code == code;

  @override
  int get hashCode => Object.hash(field, code);

  @override
  String toString() =>
      'InputError($field, $code${detail.isEmpty ? '' : ': $detail'})';
}
