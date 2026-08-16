class StaffOffice {
  int? id;
  String name;
  String? description;
  String? createdAt;

  StaffOffice({
    this.id,
    required this.name,
    this.description,
    this.createdAt,
  });

  factory StaffOffice.fromMap(Map<String, dynamic> map) {
    return StaffOffice(
      id: map['id'],
      name: map['name'] ?? '',
      description: map['description'],
      createdAt: map['createdAt'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'createdAt': createdAt,
    };
  }
}
