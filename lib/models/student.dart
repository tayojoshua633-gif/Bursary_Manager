class Student {
  int? id;
  String admissionNo;
  String surname;
  String firstName;
  String? otherName;
  String gender;
  String dob;
  int classId;
  int armId;
  String address;
  String parentName;
  String parentPhone;
  String? parentEmail;
  String? parentAddress;
  String? photoPath; // NEW FIELD

  // Optional joined fields (from classes and arms)
  String? className;
  String? armName;

  Student({
    this.id,
    required this.admissionNo,
    required this.surname,
    required this.firstName,
    this.otherName,
    required this.gender,
    required this.dob,
    required this.classId,
    required this.armId,
    required this.address,
    required this.parentName,
    required this.parentPhone,
    this.parentEmail,
    this.parentAddress,
    this.photoPath,
    this.className,
    this.armName,
  });

  // Convert from DB Map
  factory Student.fromMap(Map<String, dynamic> map) {
    return Student(
      id: map['id'],
      admissionNo: map['admissionNo'],
      surname: map['surname'],
      firstName: map['firstName'],
      otherName: map['otherName'],
      gender: map['gender'],
      dob: map['dob'],
      classId: map['classId'],
      armId: map['armId'],
      address: map['address'],
      parentName: map['parentName'],
      parentPhone: map['parentPhone'],
      parentEmail: map['parentEmail'],
      parentAddress: map['parentAddress'],
      photoPath: map['photoPath'],

      // Joined fields (from SELECT s.*, c.name AS className, a.name AS armName)
      className: map['className'],
      armName: map['armName'],
    );
  }

  // Convert to DB Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'admissionNo': admissionNo,
      'surname': surname,
      'firstName': firstName,
      'otherName': otherName,
      'gender': gender,
      'dob': dob,
      'classId': classId,
      'armId': armId,
      'address': address,
      'parentName': parentName,
      'parentPhone': parentPhone,
      'parentEmail': parentEmail,
      'parentAddress': parentAddress,
      'photoPath': photoPath,
    };
  }
}
