import 'dart:convert';

class Staff {
  int? id;
  String staffId; // Auto-generated: STF001, STF002...
  String staffType; // 'Teaching Staff' or 'Non-Teaching Staff'
  String? title;
  String surname;
  String firstName;
  String? otherName;
  String gender;
  String? dateOfBirth;
  String? maritalStatus;
  String? stateOfOrigin;
  String? lga;
  String? nationality;
  String? religion;
  String? address;
  String? phone;
  String? phone2;
  String? email;
  String? nextOfKinName;
  String? nextOfKinPhone;
  String? nextOfKinRelationship;
  String? nextOfKinAddress;
  List<AcademicRecord>? academicInfo;
  List<JobExperience>? jobExperience;
  List<String>? skills;
  List<String>? hobbies;
  String? referee1Name;
  String? referee1Phone;
  String? referee1Relationship;
  String? referee1Address;
  String? referee2Name;
  String? referee2Phone;
  String? referee2Relationship;
  String? referee2Address;
  String? dateOfEmployment;
  double salary;
  String? bankName;
  String? accountName;
  String? accountNumber;
  String? photoPath;
  int isActive;
  String? deactivationDate;
  String? createdAt;
  String? updatedAt;

  Staff({
    this.id,
    required this.staffId,
    required this.staffType,
    this.title,
    required this.surname,
    required this.firstName,
    this.otherName,
    required this.gender,
    this.dateOfBirth,
    this.maritalStatus,
    this.stateOfOrigin,
    this.lga,
    this.nationality,
    this.religion,
    this.address,
    this.phone,
    this.phone2,
    this.email,
    this.nextOfKinName,
    this.nextOfKinPhone,
    this.nextOfKinRelationship,
    this.nextOfKinAddress,
    this.academicInfo,
    this.jobExperience,
    this.skills,
    this.hobbies,
    this.referee1Name,
    this.referee1Phone,
    this.referee1Relationship,
    this.referee1Address,
    this.referee2Name,
    this.referee2Phone,
    this.referee2Relationship,
    this.referee2Address,
    this.dateOfEmployment,
    this.salary = 0,
    this.bankName,
    this.accountName,
    this.accountNumber,
    this.photoPath,
    this.isActive = 1,
    this.deactivationDate,
    this.createdAt,
    this.updatedAt,
  });

  String get fullName => '${title != null ? '$title ' : ''}$surname $firstName ${otherName ?? ''}'.trim();
  bool get isTeachingStaff => staffType == 'Teaching Staff';
  bool get active => isActive == 1;

  factory Staff.fromMap(Map<String, dynamic> map) {
    List<AcademicRecord>? academicInfo;
    if (map['academicInfo'] != null && map['academicInfo'].toString().isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(map['academicInfo']);
        academicInfo = decoded.map((e) => AcademicRecord.fromMap(e)).toList();
      } catch (_) {
        academicInfo = [];
      }
    }

