// lib/utils/batch_student_upload_helper.dart

import 'dart:io';
import 'package:excel/excel.dart';
import '../db/database_helper.dart';

class StudentUploadData {
  final String surname;
  final String firstName;
  final String? otherName;
  final String admissionNo;
  final String? guardianName;
  final String? guardianPhone;
  final String? guardianEmail;
  final String? address;
  final String? gender;
  final String? dateOfBirth;
  final int classId;
  final int armId;
  final String? status;
  final int rowNumber; // For error reporting

  StudentUploadData({
    required this.surname,
    required this.firstName,
    this.otherName,
    required this.admissionNo,
    this.guardianName,
    this.guardianPhone,
    this.guardianEmail,
    this.address,
    this.gender,
    this.dateOfBirth,
    required this.classId,
    required this.armId,
    this.status = 'Active',
    required this.rowNumber,
  });

  Map<String, dynamic> toMap() {
    return {
      'surname': surname,
      'firstName': firstName,
      'otherName': otherName,
      'admissionNo': admissionNo,
      'guardianName': guardianName,
      'guardianPhone': guardianPhone,
      'guardianEmail': guardianEmail,
      'address': address,
      'gender': gender,
      'dateOfBirth': dateOfBirth,
      'classId': classId,
      'armId': armId,
      'status': status ?? 'Active',
    };
  }
}

class ValidationError {
  final int rowNumber;
  final String field;
  final String message;

  ValidationError({
    required this.rowNumber,
    required this.field,
    required this.message,
  });

  @override
  String toString() => 'Row $rowNumber: $field - $message';
}

class BatchUploadResult {
  final int totalRows;
  final int successCount;
  final int failureCount;
  final List<ValidationError> errors;
  final List<String> duplicates;

  BatchUploadResult({
    required this.totalRows,
    required this.successCount,
    required this.failureCount,
    required this.errors,
    required this.duplicates,
  });
}

class BatchStudentUploadHelper {
  final DatabaseHelper _db = DatabaseHelper();

  // ========================================
  // PARSE EXCEL FILE
  // ========================================
  Future<List<StudentUploadData>> parseExcelFile(
    String filePath,
    Map<String, int> classNameToId,
    Map<String, Map<int, int>> armNameToId, // armName -> {classId: armId}
  ) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final excel = Excel.decodeBytes(bytes);

    final List<StudentUploadData> students = [];
    
    for (var table in excel.tables.keys) {
      final sheet = excel.tables[table]!;
      
      // Skip header row (row 0)
      for (var rowIndex = 1; rowIndex < sheet.maxRows; rowIndex++) {
        final row = sheet.rows[rowIndex];
        
        // Skip empty rows
        if (_isRowEmpty(row)) continue;

        try {
          final student = _parseRow(
            row,
            rowIndex + 1, // +1 for 1-based row numbering
            classNameToId,
            armNameToId,
          );
          students.add(student);
        } catch (e) {
          // Skip invalid rows, will be caught in validation
          debugPrint('Error parsing row ${rowIndex + 1}: $e');
        }
      }
    }

