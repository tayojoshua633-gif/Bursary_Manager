class StaffIncentive {
  int? id;
  int staffId;
  String staffName;
  String month; // e.g., "January 2024"
  double amount;
  String description;
  String? createdAt;

  StaffIncentive({
    this.id,
    required this.staffId,
    required this.staffName,
    required this.month,
    required this.amount,
    required this.description,
    this.createdAt,
  });

  factory StaffIncentive.fromMap(Map<String, dynamic> map) {
    return StaffIncentive(
      id: map['id'],
      staffId: map['staffId'],
      staffName: map['staffName'] ?? '',
      month: map['month'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      description: map['description'] ?? '',
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
      'description': description,
      'createdAt': createdAt,
    };
  }
}
