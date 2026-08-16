// Sibling detection helper.
//
// A student is considered a "sibling" if another active student shares the
// same non-empty parentPhone. This mirrors the grouping logic already used
// in siblings_screen.dart. Computed fresh from the current active student
// list rather than cached, so it always reflects the latest data across
// standalone/server/client sync modes.

/// Groups the given active students by parentPhone and returns the set of
/// phones shared by more than one student.
Set<String> computeSiblingPhones(List<Map<String, dynamic>> activeStudents) {
  final counts = <String, int>{};
  for (final student in activeStudents) {
    final phone = (student['parentPhone'] as String?)?.trim();
    if (phone == null || phone.isEmpty) continue;
    counts[phone] = (counts[phone] ?? 0) + 1;
  }
  return {
    for (final entry in counts.entries)
      if (entry.value > 1) entry.key,
  };
}

/// Whether the given parentPhone belongs to a sibling group.
bool isSiblingPhone(String? parentPhone, Set<String> siblingPhones) {
  final phone = parentPhone?.trim();
  if (phone == null || phone.isEmpty) return false;
  return siblingPhones.contains(phone);
}