    return students;
  }

  // ========================================
  // PARSE CSV FILE
  // ========================================
  Future<List<StudentUploadData>> parseCsvFile(
    String filePath,
    Map<String, int> classNameToId,
    Map<String, Map<int, int>> armNameToId,
  ) async {
    final file = File(filePath);
    final csvString = await file.readAsString();
    
    // Simple CSV parser (handles basic cases)
    final lines = csvString.split('\n');
    final List<StudentUploadData> students = [];
    
    // Skip header row (row 0)
    for (var rowIndex = 1; rowIndex < lines.length; rowIndex++) {
      final line = lines[rowIndex].trim();
      
      // Skip empty lines
      if (line.isEmpty) continue;
      
      // Split by comma (basic CSV parsing)
      final row = line.split(',').map((cell) => cell.trim()).toList();
      
      // Skip empty rows
      if (row.every((cell) => cell.isEmpty)) continue;

      try {
        final student = _parseCsvRow(
          row,
          rowIndex + 1,
          classNameToId,
          armNameToId,
        );
        students.add(student);
      } catch (e) {
        debugPrint('Error parsing row ${rowIndex + 1}: $e');
      }
    }

    return students;
  }

  // ========================================
  // VALIDATE STUDENTS
  // ========================================
  Future<List<ValidationError>> validateStudents(
    List<StudentUploadData> students,
  ) async {
    final List<ValidationError> errors = [];
    final Set<String> admissionNumbers = {};
    
    final db = await _db.database;

    for (var student in students) {
      // Required field validation
      if (student.surname.trim().isEmpty) {
        errors.add(ValidationError(
          rowNumber: student.rowNumber,
          field: 'Surname',
          message: 'Surname is required',
        ));
      }

      if (student.firstName.trim().isEmpty) {
        errors.add(ValidationError(
          rowNumber: student.rowNumber,
          field: 'First Name',
          message: 'First name is required',
        ));
      }

      if (student.admissionNo.trim().isEmpty) {
        errors.add(ValidationError(
          rowNumber: student.rowNumber,
          field: 'Admission No',
          message: 'Admission number is required',
        ));
      } else {
        // Check for duplicates in the file
        if (admissionNumbers.contains(student.admissionNo)) {
          errors.add(ValidationError(
            rowNumber: student.rowNumber,
            field: 'Admission No',
            message: 'Duplicate admission number in file',
          ));
        }
        admissionNumbers.add(student.admissionNo);

        // Check if admission number already exists in database
        final existing = await db.query(
          'students',
          where: 'admissionNo = ?',
          whereArgs: [student.admissionNo],
          limit: 1,
        );
        
        if (existing.isNotEmpty) {
          errors.add(ValidationError(
            rowNumber: student.rowNumber,
            field: 'Admission No',
            message: 'Admission number already exists in database',
          ));
        }
      }

      // Class ID validation
      if (student.classId <= 0) {
        errors.add(ValidationError(
          rowNumber: student.rowNumber,
          field: 'Class',
          message: 'Invalid class name',
        ));
      }

      // Arm ID validation
      if (student.armId <= 0) {
        errors.add(ValidationError(
          rowNumber: student.rowNumber,
          field: 'Arm',
          message: 'Invalid arm name',
        ));
      }

      // Gender validation (optional but if provided, must be valid)
      if (student.gender != null && 
          student.gender!.isNotEmpty && 
          !['Male', 'Female', 'M', 'F'].contains(student.gender)) {
        errors.add(ValidationError(
          rowNumber: student.rowNumber,
          field: 'Gender',
          message: 'Gender must be Male/Female or M/F',
        ));
      }

      // Phone validation (optional but if provided, must be valid format)
      if (student.guardianPhone != null && student.guardianPhone!.isNotEmpty) {
        final phone = student.guardianPhone!.replaceAll(RegExp(r'[^\d]'), '');
        if (phone.length < 10 || phone.length > 15) {
          errors.add(ValidationError(
            rowNumber: student.rowNumber,
            field: 'Guardian Phone',
            message: 'Invalid phone number format',
          ));
        }
      }
    }

    return errors;
  }

  // ========================================
  // IMPORT STUDENTS
  // ========================================
  Future<BatchUploadResult> importStudents(
    List<StudentUploadData> students,
  ) async {
    int successCount = 0;
    int failureCount = 0;
    final List<ValidationError> errors = [];
    final List<String> duplicates = [];
    
    final db = await _db.database;

    for (var student in students) {
      try {
        // Check for duplicates again (just to be safe)
        final existing = await db.query(
          'students',
          where: 'admissionNo = ?',
          whereArgs: [student.admissionNo],
          limit: 1,
        );
        
        if (existing.isNotEmpty) {
          duplicates.add('Row ${student.rowNumber}: ${student.admissionNo}');
          failureCount++;
          continue;
        }

        // Normalize gender
        String? normalizedGender = student.gender;
        if (normalizedGender != null && normalizedGender.isNotEmpty) {
          normalizedGender = normalizedGender.toUpperCase().startsWith('M') ? 'Male' : 'Female';
        }

        // Insert student
        final studentData = student.toMap();
        studentData['gender'] = normalizedGender;
        
        await db.insert('students', studentData);
        successCount++;
      } catch (e) {
        errors.add(ValidationError(
          rowNumber: student.rowNumber,
          field: 'Database',
          message: 'Error inserting: ${e.toString()}',
        ));
        failureCount++;
      }
    }

    return BatchUploadResult(
      totalRows: students.length,
      successCount: successCount,
      failureCount: failureCount,
      errors: errors,
      duplicates: duplicates,
    );
  }

  // ========================================
  // HELPER METHODS
  // ========================================
  bool _isRowEmpty(List<Data?> row) {
    return row.every((cell) => cell == null || cell.value == null || cell.value.toString().trim().isEmpty);
  }

  StudentUploadData _parseRow(
    List<Data?> row,
    int rowNumber,
    Map<String, int> classNameToId,
    Map<String, Map<int, int>> armNameToId,
  ) {
    String getCellValue(int index) {
      if (index >= row.length) return '';
      final cell = row[index];
      if (cell == null || cell.value == null) return '';
      return cell.value.toString().trim();
    }

    final surname = getCellValue(0);
    final firstName = getCellValue(1);
    final otherName = getCellValue(2);
    final admissionNo = getCellValue(3);
    final className = getCellValue(4);
    final armName = getCellValue(5);
    final guardianName = getCellValue(6);
    final guardianPhone = getCellValue(7);
    final guardianEmail = getCellValue(8);
    final address = getCellValue(9);
    final gender = getCellValue(10);
    final dateOfBirth = getCellValue(11);

    // Get class ID
    final classId = classNameToId[className] ?? -1;
    
    // Get arm ID
    int armId = -1;
    if (classId > 0 && armNameToId.containsKey(armName)) {
      armId = armNameToId[armName]![classId] ?? -1;
    }

    return StudentUploadData(
      surname: surname,
      firstName: firstName,
      otherName: otherName.isEmpty ? null : otherName,
      admissionNo: admissionNo,
      guardianName: guardianName.isEmpty ? null : guardianName,
      guardianPhone: guardianPhone.isEmpty ? null : guardianPhone,
      guardianEmail: guardianEmail.isEmpty ? null : guardianEmail,
      address: address.isEmpty ? null : address,
      gender: gender.isEmpty ? null : gender,
      dateOfBirth: dateOfBirth.isEmpty ? null : dateOfBirth,
      classId: classId,
      armId: armId,
      rowNumber: rowNumber,
    );
  }

  StudentUploadData _parseCsvRow(
    List<String> row,
    int rowNumber,
    Map<String, int> classNameToId,
    Map<String, Map<int, int>> armNameToId,
  ) {
    String getCellValue(int index) {
      if (index >= row.length) return '';
      return row[index].trim();
    }

    final surname = getCellValue(0);
    final firstName = getCellValue(1);
    final otherName = getCellValue(2);
    final admissionNo = getCellValue(3);
    final className = getCellValue(4);
    final armName = getCellValue(5);
    final guardianName = getCellValue(6);
    final guardianPhone = getCellValue(7);
    final guardianEmail = getCellValue(8);
    final address = getCellValue(9);
    final gender = getCellValue(10);
    final dateOfBirth = getCellValue(11);

    final classId = classNameToId[className] ?? -1;
    
    int armId = -1;
    if (classId > 0 && armNameToId.containsKey(armName)) {
      armId = armNameToId[armName]![classId] ?? -1;
    }

    return StudentUploadData(
      surname: surname,
      firstName: firstName,
      otherName: otherName.isEmpty ? null : otherName,
      admissionNo: admissionNo,
      guardianName: guardianName.isEmpty ? null : guardianName,
      guardianPhone: guardianPhone.isEmpty ? null : guardianPhone,
      guardianEmail: guardianEmail.isEmpty ? null : guardianEmail,
      address: address.isEmpty ? null : address,
      gender: gender.isEmpty ? null : gender,
      dateOfBirth: dateOfBirth.isEmpty ? null : dateOfBirth,
      classId: classId,
      armId: armId,
      rowNumber: rowNumber,
    );
  }

  // ========================================
  // GENERATE TEMPLATE
  // ========================================
  Future<File> generateTemplate(String outputPath) async {
    final excel = Excel.createExcel();
    final sheet = excel['Students'];

    // Headers
    final headers = [
      'Surname*',
      'First Name*',
      'Other Name',
      'Admission No*',
      'Class*',
      'Arm*',
      'Guardian Name',
      'Guardian Phone',
      'Guardian Email',
      'Address',
      'Gender (M/F)',
      'Date of Birth (YYYY-MM-DD)',
    ];

    for (var i = 0; i < headers.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
        ..value = TextCellValue(headers[i])
        ..cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.blue,
          fontColorHex: ExcelColor.white,
        );
    }

    // Sample data row
    final sampleData = [
      'Doe',
      'John',
      'Michael',
      'STU001',
      'JSS 1',
      'A',
      'Mr. John Doe Sr.',
      '08012345678',
      'parent@example.com',
      '123 Main Street, Lagos',
      'M',
      '2010-05-15',
    ];

    for (var i = 0; i < sampleData.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value = 
        TextCellValue(sampleData[i]);
    }

    // Save file
    final fileBytes = excel.save();
    final file = File(outputPath);
    await file.writeAsBytes(fileBytes!);
    
    return file;
  }
}

// Simple debug print function
void debugPrint(String message) {
  // Only print in debug mode
  assert(() {
    // ignore: avoid_print
    print(message);
    return true;
  }());
}