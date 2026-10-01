// lib/utils/report_data/report_pdf_dates.dart
import 'package:intl/intl.dart';

/// Date helpers shared by the Daily Report and Custom Report PDF/HTML
/// exports, so every date column is formatted and ordered the same way.

final DateFormat _reportDateFormat = DateFormat('dd/MM/yyyy');

/// Formats a stored date (ISO string or DateTime) for a report table cell.
/// Falls back to the raw value when it can't be parsed.
String formatReportDate(dynamic raw) {
  if (raw == null) return '';
  final dt = raw is DateTime ? raw : DateTime.tryParse(raw.toString());
  return dt == null ? raw.toString() : _reportDateFormat.format(dt);
}

/// Returns a copy of [rows] sorted oldest-first by [dateKey]. Rows whose
/// date can't be parsed keep their relative order at the end.
List<Map<String, dynamic>> sortByDateAscending(
  List<Map<String, dynamic>> rows,
  String dateKey,
) {
  final indexed = rows.asMap().entries.toList();
  indexed.sort((a, b) {
    final da = DateTime.tryParse(a.value[dateKey]?.toString() ?? '');
    final db = DateTime.tryParse(b.value[dateKey]?.toString() ?? '');
    if (da == null && db == null) return a.key.compareTo(b.key);
    if (da == null) return 1;
    if (db == null) return -1;
    final c = da.compareTo(db);
    return c != 0 ? c : a.key.compareTo(b.key);
  });
  return indexed.map((e) => e.value).toList();
}

/// Date cell for a sales row. Sales are grouped per buyer, so a group can
/// span several days in a Custom Report range — show "first - last" then.
String formatSaleDate(Map<String, dynamic> sale) {
  final first = formatReportDate(sale['saleDate']);
  final last = formatReportDate(sale['lastSaleDate']);
  if (last.isEmpty || last == first) return first;
  return '$first - $last';
}
