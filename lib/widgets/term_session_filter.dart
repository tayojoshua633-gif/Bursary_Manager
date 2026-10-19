import 'package:flutter/material.dart';

/// Session + Term dropdown pair used by the student screens that work per
/// term (Deactivate, Inactive, New Students).
///
/// When [allowAll] is true each dropdown gets an "All ..." entry, reported as
/// a null value.
class TermSessionFilter extends StatelessWidget {
  static const List<String> terms = ['1st Term', '2nd Term', '3rd Term'];

  final List<String> sessions;
  final String? session;
  final String? term;
  final ValueChanged<String?> onSessionChanged;
  final ValueChanged<String?> onTermChanged;
  final bool allowAll;

  const TermSessionFilter({
    super.key,
    required this.sessions,
    required this.session,
    required this.term,
    required this.onSessionChanged,
    required this.onTermChanged,
    this.allowAll = false,
  });

  /// Distinct session names from `getAllSessions()` rows, always including
  /// [current] so the dropdown never holds a value missing from its items.
  static List<String> sessionNames(List<Map<String, dynamic>> rows, String? current) {
    final names = rows
        .map((s) => (s['sessionName'] ?? '').toString())
        .where((n) => n.isNotEmpty)
        .toSet();
    if (current != null && current.isNotEmpty) names.add(current);
    return names.toList()..sort((a, b) => b.compareTo(a));
  }

  @override
  Widget build(BuildContext context) {
    final termItems = {...terms, if (term != null) term!}.toList();

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            key: ValueKey('session_$session'),
            initialValue: session,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Session',
              isDense: true,
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.calendar_today, size: 18),
              filled: true,
              fillColor: Colors.white,
            ),
            items: [
              if (allowAll)
                const DropdownMenuItem<String?>(value: null, child: Text('All Sessions')),
              ...sessions.map((s) => DropdownMenuItem<String?>(value: s, child: Text(s))),
            ],
            onChanged: onSessionChanged,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String?>(
            key: ValueKey('term_$term'),
            initialValue: term,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Term',
              isDense: true,
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.event, size: 18),
              filled: true,
              fillColor: Colors.white,
            ),
            items: [
              if (allowAll)
                const DropdownMenuItem<String?>(value: null, child: Text('All Terms')),
              ...termItems.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t))),
            ],
            onChanged: onTermChanged,
          ),
        ),
      ],
    );
  }
}
