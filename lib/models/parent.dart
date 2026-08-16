class Parent {
  int? id;
  String parentName;
  String phoneNumber;
  String? phoneNumber2;
  String homeAddress;
  String? occupation;
  String? officeAddress;
  String? emailAddress;
  String? createdAt;
  String? updatedAt;

  Parent({
    this.id,
    required this.parentName,
    required this.phoneNumber,
    this.phoneNumber2,
    required this.homeAddress,
    this.occupation,
    this.officeAddress,
    this.emailAddress,
    this.createdAt,
    this.updatedAt,
  });

  // Convert from DB Map
  factory Parent.fromMap(Map<String, dynamic> map) {
    return Parent(
      id: map['id'],
      parentName: map['parentName'],
      phoneNumber: map['phoneNumber'],
      phoneNumber2: map['phoneNumber2'],
      homeAddress: map['homeAddress'],
      occupation: map['occupation'],
      officeAddress: map['officeAddress'],
      emailAddress: map['emailAddress'],
      createdAt: map['createdAt'],
      updatedAt: map['updatedAt'],
    );
  }

  // Convert to DB Map
  Map<String, dynamic> toMap() {
    final now = DateTime.now().toIso8601String();
    return {
      if (id != null) 'id': id,
      'parentName': parentName,
      'phoneNumber': phoneNumber,
      'phoneNumber2': phoneNumber2,
      'homeAddress': homeAddress,
      'occupation': occupation,
      'officeAddress': officeAddress,
      'emailAddress': emailAddress,
      'createdAt': createdAt ?? now,
      'updatedAt': now,
    };
  }

  // Display formatted phone numbers
  String get phoneNumbers {
    if (phoneNumber2 != null && phoneNumber2!.isNotEmpty) {
      return '$phoneNumber, $phoneNumber2';
    }
    return phoneNumber;
  }

  // Full name for display
  String get fullName => parentName;
}
