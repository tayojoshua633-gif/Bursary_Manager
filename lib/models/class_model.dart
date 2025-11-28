class SchoolClass {
  int? id;
  String name;

  SchoolClass({this.id, required this.name});

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
      };

  factory SchoolClass.fromMap(Map<String, dynamic> map) {
    return SchoolClass(
      id: map['id'],
      name: map['name'],
    );
  }
}
