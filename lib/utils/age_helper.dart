// lib/utils/age_helper.dart

class AgeHelper {
  /// Computes age in whole years from a "yyyy-MM-dd" date of birth string.
  /// Returns null if [dob] can't be parsed or is in the future.
  static int? calculateAge(String dob) {
    final date = DateTime.tryParse(dob.trim());
    if (date == null) return null;

    final today = DateTime.now();
    int age = today.year - date.year;
    if (today.month < date.month ||
        (today.month == date.month && today.day < date.day)) {
      age--;
    }
    return age < 0 ? null : age;
  }

  /// Derives an approximate date of birth ("yyyy-MM-dd") from an age in years,
  /// using today's month/day in the resulting birth year.
  static String dobFromAge(int age) {
    final today = DateTime.now();
    final year = today.year - age;
    return "$year-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
  }
}
