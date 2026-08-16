import 'package:intl/intl.dart';

DateTime? parsePaymentDate(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

String formatPaymentDateOnly(String? raw) {
  final dt = parsePaymentDate(raw);
  if (dt == null) return raw ?? '';
  return DateFormat('dd MMM yyyy').format(dt);
}

String formatPaymentTimeOnly(String? raw) {
  final dt = parsePaymentDate(raw);
  if (dt == null) return '';
  final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour < 12 ? 'am' : 'pm';
  return '$hour:$minute$period';
}
