class ExaminationRegistration {
  final int? id;
  final int examinationId;
  final int? studentId; // nullable — null means student was deleted
  final String registrationDate;
  final String createdAt;
  final String session;

  // Snapshot — saved at registration time, survives student deletion/deactivation
  final String? snapshotName;
  final String? snapshotAdmNo;
  final String? snapshotGender;
  final String? snapshotClass;
  final String? snapshotArm;

  // Live joined fields (null when student is deleted)
  final String? surname;
  final String? firstName;
  final String? otherName;
  final String? admissionNo;
  final String? gender;
  final String? className;
  final String? armName;
  final String? parentPhone;
  final int? studentIsActive; // null = deleted, 0 = deactivated, 1 = active
  final String? examinationName;
  final String? examinationCode;

  const ExaminationRegistration({
    this.id,
    required this.examinationId,
    this.studentId,
    required this.registrationDate,
    required this.createdAt,
    required this.session,
    this.snapshotName,
    this.snapshotAdmNo,
    this.snapshotGender,
    this.snapshotClass,
    this.snapshotArm,
    this.surname,
    this.firstName,
    this.otherName,
    this.admissionNo,
    this.gender,
    this.className,
    this.armName,
    this.parentPhone,
    this.studentIsActive,
    this.examinationName,
    this.examinationCode,
  });

  /// True if the student record no longer exists in the students table.
  bool get isStudentDeleted => studentId == null || (surname == null && firstName == null);

  /// True if the student exists but has been deactivated.
  bool get isStudentDeactivated => !isStudentDeleted && studentIsActive == 0;

  /// Full display name — prefers live data, falls back to snapshot.
  String get fullName {
    final live = [surname, firstName, otherName]
        .where((p) => p != null && p.isNotEmpty)
        .join(' ');
    if (live.isNotEmpty) return live;
    return snapshotName ?? 'Unknown Student';
  }

  String get classArm {
    final cls = className ?? snapshotClass ?? '';
    final arm = armName ?? snapshotArm ?? '';
    return arm.isNotEmpty ? '$cls $arm'.trim() : cls;
  }

  factory ExaminationRegistration.fromMap(Map<String, dynamic> map) {
    return ExaminationRegistration(
      id: map['id'] as int?,
      examinationId: map['examinationId'] as int,
      studentId: map['studentId'] as int?,
      registrationDate: map['registrationDate'] as String,
      createdAt: map['createdAt'] as String,
      session: map['session'] as String? ?? '',
      snapshotName: map['snapshotName'] as String?,
      snapshotAdmNo: map['snapshotAdmNo'] as String?,
      snapshotGender: map['snapshotGender'] as String?,
      snapshotClass: map['snapshotClass'] as String?,
      snapshotArm: map['snapshotArm'] as String?,
      surname: map['surname'] as String?,
      firstName: map['firstName'] as String?,
      otherName: map['otherName'] as String?,
      admissionNo: map['admissionNo'] as String?,
      gender: map['gender'] as String?,
      className: map['className'] as String?,
      armName: map['armName'] as String?,
      parentPhone: map['parentPhone'] as String?,
      studentIsActive: map['studentIsActive'] as int?,
      examinationName: map['examinationName'] as String?,
      examinationCode: map['examinationCode'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'examinationId': examinationId,
      if (studentId != null) 'studentId': studentId,
      'registrationDate': registrationDate,
      'createdAt': createdAt,
      'session': session,
      if (snapshotName != null) 'snapshotName': snapshotName,
      if (snapshotAdmNo != null) 'snapshotAdmNo': snapshotAdmNo,
      if (snapshotGender != null) 'snapshotGender': snapshotGender,
      if (snapshotClass != null) 'snapshotClass': snapshotClass,
      if (snapshotArm != null) 'snapshotArm': snapshotArm,
    };
  }
}
