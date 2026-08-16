class ExternalExamination {
  final int? id;
  final String name;
  final String code;
  final bool isDefault;
  final bool isActive;
  final String createdAt;

  const ExternalExamination({
    this.id,
    required this.name,
    required this.code,
    this.isDefault = false,
    this.isActive = true,
    required this.createdAt,
  });

  factory ExternalExamination.fromMap(Map<String, dynamic> map) {
    return ExternalExamination(
      id: map['id'] as int?,
      name: map['name'] as String,
      code: map['code'] as String,
      isDefault: (map['isDefault'] as int? ?? 0) == 1,
      isActive: (map['isActive'] as int? ?? 1) == 1,
      createdAt: map['createdAt'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'code': code,
      'isDefault': isDefault ? 1 : 0,
      'isActive': isActive ? 1 : 0,
      'createdAt': createdAt,
    };
  }

  ExternalExamination copyWith({
    int? id,
    String? name,
    String? code,
    bool? isDefault,
    bool? isActive,
    String? createdAt,
  }) {
    return ExternalExamination(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      isDefault: isDefault ?? this.isDefault,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
