class StaffDeduction {
  int? id;
  int staffId;
  String staffName;
  String month; // e.g., "January 2024"
  double amount;
  String reason; // 'Late Coming', 'Absenteeism', 'Other'
  String? description;
  String date;
  String? createdAt;

  StaffDeduction({
    this.id,
    required this.staffId,
    required this.staffName,
    required this.month,
    required this.amount,
    required this.reason,
    this.description,
    required this.date,
    this.createdAt,
  });

  factory StaffDeduction.fromMap(Map<String, dynamic> map) {
    return StaffDeduction(
      id: map['id'],
      staffId: map['staffId'],
      staffName: map['staffName'] ?? '',
      month: map['month'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      reason: map['reason'] ?? '',
      description: map['description'],
      date: map['date'] ?? '',
      createdAt: map['createdAt'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'staffId': staffId,
      'staffName': staffName,
      'month': month,
      'amount': amount,
      'reason': reason,
      'description': description,
      'date': date,
      'createdAt': createdAt,
    };
  }
}
