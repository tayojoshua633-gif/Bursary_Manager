// lib/utils/multi_school_report_coordinator.dart
import '../db/database_helper.dart';
import 'school_sync_registry.dart';

/// One school's outcome from a multi-school load — success or per-school
/// failure. One school's error never blocks the others from rendering.
class SchoolReportOutcome<T> {
  final LinkedSchool school;
  final T? data;
  final Object? error;

  bool get success => error == null;

  const SchoolReportOutcome({required this.school, this.data, this.error});
}

/// Runs [loader] once per linked school, sequentially — never in parallel,
/// because DatabaseHelper only ever has one file open at a time (see
/// SchoolSyncClient's class doc for the same constraint; parallel
/// Future.wait calls here would race on the single shared connection).
/// Switches the active database to each school before calling [loader], and
/// restores whatever was active before this call started once every school
/// has been visited — success or failure, via try/finally, so a mid-loop
/// exception still restores the caller's original active database.
///
/// Known limitation, not solved here: if AutoSyncService's periodic timer
/// fires while this is mid-loop, both would call switchDatabase() and race
/// the same singleton. This exact race already exists between
/// AutoSyncService and manual sync today — not a new risk introduced here.
Future<List<SchoolReportOutcome<T>>> loadAcrossLinkedSchools<T>(
  Future<T> Function() loader, {
  List<LinkedSchool>? schoolsOverride,
}) async {
  final schools = schoolsOverride ?? await SchoolSyncRegistry.getAll();
  final originalActiveId = await SchoolSyncRegistry.getActiveId();
  final results = <SchoolReportOutcome<T>>[];

  try {
    for (final school in schools) {
      try {
        await DatabaseHelper().switchDatabase(school.dbFileName);
        final data = await loader();
        results.add(SchoolReportOutcome(school: school, data: data));
      } catch (e) {
        results.add(SchoolReportOutcome(school: school, error: e));
      }
    }
  } finally {
    final restoreTo = schools.where((s) => s.id == originalActiveId).firstOrNull ??
        (schools.isNotEmpty ? schools.first : null);
    if (restoreTo != null) {
      await DatabaseHelper().switchDatabase(restoreTo.dbFileName);
    }
  }

  return results;
}