    List<JobExperience>? jobExperience;
    if (map['jobExperience'] != null && map['jobExperience'].toString().isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(map['jobExperience']);
        jobExperience = decoded.map((e) => JobExperience.fromMap(e)).toList();
      } catch (_) {
        jobExperience = [];
      }
    }

    List<String>? skills;
    if (map['skills'] != null && map['skills'].toString().isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(map['skills']);
        skills = decoded.map((e) => e.toString()).toList();
      } catch (_) {
        skills = [];
      }
    }

    List<String>? hobbies;
    if (map['hobbies'] != null && map['hobbies'].toString().isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(map['hobbies']);
        hobbies = decoded.map((e) => e.toString()).toList();
      } catch (_) {
        hobbies = [];
      }
    }

    return Staff(
      id: map['id'],
      staffId: map['staffId'] ?? '',
      staffType: map['staffType'] ?? 'Non-Teaching Staff',
      title: map['title'],
      surname: map['surname'] ?? '',
      firstName: map['firstName'] ?? '',
      otherName: map['otherName'],
      gender: map['gender'] ?? '',
      dateOfBirth: map['dateOfBirth'],
      maritalStatus: map['maritalStatus'],
      stateOfOrigin: map['stateOfOrigin'],
      lga: map['lga'],
      nationality: map['nationality'],
      religion: map['religion'],
      address: map['address'],
      phone: map['phone'],
      phone2: map['phone2'],
      email: map['email'],
      nextOfKinName: map['nextOfKinName'],
      nextOfKinPhone: map['nextOfKinPhone'],
      nextOfKinRelationship: map['nextOfKinRelationship'],
      nextOfKinAddress: map['nextOfKinAddress'],
      academicInfo: academicInfo,
      jobExperience: jobExperience,
      skills: skills,
      hobbies: hobbies,
      referee1Name: map['referee1Name'],
      referee1Phone: map['referee1Phone'],
      referee1Relationship: map['referee1Relationship'],
      referee1Address: map['referee1Address'],
      referee2Name: map['referee2Name'],
      referee2Phone: map['referee2Phone'],
      referee2Relationship: map['referee2Relationship'],
      referee2Address: map['referee2Address'],
      dateOfEmployment: map['dateOfEmployment'],
      salary: (map['salary'] ?? 0).toDouble(),
      bankName: map['bankName'],
      accountName: map['accountName'],
      accountNumber: map['accountNumber'],
      photoPath: map['photoPath'],
      isActive: map['isActive'] ?? 1,
      deactivationDate: map['deactivationDate'],
      createdAt: map['createdAt'],
      updatedAt: map['updatedAt'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'staffId': staffId,
      'staffType': staffType,
      'title': title,
      'surname': surname,
      'firstName': firstName,
      'otherName': otherName,
      'gender': gender,
      'dateOfBirth': dateOfBirth,
      'maritalStatus': maritalStatus,
      'stateOfOrigin': stateOfOrigin,
      'lga': lga,
      'nationality': nationality,
      'religion': religion,
      'address': address,
      'phone': phone,
      'phone2': phone2,
      'email': email,
      'nextOfKinName': nextOfKinName,
      'nextOfKinPhone': nextOfKinPhone,
      'nextOfKinRelationship': nextOfKinRelationship,
      'nextOfKinAddress': nextOfKinAddress,
      'academicInfo': academicInfo != null
          ? jsonEncode(academicInfo!.map((e) => e.toMap()).toList())
          : null,
      'jobExperience': jobExperience != null
          ? jsonEncode(jobExperience!.map((e) => e.toMap()).toList())
          : null,
      'skills': skills != null ? jsonEncode(skills) : null,
      'hobbies': hobbies != null ? jsonEncode(hobbies) : null,
      'referee1Name': referee1Name,
      'referee1Phone': referee1Phone,
      'referee1Relationship': referee1Relationship,
      'referee1Address': referee1Address,
      'referee2Name': referee2Name,
      'referee2Phone': referee2Phone,
      'referee2Relationship': referee2Relationship,
      'referee2Address': referee2Address,
      'dateOfEmployment': dateOfEmployment,
      'salary': salary,
      'bankName': bankName,
      'accountName': accountName,
      'accountNumber': accountNumber,
      'photoPath': photoPath,
      'isActive': isActive,
      'deactivationDate': deactivationDate,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

class AcademicRecord {
  String schoolName;
  String certificate;
  String yearObtained;

  AcademicRecord({
    required this.schoolName,
    required this.certificate,
    required this.yearObtained,
  });

  factory AcademicRecord.fromMap(Map<String, dynamic> map) {
    return AcademicRecord(
      schoolName: map['schoolName'] ?? '',
      certificate: map['certificate'] ?? '',
      yearObtained: map['yearObtained'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'schoolName': schoolName,
      'certificate': certificate,
      'yearObtained': yearObtained,
    };
  }
}

class JobExperience {
  String organization;
  String position;
  String startDate;
  String endDate;

  JobExperience({
    required this.organization,
    required this.position,
    required this.startDate,
    required this.endDate,
  });

  factory JobExperience.fromMap(Map<String, dynamic> map) {
    return JobExperience(
      organization: map['organization'] ?? '',
      position: map['position'] ?? '',
      startDate: map['startDate'] ?? '',
      endDate: map['endDate'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'organization': organization,
      'position': position,
      'startDate': startDate,
      'endDate': endDate,
    };
  }
}
