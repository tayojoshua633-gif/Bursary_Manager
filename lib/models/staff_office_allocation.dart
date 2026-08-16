class StaffOfficeAllocation {
  int? id;
  int staffId;
  int officeId;
  String? createdAt;

  // Joined fields (populated from queries)
  String? staffName;
  String? officeName;

  StaffOfficeAllocation({
    this.id,
    required this.staffId,
    required this.officeId,
    this.createdAt,
    this.staffName,
    this.officeName,
  });

  factory StaffOfficeAllocation.fromMap(Map<String, dynamic> map) {
    return StaffOfficeAllocation(
      id: map['id'],
      staffId: map['staffId'],
      officeId: map['officeId'],
      createdAt: map['createdAt'],
      staffName: map['staffName'],
      officeName: map['officeName'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'staffId': staffId,
      'officeId': officeId,
      'createdAt': createdAt,
    };
  }
}
