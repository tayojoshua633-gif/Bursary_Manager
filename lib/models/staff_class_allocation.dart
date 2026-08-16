import 'dart:convert';

class StaffClassAllocation {
  int? id;
  int staffId;
  int classId;
  int armId;
  List<String>? subjectsTaught;
  String? createdAt;

  // Joined fields (populated from queries)
  String? staffName;
  String? className;
  String? armName;

  StaffClassAllocation({
    this.id,
    required this.staffId,
    required this.classId,
    required this.armId,
    this.subjectsTaught,
    this.createdAt,
    this.staffName,
    this.className,
    this.armName,
  });

  factory StaffClassAllocation.fromMap(Map<String, dynamic> map) {
    List<String>? subjects;
    if (map['subjectsTaught'] != null && map['subjectsTaught'].toString().isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(map['subjectsTaught']);
        subjects = decoded.map((e) => e.toString()).toList();
      } catch (_) {
        subjects = [];
      }
    }

    return StaffClassAllocation(
      id: map['id'],
      staffId: map['staffId'],
      classId: map['classId'],
      armId: map['armId'],
      subjectsTaught: subjects,
      createdAt: map['createdAt'],
      staffName: map['staffName'],
      className: map['className'],
      armName: map['armName'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'staffId': staffId,
      'classId': classId,
      'armId': armId,
      'subjectsTaught': subjectsTaught != null ? jsonEncode(subjectsTaught) : null,
      'createdAt': createdAt,
    };
  }
}
