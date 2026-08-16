class FeeItem {
  int? id;
  String name;
  double defaultAmount;
  String? description;
  String? term;
  String? session;

  FeeItem({
    this.id,
    required this.name,
    this.defaultAmount = 0,
    this.description,
    this.term,
    this.session,
  });

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

  factory FeeItem.fromMap(Map<String, dynamic> map) {
    return FeeItem(
      id: map['id'],
      name: map['name'] ?? '',
      defaultAmount: (map['defaultAmount'] ?? 0).toDouble(),
      description: map['description'],
      term: map['term'],
      session: map['session'],
    );
  }
}
