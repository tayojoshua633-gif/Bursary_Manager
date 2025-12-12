// lib/screens/students/student_list_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:bursary_manager/db/database_helper.dart';
import 'package:bursary_manager/models/student.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
// FIXED: Hide Border to avoid conflict with Flutter's Border
import 'package:excel/excel.dart' hide Border;

import 'student_form_screen.dart';
import 'student_details_screen.dart';
// ========================================
// 👇 ADD THIS IMPORT
// ========================================
import 'batch_student_upload_screen.dart';
// ========================================

class StudentListScreen extends StatefulWidget {
  const StudentListScreen({super.key});

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  final TextEditingController _searchCtrl = TextEditingController();

  List<Student> _students = [];
  List<Student> _allStudents = [];
  List<Map<String, dynamic>> _classes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    setState(() => _loading = true);

    // Load classes for export
    _classes = await _db.getClasses();

    // Load ACTIVE students WITH class and arm names using JOIN
    final db = await _db.database;
    final raw = await db.rawQuery('''
      SELECT 
        s.*,
        c.name as className,
        a.name as armName
      FROM students s
      LEFT JOIN classes c ON s.classId = c.id
      LEFT JOIN arms a ON s.armId = a.id
      WHERE s.isActive = 1
      ORDER BY s.surname ASC, s.firstName ASC
    ''');

    final list = raw.map((m) => Student.fromMap(m)).toList();

    if (!mounted) return;

