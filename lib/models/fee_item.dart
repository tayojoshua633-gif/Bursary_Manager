class FeeItem {
  int? id;
  String name;
  String? description;

  FeeItem({this.id, required this.name, this.description});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
    };
  }

  factory FeeItem.fromMap(Map<String, dynamic> map) {
    return FeeItem(
      id: map['id'],
      name: map['name'],
      description: map['description'],
    );
  }
}
