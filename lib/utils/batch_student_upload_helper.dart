// lib/utils/batch_student_upload_helper.dart

import 'dart:io';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:excel/excel.dart';
import 'package:csv/csv.dart';
import '../data/database_helper_wrapper.dart';

class BatchStudentUploadHelper {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  /// Generate Excel template with correct column names
  Future<File> generateTemplate(String outputPath) async {
    var excel = Excel.createExcel();
    Sheet sheet = excel['Students'];

    // Header row with correct column names matching database schema
    sheet.appendRow([
      TextCellValue('Surname'), TextCellValue('First Name'), TextCellValue('Other Name'), TextCellValue('Admission No'),
      TextCellValue('Parent Name'), TextCellValue('Parent Phone'), TextCellValue('Parent Email'), TextCellValue('Address'),
      TextCellValue('Gender'), TextCellValue('Date of Birth'), TextCellValue('Class'), TextCellValue('Arm'), TextCellValue('Status')
    ]);

    // Example rows
    sheet.appendRow([
      TextCellValue('ADINYA'), TextCellValue('SARAH'), TextCellValue('DAWOT'), TextCellValue('2025/0001'),
      TextCellValue('MR. & MRS. ADINYA'), TextCellValue('08012345678'), TextCellValue('parent@example.com'), TextCellValue('ORE'),
      TextCellValue('Female'), TextCellValue('2010-05-15'), TextCellValue('JSS 1'), TextCellValue('A'), TextCellValue('Active')
    ]);

    sheet.appendRow([
      TextCellValue('AGBOOLA'), TextCellValue('GREAT'), TextCellValue('DAWOT'), TextCellValue('2025/0002'),
      TextCellValue('MR. & MRS. AGBOOLA'), TextCellValue('08012345678'), TextCellValue('parent@example.com'), TextCellValue('ORE'),
      TextCellValue('Male'), TextCellValue('2010-05-15'), TextCellValue('JSS 1'), TextCellValue('A'), TextCellValue('Active')
    ]);

    // Auto-size columns
    for (var i = 0; i < 13; i++) {
      sheet.setColumnWidth(i, 20);
    }

    // Save file
    var fileBytes = excel.save();
    File(outputPath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(fileBytes!);

    return File(outputPath);
  }

  /// Parse Excel file
  Future<List<StudentUploadData>> parseExcelFile(
    String filePath,
    Map<String, int> classNameToId,
    Map<String, Map<int, int>> armNameToId,
  ) async {
    var bytes = File(filePath).readAsBytesSync();
    var excel = Excel.decodeBytes(bytes);

    List<StudentUploadData> students = [];

    for (var table in excel.tables.keys) {
      var sheet = excel.tables[table]!;
      
      // Skip header row (index 0)
      for (var rowIndex = 1; rowIndex < sheet.maxRows; rowIndex++) {
        var row = sheet.rows[rowIndex];
        
        // Skip empty rows
        if (row.isEmpty || row.every((cell) => cell == null || cell.value == null)) {
          continue;
        }

        try {
          final surname = _getCellValue(row, 0);
          final firstName = _getCellValue(row, 1);
          final otherName = _getCellValue(row, 2);
          final admissionNo = _getCellValue(row, 3);
          final parentName = _getCellValue(row, 4);  // Changed from guardianName
          final parentPhone = _getCellValue(row, 5); // Changed from guardianPhone
          final parentEmail = _getCellValue(row, 6); // Changed from guardianEmail
          final address = _getCellValue(row, 7);
          final gender = _getCellValue(row, 8);
          final dob = _getCellValue(row, 9);
          final className = _getCellValue(row, 10);
          final armName = _getCellValue(row, 11);
          final status = _getCellValue(row, 12);

          students.add(StudentUploadData(
            rowNumber: rowIndex + 1,
            surname: surname,
            firstName: firstName,
            otherName: otherName,
            admissionNo: admissionNo,
            parentName: parentName,      // Changed from guardianName
            parentPhone: parentPhone,    // Changed from guardianPhone
            parentEmail: parentEmail,    // Changed from guardianEmail
            address: address,
            gender: gender,
            dateOfBirth: dob,
            className: className,
            armName: armName,
            status: status,
            classId: classNameToId[className],
            armId: armNameToId[armName]?[classNameToId[className]],
          ));
        } catch (e) {
          developer.log('Error parsing row $rowIndex: $e');
        }
      }
    }

    return students;
  }

  /// Parse CSV file
  Future<List<StudentUploadData>> parseCsvFile(
    String filePath,
    Map<String, int> classNameToId,
    Map<String, Map<int, int>> armNameToId,
  ) async {
    final input = File(filePath).openRead();
    final fields = await input
        .transform(utf8.decoder)
        .transform(const CsvToListConverter())
        .toList();

    List<StudentUploadData> students = [];

    // Skip header row (index 0)
    for (var rowIndex = 1; rowIndex < fields.length; rowIndex++) {
      var row = fields[rowIndex];
      
      // Skip empty rows
      if (row.isEmpty) continue;

      try {
        final surname = _getCellValueFromList(row, 0);
        final firstName = _getCellValueFromList(row, 1);
        final otherName = _getCellValueFromList(row, 2);
        final admissionNo = _getCellValueFromList(row, 3);
        final parentName = _getCellValueFromList(row, 4);  // Changed from guardianName
        final parentPhone = _getCellValueFromList(row, 5); // Changed from guardianPhone
        final parentEmail = _getCellValueFromList(row, 6); // Changed from guardianEmail
        final address = _getCellValueFromList(row, 7);
        final gender = _getCellValueFromList(row, 8);
        final dob = _getCellValueFromList(row, 9);
        final className = _getCellValueFromList(row, 10);
        final armName = _getCellValueFromList(row, 11);
        final status = _getCellValueFromList(row, 12);

        students.add(StudentUploadData(
          rowNumber: rowIndex + 1,
          surname: surname,
          firstName: firstName,
          otherName: otherName,
          admissionNo: admissionNo,
          parentName: parentName,      // Changed from guardianName
          parentPhone: parentPhone,    // Changed from guardianPhone
          parentEmail: parentEmail,    // Changed from guardianEmail
          address: address,
          gender: gender,
          dateOfBirth: dob,
          className: className,
          armName: armName,
          status: status,
          classId: classNameToId[className],
          armId: armNameToId[armName]?[classNameToId[className]],
        ));
      } catch (e) {
        developer.log('Error parsing row $rowIndex: $e');
      }
    }

    return students;
  }

  String _getCellValue(List<Data?> row, int index) {
    if (index >= row.length) return '';
    final cell = row[index];
    if (cell == null || cell.value == null) return '';
    return cell.value.toString().trim();
  }

  String _getCellValueFromList(List row, int index) {
    if (index >= row.length) return '';
    final value = row[index];
    if (value == null) return '';
    return value.toString().trim();
  }

  /// Validate students
  Future<List<ValidationError>> validateStudents(List<StudentUploadData> students) async {
    List<ValidationError> errors = [];

    for (var student in students) {
      // Required fields
      if (student.surname.isEmpty) {
        errors.add(ValidationError(
          rowNumber: student.rowNumber,
          field: 'Surname',
          message: 'Surname is required',
        ));
      }

      if (student.firstName.isEmpty) {
        errors.add(ValidationError(
          rowNumber: student.rowNumber,
          field: 'First Name',
          message: 'First Name is required',
        ));
      }

      if (student.admissionNo.isEmpty) {
        errors.add(ValidationError(
          rowNumber: student.rowNumber,
          field: 'Admission No',
          message: 'Admission No is required',
        ));
      }

      if (student.parentName.isEmpty) {  // Changed from guardianName
        errors.add(ValidationError(
          rowNumber: student.rowNumber,
          field: 'Parent Name',  // Changed from 'Guardian Name'
          message: 'Parent Name is required',
        ));
      }

      if (student.parentPhone.isEmpty) {  // Changed from guardianPhone
        errors.add(ValidationError(
          rowNumber: student.rowNumber,
          field: 'Parent Phone',  // Changed from 'Guardian Phone'
          message: 'Parent Phone is required',
        ));
      }

      if (student.address.isEmpty) {
        errors.add(ValidationError(
          rowNumber: student.rowNumber,
          field: 'Address',
          message: 'Address is required',
        ));
      }

      // Gender validation
      if (student.gender.isEmpty) {
        errors.add(ValidationError(
          rowNumber: student.rowNumber,
          field: 'Gender',
          message: 'Gender is required',
        ));
      } else if (!['Male', 'Female'].contains(student.gender)) {
        errors.add(ValidationError(
          rowNumber: student.rowNumber,
          field: 'Gender',
          message: 'Gender must be Male or Female',
        ));
      }

      // Date of Birth validation
      if (student.dateOfBirth.isEmpty) {
        errors.add(ValidationError(
          rowNumber: student.rowNumber,
          field: 'Date of Birth',
          message: 'Date of Birth is required',
        ));
      } else {
        try {
          DateTime.parse(student.dateOfBirth);
        } catch (e) {
          errors.add(ValidationError(
            rowNumber: student.rowNumber,
            field: 'Date of Birth',
            message: 'Invalid date format. Use YYYY-MM-DD',
          ));
        }
      }

      // Class validation
      if (student.className.isEmpty) {
        errors.add(ValidationError(
          rowNumber: student.rowNumber,
          field: 'Class',
          message: 'Class is required',
        ));
      } else if (student.classId == null) {
        errors.add(ValidationError(
          rowNumber: student.rowNumber,
          field: 'Class',
          message: 'Class "${student.className}" not found in database',
        ));
      }

      // Arm validation
      if (student.armName.isEmpty) {
        errors.add(ValidationError(
          rowNumber: student.rowNumber,
          field: 'Arm',
          message: 'Arm is required',
        ));
      } else if (student.armId == null && student.classId != null) {
        errors.add(ValidationError(
          rowNumber: student.rowNumber,
          field: 'Arm',
          message: 'Arm "${student.armName}" not found for class "${student.className}"',
        ));
      }

      // Status validation
      if (student.status.isNotEmpty && !['Active', 'Inactive'].contains(student.status)) {
        errors.add(ValidationError(
          rowNumber: student.rowNumber,
          field: 'Status',
          message: 'Status must be Active or Inactive',
        ));
      }
    }

    return errors;
  }

  /// Import students to database
  Future<BatchUploadResult> importStudents(List<StudentUploadData> students) async {
    int successCount = 0;
    List<String> failedRows = [];

    for (var student in students) {
      try {
        // Map to database column names
        final studentMap = {
          'admissionNo': student.admissionNo,
          'surname': student.surname,
          'firstName': student.firstName,
          'otherName': student.otherName,
          'gender': student.gender,
          'dob': student.dateOfBirth,
          'classId': student.classId,
          'armId': student.armId,
          'address': student.address,
          'parentName': student.parentName,      // Correct column name
          'parentPhone': student.parentPhone,    // Correct column name
          'parentEmail': student.parentEmail.isEmpty ? null : student.parentEmail,  // Correct column name
          'isActive': student.status.isEmpty || student.status == 'Active' ? 1 : 0,
        };

        await _db.insertStudent(studentMap);
        successCount++;
      } catch (e) {
        failedRows.add('Row ${student.rowNumber}: ${e.toString()}');
      }
    }

    return BatchUploadResult(
      totalRows: students.length,
      successCount: successCount,
      failedCount: students.length - successCount,
      failedRows: failedRows,
    );
  }
}

/// Student upload data model
class StudentUploadData {
  final int rowNumber;
  final String surname;
  final String firstName;
  final String otherName;
  final String admissionNo;
  final String parentName;      // Changed from guardianName
  final String parentPhone;    // Changed from guardianPhone
  final String parentEmail;    // Changed from guardianEmail
  final String address;
  final String gender;
  final String dateOfBirth;
  final String className;
  final String armName;
  final String status;
  final int? classId;
  final int? armId;

  StudentUploadData({
    required this.rowNumber,
    required this.surname,
    required this.firstName,
    required this.otherName,
    required this.admissionNo,
    required this.parentName,      // Changed from guardianName
    required this.parentPhone,    // Changed from guardianPhone
    required this.parentEmail,    // Changed from guardianEmail
    required this.address,
    required this.gender,
    required this.dateOfBirth,
    required this.className,
    required this.armName,
    required this.status,
    this.classId,
    this.armId,
  });
}

/// Validation error model
class ValidationError {
  final int rowNumber;
  final String field;
  final String message;

  ValidationError({
    required this.rowNumber,
    required this.field,
    required this.message,
  });
}

/// Batch upload result
class BatchUploadResult {
  final int totalRows;
  final int successCount;
  final int failedCount;
  final List<String> failedRows;
  final List<String> duplicates;
  final List<ValidationError> errors;

  BatchUploadResult({
    required this.totalRows,
    required this.successCount,
    required this.failedCount,
    required this.failedRows,
    this.duplicates = const [],
    this.errors = const [],
  });

  // Convenience getter for compatibility
  int get failureCount => failedCount;
}