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

  double get totalPaid => amount - (deductionPerMonth * monthsRemaining);
  double get balance => deductionPerMonth * monthsRemaining;

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
