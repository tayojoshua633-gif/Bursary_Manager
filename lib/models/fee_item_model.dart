class FeeItem {
  final int? id;
  final String name;
  final double defaultAmount;
  final String? description;
  final String? term;
  final String? session;

  FeeItem({
    this.id,
    required this.name,
    required this.defaultAmount,
    this.description,
    this.term,
    this.session,
  });

  factory FeeItem.fromMap(Map<String, dynamic> map) {
    return FeeItem(
      id: map['id'] as int?,
      name: map['name'] ?? '',
      defaultAmount: (map['defaultAmount'] ?? 0).toDouble(),
      description: map['description'],
      term: map['term'],
      session: map['session'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'defaultAmount': defaultAmount,
      'description': description,
      'term': term,
      'session': session,
    };
  }
}
