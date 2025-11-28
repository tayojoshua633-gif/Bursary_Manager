class Arm {
  int? id;
  int classId;
  String name;

  Arm({this.id, required this.classId, required this.name});

  Map<String, dynamic> toMap() => {
        'id': id,
        'classId': classId,
        'name': name,
      };

  factory Arm.fromMap(Map<String, dynamic> map) {
    return Arm(
      id: map['id'],
      classId: map['classId'],
      name: map['name'],
    );
  }
}
