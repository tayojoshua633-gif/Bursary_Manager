// lib/utils/fee_priority_helper.dart
// Shared utility for Fee Tracker feature - computes payment progression against prioritized fees

class FeePriorityHelper {
  /// Apply payments to fee items in priority order.
  /// [prioritizedFees] must be sorted by priority (ascending).
  /// Each entry needs: 'feeItemId', 'feeName' (or 'label'), 'amount'.
  /// Returns a list with added 'status' ('Paid', 'Partly Paid', 'Not Paid') and 'covered' amount.
  static List<Map<String, dynamic>> computeProgression({
    required List<Map<String, dynamic>> prioritizedFees,
    required double totalPaid,
  }) {
    double remaining = totalPaid;
    final result = <Map<String, dynamic>>[];

    for (final fee in prioritizedFees) {
      final amount = (fee['amount'] as num).toDouble();
      final feeName = fee['feeName'] ?? fee['label'] ?? fee['name'] ?? 'Unknown';
      final feeItemId = fee['feeItemId'];

      String status;
      double covered;

      if (remaining >= amount) {
        status = 'Paid';
        covered = amount;
        remaining -= amount;
      } else if (remaining > 0) {
        status = 'Partly Paid';
        covered = remaining;
        remaining = 0;
      } else {
        status = 'Not Paid';
        covered = 0;
      }

      result.add({
        'feeItemId': feeItemId,
        'feeName': feeName,
        'amount': amount,
        'status': status,
        'covered': covered,
      });
    }

    return result;
  }

  /// Get the status of a specific fee item from a progression result
  static String getItemStatus(List<Map<String, dynamic>> progression, int feeItemId) {
    for (final item in progression) {
      if (item['feeItemId'] == feeItemId) {
        return item['status'] as String;
      }
    }
    return 'Not Paid';
  }
}
