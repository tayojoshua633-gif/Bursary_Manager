// lib/utils/license_tier_helper.dart
//
// Pricing tiers keyed by student count range. Introduced alongside the
// License Key Generator's pricing guide; also used to show subscribers
// which tier their current active student count falls into (on the home
// screen and the license page), since existing licenses predate this tier
// scheme and don't carry a tier of their own.

/// A pricing tier. Display-only — never encoded into a license key.
class LicenseTier {
  final String name;
  final String emoji;
  final int minStudents;
  final int? maxStudents; // null = open-ended
  final int licensePrice;
  final int termlySupport;
  final int annualSupport;

  const LicenseTier({
    required this.name,
    required this.emoji,
    required this.minStudents,
    required this.maxStudents,
    required this.licensePrice,
    required this.termlySupport,
    required this.annualSupport,
  });

  String get rangeLabel =>
      maxStudents == null ? '$minStudents+' : '$minStudents–$maxStudents';

  String get label => '$emoji $name';
}

const List<LicenseTier> licenseTiers = [
  LicenseTier(
    name: 'Starter',
    emoji: '🟢',
    minStudents: 1,
    maxStudents: 200,
    licensePrice: 100000,
    termlySupport: 10000,
    annualSupport: 20000,
  ),
  LicenseTier(
    name: 'Standard',
    emoji: '🔵',
    minStudents: 201,
    maxStudents: 500,
    licensePrice: 150000,
    termlySupport: 15000,
    annualSupport: 30000,
  ),
  LicenseTier(
    name: 'Professional',
    emoji: '🟣',
    minStudents: 501,
    maxStudents: 1000,
    licensePrice: 200000,
    termlySupport: 20000,
    annualSupport: 40000,
  ),
  LicenseTier(
    name: 'Enterprise',
    emoji: '🏆',
    minStudents: 1001,
    maxStudents: 5000,
    licensePrice: 250000,
    termlySupport: 25000,
    annualSupport: 50000,
  ),
];

/// Finds the tier a given active-student count falls into. Returns null if
/// the count is below the lowest tier's minimum (e.g. 0) or above the
/// highest tier's maximum.
LicenseTier? tierForStudentCount(int students) {
  for (final tier in licenseTiers) {
    if (students >= tier.minStudents &&
        (tier.maxStudents == null || students <= tier.maxStudents!)) {
      return tier;
    }
  }
  return null;
}
