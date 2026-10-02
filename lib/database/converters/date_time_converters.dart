import 'package:floor/floor.dart';

/// SQLite has no date type, so Floor needs a converter.
///
/// [DateTimeConverter] stores a non nullable date as an `INTEGER` holding the
/// number of milliseconds since the Unix epoch (UTC based).
class DateTimeConverter extends TypeConverter<DateTime, int> {
  @override
  DateTime decode(int databaseValue) =>
      DateTime.fromMillisecondsSinceEpoch(databaseValue, isUtc: true);

  @override
  int encode(DateTime value) => value.toUtc().millisecondsSinceEpoch;
}

/// Same as [DateTimeConverter] but keeps the `NULL` value, which is what the
/// optional `location_captured_at` column needs.
class NullableDateTimeConverter extends TypeConverter<DateTime?, int?> {
  @override
  DateTime? decode(int? databaseValue) => databaseValue == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(databaseValue, isUtc: true);

  @override
  int? encode(DateTime? value) => value?.toUtc().millisecondsSinceEpoch;
}