    setState(() {
      _allStudents = list;
      _students = list;
      _loading = false;
    });
  }

  Future<void> _searchStudents(String keyword) async {
    if (keyword.trim().isEmpty) {
      setState(() => _students = _allStudents);
    } else {
      final kw = keyword.trim().toLowerCase();
      setState(() {
        _students = _allStudents.where((student) {
          final surname = student.surname.toLowerCase();
          final firstName = student.firstName.toLowerCase();
          final admissionNo = student.admissionNo.toLowerCase();
          final className = (student.className ?? '').toLowerCase();
          final armName = (student.armName ?? '').toLowerCase();
          
          return surname.contains(kw) || 
                 firstName.contains(kw) || 
                 admissionNo.contains(kw) ||
                 className.contains(kw) ||
                 armName.contains(kw);
        }).toList();
      });
    }
  }

  // ========================================
  // 👇 ADD THIS METHOD
  // ========================================
  Future<void> _openBatchUpload() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BatchStudentUploadScreen(),
      ),
    );
    
    if (result != null && result > 0) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$result students imported successfully!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
      
      // Refresh student list
      _loadStudents();
    }
  }
  // ========================================

  // Show export dialog
  Future<void> _showExportDialog() async {
    if (_classes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No classes available for export')),
      );
      return;
    }

    int? selectedClassId;
    String exportFormat = 'pdf';

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Export Student List'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select Class to Export:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Class',
                      ),
                      initialValue: selectedClassId,
                      items: _classes
                          .map((c) => DropdownMenuItem<int>(
                                value: c['id'],
                                child: Text(c['name']),
                              ))
                          .toList(),
                      onChanged: (v) {
                        setDialogState(() => selectedClassId = v);
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Export Format:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    
                    // Custom radio buttons (no deprecated Radio widget)
                    InkWell(
                      onTap: () {
                        setDialogState(() => exportFormat = 'pdf');
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: exportFormat == 'pdf' ? Colors.blue : Colors.grey[300]!,
                            width: exportFormat == 'pdf' ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          color: exportFormat == 'pdf' 
                              ? Colors.blue.withValues(alpha: 0.05)
                              : Colors.transparent,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: exportFormat == 'pdf' ? Colors.blue : Colors.grey,
                                  width: 2,
                                ),
                              ),
                              child: exportFormat == 'pdf'
                                  ? Center(
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.blue,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            const Text('PDF'),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    InkWell(
                      onTap: () {
                        setDialogState(() => exportFormat = 'excel');
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: exportFormat == 'excel' ? Colors.blue : Colors.grey[300]!,
                            width: exportFormat == 'excel' ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          color: exportFormat == 'excel' 
                              ? Colors.blue.withValues(alpha: 0.05)
                              : Colors.transparent,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: exportFormat == 'excel' ? Colors.blue : Colors.grey,
                                  width: 2,
                                ),
                              ),
                              child: exportFormat == 'excel'
                                  ? Center(
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.blue,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            const Text('Excel'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (selectedClassId != null) {
                      Navigator.pop(context);
                      if (exportFormat == 'pdf') {
                        _exportToPDF(selectedClassId!);
                      } else {
                        _exportToExcel(selectedClassId!);
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please select a class')),
                      );
                    }
                  },
                  child: const Text('Export'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Export to PDF
  Future<void> _exportToPDF(int classId) async {
    try {
      // Show loading
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Find class name
      final classMap = _classes.firstWhere((c) => c['id'] == classId);
      final className = classMap['name'];

      // Filter students for this class
      final classStudents = _allStudents.where((s) => s.classId == classId).toList();

      if (classStudents.isEmpty) {
        if (!mounted) return;
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No students found in this class')),
        );
        return;
      }

      // Create PDF
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context ctx) {
            return [
              // Title
              pw.Text(
                'Student List - $className',
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'Total Students: ${classStudents.length}',
                style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 20),

              // Table
              pw.Table.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.centerLeft,
                },
                data: [
                  ['No.', 'Surname', 'First Name', 'Admission No'],
                  ...classStudents.asMap().entries.map((entry) {
                    final idx = entry.key + 1;
                    final s = entry.value;
                    return [
                      idx.toString(),
                      s.surname,
                      s.firstName,
                      s.admissionNo,
                    ];
                  }),
                ],
              ),

              // Footer
              pw.SizedBox(height: 30),
              pw.Divider(),
              pw.SizedBox(height: 10),
              pw.Text(
                'Generated on: ${DateTime.now().toString().split('.')[0]}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            ];
          },
        ),
      );

      // Save
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/students_${className.replaceAll(' ', '_')}.pdf');
      await file.writeAsBytes(await pdf.save());

      if (!mounted) return;
      Navigator.pop(context); // Close loading

      // Share
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Student List - $className',
        text: 'Active student list for $className (${classStudents.length} students)',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF exported successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting PDF: $e')),
      );
    }
  }

  // Export to Excel
  Future<void> _exportToExcel(int classId) async {
    try {
      // Show loading
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Find class name
      final classMap = _classes.firstWhere((c) => c['id'] == classId);
      final className = classMap['name'];

      // Filter students for this class
      final classStudents = _allStudents.where((s) => s.classId == classId).toList();

      if (classStudents.isEmpty) {
        if (!mounted) return;
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No students found in this class')),
        );
        return;
      }

      // Create Excel
      final excel = Excel.createExcel();
      final sheet = excel['Students'];

      // Headers with styling
      final headers = ['No.', 'Surname', 'First Name', 'Other Name', 'Admission No', 'Arm'];
      for (var i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          ..value = TextCellValue(headers[i])
          ..cellStyle = CellStyle(
            bold: true,
            backgroundColorHex: ExcelColor.blue,
            fontColorHex: ExcelColor.white,
          );
      }

      // Data rows
      for (var i = 0; i < classStudents.length; i++) {
        final s = classStudents[i];
        final row = i + 1;

        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
            TextCellValue((i + 1).toString());
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value =
            TextCellValue(s.surname);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value =
            TextCellValue(s.firstName);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value =
            TextCellValue(s.otherName ?? '');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value =
            TextCellValue(s.admissionNo);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value =
            TextCellValue(s.armName ?? 'N/A');
      }

      // Save
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/students_${className.replaceAll(' ', '_')}.xlsx');
      final bytes = excel.encode();
      if (bytes != null) {
        await file.writeAsBytes(bytes);

        if (!mounted) return;
        Navigator.pop(context); // Close loading

        // Share
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'Student List - $className',
          text: 'Active student list for $className (${classStudents.length} students)',
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Excel file exported successfully!')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting Excel: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Students"),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Export Class List',
            onPressed: _showExportDialog,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStudents,
              child: Column(
                children: [
                  // ========================================
                  // 👇 UPDATED SECTION WITH BATCH UPLOAD
                  // ========================================
                  // BUTTONS ROW
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Row(
                      children: [
                        // REGISTER NEW STUDENT BUTTON
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const StudentFormScreen()),
                              ).then((value) {
                                if (value == true) _loadStudents();
                              });
                            },
                            icon: const Icon(Icons.person_add, size: 20),
                            label: const Text(
                              'Register',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(width: 12),
                        
                        // BATCH UPLOAD BUTTON
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _openBatchUpload,
                            icon: const Icon(Icons.upload_file, size: 20),
                            label: const Text(
                              'Batch Upload',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ========================================

                  // SEARCH BAR
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        hintText: "Search active students...",
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _loadStudents();
                                },
                              )
                            : null,
                      ),
                      onChanged: _searchStudents,
                    ),
                  ),

                  // INFO BANNER
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: Colors.blue.shade50,
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Showing active students only (${_students.length})",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // LIST
                  Expanded(
                    child: _students.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                Text(
                                  _searchCtrl.text.isEmpty
                                      ? "No active students found."
                                      : "No active students match your search.",
                                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _students.length,
                            itemBuilder: (context, index) {
                              final s = _students[index];
                              final String name = "${s.surname} ${s.firstName}".trim();

                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                child: ListTile(
                                  // NO PHOTO - Removed leading avatar
                                  title: Text(
                                    name,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text("Adm No: ${s.admissionNo}"),
                                      Text(
                                        "${s.className ?? 'N/A'} - ${s.armName ?? 'N/A'}",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  isThreeLine: true,
                                  trailing: const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                  ),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => StudentDetailsScreen(student: s),
                                      ),
                                    ).then((value) {
                                      if (value == true) _loadStudents();
                                    });
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}