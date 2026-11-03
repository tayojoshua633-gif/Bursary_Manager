import 'dart:convert';

class StaffLoan {
  int? id;
  int staffId;
  String staffName;
  String month; // e.g., "January 2024"
  double amount;
  double deductionPerMonth;
  int monthsRemaining;
  String reason;
  String status; // 'Active', 'Completed'
  String? collectionDate; // Date when loan was collected
  String? createdAt;
  int? linkedExpenseId; // Expense record this loan was auto-posted to
  String? paymentMethod; // How the loan was paid out: 'Cash', 'Transfer', 'POS'

  StaffLoan({
    this.id,
    required this.staffId,
    required this.staffName,
    required this.month,
    required this.amount,
    required this.deductionPerMonth,
    this.monthsRemaining = 0,
    required this.reason,
    this.status = 'Active',
    this.collectionDate,
    this.createdAt,
    this.linkedExpenseId,
    this.paymentMethod,
  });

  double get totalPaid => amount - balance;
  double get balance => monthsRemaining > 0
      ? deductionPerMonth * monthsRemaining + roundingResidue(amount, deductionPerMonth)
      : 0;

  /// Kobo left over when a loan doesn't split evenly into its monthly
  /// deduction (e.g. N100,000 / 3 months = N33,333.33 → N0.01). It is
  /// collected with the final month so the loan is repaid exactly.
  static double roundingResidue(double amount, double deductionPerMonth) {
    if (deductionPerMonth <= 0) return 0;
    final months = (amount / deductionPerMonth).round();
    final residue = double.parse((amount - deductionPerMonth * months).toStringAsFixed(2));
    // Only true rounding leftovers — a hand-picked deduction that doesn't
    // divide the loan isn't silently topped up.
    return residue.abs() < 1 ? residue : 0;
  }

  /// Repayments recorded outside salary (Record Payment): each entry is
  /// {'date', 'months', 'amount', 'by', 'completed'}.
  static List<Map<String, dynamic>> manualRepaymentsFor(Map<String, dynamic> loan) {
    final raw = loan['manualRepayments'] as String?;
    if (raw == null || raw.isEmpty) return [];
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          if (e is Map) Map<String, dynamic>.from(e),
      ];
    } catch (_) {
      return [];
    }
  }

  /// True when a Record Payment (not a salary) took the loan's final month.
  static bool completedByManualRepayment(Map<String, dynamic> loan) =>
      manualRepaymentsFor(loan).any((e) => e['completed'] == true);

  static double roundingResidueFor(Map<String, dynamic> loan) => roundingResidue(
        (loan['amount'] as num?)?.toDouble() ?? 0,
        (loan['deductionPerMonth'] as num?)?.toDouble() ?? 0,
      );

  factory StaffLoan.fromMap(Map<String, dynamic> map) {
    return StaffLoan(
      id: map['id'],
      staffId: map['staffId'],
      staffName: map['staffName'] ?? '',
      month: map['month'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      deductionPerMonth: (map['deductionPerMonth'] ?? 0).toDouble(),
      monthsRemaining: map['monthsRemaining'] ?? 0,
      reason: map['reason'] ?? '',
      status: map['status'] ?? 'Active',
      collectionDate: map['collectionDate'],
      createdAt: map['createdAt'],
      linkedExpenseId: map['linkedExpenseId'],
      paymentMethod: map['paymentMethod'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'staffId': staffId,
      'staffName': staffName,
      'month': month,
      'amount': amount,
      'deductionPerMonth': deductionPerMonth,
      'monthsRemaining': monthsRemaining,
      'reason': reason,
      'status': status,
      'collectionDate': collectionDate,
      'createdAt': createdAt,
      'linkedExpenseId': linkedExpenseId,
      'paymentMethod': paymentMethod,
    };
  }
}
