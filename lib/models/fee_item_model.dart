class FeeItem {
  final int? id;
  final String name;
  final double defaultAmount;   // ✅ REQUIRED FIELD
  final String? description;

  FeeItem({
    this.id,
    required this.name,
    required this.defaultAmount,   // ✅ REQUIRED IN CONSTRUCTOR
    this.description,
  });

  factory FeeItem.fromMap(Map<String, dynamic> map) {
    return FeeItem(
      id: map['id'] as int?,
      name: map['name'] ?? '',
      defaultAmount: (map['defaultAmount'] ?? 0).toDouble(), // ✅ FIXED
      description: map['description'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'defaultAmount': defaultAmount,    // ✅ FIXED
      'description': description,
    };
  }
}
