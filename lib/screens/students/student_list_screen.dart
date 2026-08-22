// lib/screens/students/student_list_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:bursary_manager/data/database_helper_wrapper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/student.dart';
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
import '../../utils/permission_helper.dart';
import '../../utils/display_settings_helper.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/sibling_helper.dart';
import '../../utils/license_helper.dart';
import '../../widgets/sibling_mark.dart';
// ========================================

class StudentListScreen extends StatefulWidget {
  const StudentListScreen({super.key});

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final TextEditingController _searchCtrl = TextEditingController();

  List<Student> _students = [];
  List<Student> _allStudents = [];
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _arms = [];
  Set<String> _siblingPhones = {};
  bool _loading = true;
  int? _selectedClassFilter; // null means "All Classes"
  int? _selectedArmFilter; // null means "All Arms"
  Map<String, dynamic>? _currentUser;
  bool _canManageStudents = false;
  int? _licenseMaxStudents;
  bool _isMasterKey = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadStudents();
    _loadLicenseInfo();
  }

  Future<void> _loadLicenseInfo() async {
    final license = await _db.getActiveLicense();
    if (!mounted || license == null) return;

    final maxStudents = license['maxStudents'] as int?;
    final decoded = LicenseHelper.validateLicenseKey(
      license['licenseKey'] as String,
    );

    setState(() {
      _licenseMaxStudents =
          (maxStudents != null && maxStudents > 0) ? maxStudents : null;
      _isMasterKey = decoded?['isMasterKey'] == true;
    });
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userType = prefs.getString('userType') ?? 'bursar';
    final userId = prefs.getInt('userId') ?? 0;
    final username = prefs.getString('username') ?? 'User';

    final currentUser = {
      'id': userId,
      'userType': userType,
      'username': username,
    };

    final canManage = await PermissionHelper.hasPermission(currentUser, 'students_manage');

    setState(() {
      _currentUser = currentUser;
      _canManageStudents = canManage;
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    setState(() => _loading = true);

    // Load classes and arms
    _classes = await _db.getClasses();
    _arms = await _db.getArms();

    // Load ACTIVE students WITH class and arm names (works in all modes)
    final raw = await _db.getActiveStudentsWithDetails();
    final list = raw.map((m) => Student.fromMap(m)).toList();
    final siblingPhones = computeSiblingPhones(raw);

    if (!mounted) return;

    setState(() {
      _allStudents = list;
      _siblingPhones = siblingPhones;
      _loading = false;
    });

    // Apply filters to maintain filter state after refresh
    _applyFilters();
  }

  Future<void> _applyFilters() async {
    final keyword = _searchCtrl.text.trim();

    setState(() {
      // Start with all students
      List<Student> filtered = _allStudents;

      // Apply class filter first
      if (_selectedClassFilter != null) {
        filtered = filtered.where((s) => s.classId == _selectedClassFilter).toList();
      }

      // Apply arm filter
      if (_selectedArmFilter != null) {
        filtered = filtered.where((s) => s.armId == _selectedArmFilter).toList();
      }

      // Then apply search keyword
      if (keyword.isNotEmpty) {
        final kw = keyword.toLowerCase();
        filtered = filtered.where((student) {
          final surname = student.surname.toLowerCase();
          final firstName = student.firstName.toLowerCase();
          final otherName = (student.otherName ?? '').toLowerCase();
          final admissionNo = student.admissionNo.toLowerCase();
          final className = (student.className ?? '').toLowerCase();
          final armName = (student.armName ?? '').toLowerCase();

          return surname.contains(kw) ||
                 firstName.contains(kw) ||
                 otherName.contains(kw) ||
                 admissionNo.contains(kw) ||
                 className.contains(kw) ||
                 armName.contains(kw);
        }).toList();
      }

      _students = filtered;
    });
  }

  Future<void> _searchStudents(String keyword) async {
    _applyFilters();
  }

  String _buildFilterInfoText() {
    if (_selectedClassFilter == null && _selectedArmFilter == null) {
      var text = "Showing ${_students.length} of ${_allStudents.length} active students";
      if (!_isMasterKey && _licenseMaxStudents != null) {
        final remaining = _licenseMaxStudents! - _allStudents.length;
        text += remaining > 0
            ? " • $remaining slot${remaining == 1 ? '' : 's'} remaining of $_licenseMaxStudents"
            : " • Student limit reached ($_licenseMaxStudents)";
      }
      return text;
    }

    String filterText = "Showing ${_students.length} students";
    List<String> filters = [];

    if (_selectedClassFilter != null) {
      final className = _classes.firstWhere((c) => c['id'] == _selectedClassFilter)['name'];
      filters.add("Class: $className");
    }

    if (_selectedArmFilter != null) {
      final armName = _arms.firstWhere((a) => a['id'] == _selectedArmFilter)['name'];
      filters.add("Arm: $armName");
    }

    if (filters.isNotEmpty) {
      filterText += " (${filters.join(', ')})";
    }

    return filterText;
  }

  // Get filtered arms based on selected class
  List<Map<String, dynamic>> _getFilteredArms() {
    if (_selectedClassFilter == null) {
      return _arms; // Show all arms if no class is selected
    }
    // Filter arms by the selected class
    return _arms.where((arm) => arm['classId'] == _selectedClassFilter).toList();
  }

  // ========================================
  // 👇 ADD THIS METHOD
  // ========================================
  Future<void> _openBatchUpload() async {
    final result = await NavigationHelper.pushWithSidebar(
      context,
      page: const BatchStudentUploadScreen(),
      currentUser: _currentUser ?? {},
      pageId: 'student_management/students',
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
              pw.TableHelper.fromTextArray(
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
    final ds = DisplaySettingsProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Students"),
        actions: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: ds.cardPadding * 0.5, vertical: ds.cardPadding * 0.5),
            child: ElevatedButton.icon(
              onPressed: _showExportDialog,
              icon: Icon(Icons.file_download, size: ds.iconSize * 0.85),
              label: Text(
                'Export',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: ds.bodyFontSize),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue.shade700,
                elevation: 2,
                padding: EdgeInsets.symmetric(horizontal: ds.cardPadding, vertical: ds.cardPadding * 0.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
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
                  // 👇 UPDATED SECTION WITH BATCH UPLOAD (PERMISSION-PROTECTED)
                  // ========================================
                  // BUTTONS ROW - Only show for users with students_manage permission
                  if (_canManageStudents)
                    Padding(
                      padding: EdgeInsets.fromLTRB(ds.cardPadding * 0.75, ds.cardPadding * 0.75, ds.cardPadding * 0.75, ds.cardPadding * 0.5),
                      child: Row(
                        children: [
                          // REGISTER NEW STUDENT BUTTON
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                NavigationHelper.pushWithSidebar(
                                  context,
                                  page: const StudentFormScreen(),
                                  currentUser: _currentUser ?? {},
                                  pageId: 'student_management/students',
                                ).then((value) {
                                  if (value == true) _loadStudents();
                                });
                              },
                              icon: Icon(Icons.person_add, size: ds.iconSize * 0.85),
                              label: Text(
                                'Register',
                                style: TextStyle(fontSize: ds.bodyFontSize, fontWeight: FontWeight.w600),
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.symmetric(vertical: ds.cardPadding * 0.9),
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),

                          SizedBox(width: ds.cardPadding * 0.75),

                          // BATCH UPLOAD BUTTON
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _openBatchUpload,
                              icon: Icon(Icons.upload_file, size: ds.iconSize * 0.85),
                              label: Text(
                                'Batch Upload',
                                style: TextStyle(fontSize: ds.bodyFontSize, fontWeight: FontWeight.w600),
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.symmetric(vertical: ds.cardPadding * 0.9),
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

                  // CLASS AND ARM FILTER DROPDOWNS
                  Padding(
                    padding: EdgeInsets.fromLTRB(ds.cardPadding * 0.75, ds.cardPadding * 0.25, ds.cardPadding * 0.75, ds.cardPadding * 0.5),
                    child: Row(
                      children: [
                        // CLASS FILTER
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            padding: EdgeInsets.symmetric(horizontal: ds.cardPadding * 0.75),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int?>(
                                isExpanded: true,
                                value: _selectedClassFilter,
                                hint: Text('Filter by Class', style: TextStyle(fontSize: ds.bodyFontSize)),
                                icon: Icon(Icons.filter_list, size: ds.iconSize * 0.85),
                                items: [
                                  DropdownMenuItem<int?>(
                                    value: null,
                                    child: Text(
                                      'All Classes',
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: ds.bodyFontSize),
                                    ),
                                  ),
                                  ..._classes.map((c) => DropdownMenuItem<int?>(
                                        value: c['id'],
                                        child: Text(c['name'], style: TextStyle(fontSize: ds.bodyFontSize)),
                                      )),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _selectedClassFilter = value;
                                    // Reset arm filter if the currently selected arm doesn't belong to the new class
                                    if (_selectedArmFilter != null) {
                                      final filteredArms = value == null
                                          ? _arms
                                          : _arms.where((arm) => arm['classId'] == value).toList();
                                      final armExists = filteredArms.any((arm) => arm['id'] == _selectedArmFilter);
                                      if (!armExists) {
                                        _selectedArmFilter = null;
                                      }
                                    }
                                  });
                                  _applyFilters();
                                },
                              ),
                            ),
                          ),
                        ),

                        SizedBox(width: ds.cardPadding * 0.5),

                        // ARM FILTER
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            padding: EdgeInsets.symmetric(horizontal: ds.cardPadding * 0.75),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int?>(
                                isExpanded: true,
                                value: _selectedArmFilter,
                                hint: Text('Filter by Arm', style: TextStyle(fontSize: ds.bodyFontSize)),
                                icon: Icon(Icons.filter_list, size: ds.iconSize * 0.85),
                                items: [
                                  DropdownMenuItem<int?>(
                                    value: null,
                                    child: Text(
                                      'All Arms',
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: ds.bodyFontSize),
                                    ),
                                  ),
                                  ..._getFilteredArms().map((a) => DropdownMenuItem<int?>(
                                        value: a['id'],
                                        child: Text(a['name'], style: TextStyle(fontSize: ds.bodyFontSize)),
                                      )),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _selectedArmFilter = value;
                                  });
                                  _applyFilters();
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // SEARCH BAR
                  Padding(
                    padding: EdgeInsets.fromLTRB(ds.cardPadding * 0.75, ds.cardPadding * 0.25, ds.cardPadding * 0.75, ds.cardPadding * 0.5),
                    child: TextField(
                      controller: _searchCtrl,
                      style: TextStyle(fontSize: ds.bodyFontSize),
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.search, size: ds.iconSize),
                        border: const OutlineInputBorder(),
                        hintText: "Search active students...",
                        hintStyle: TextStyle(fontSize: ds.bodyFontSize),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear, size: ds.iconSize),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _applyFilters();
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
                    padding: EdgeInsets.symmetric(horizontal: ds.cardPadding, vertical: ds.cardPadding * 0.5),
                    color: Colors.blue.shade50,
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: ds.iconSize * 0.7, color: Colors.blue.shade700),
                        SizedBox(width: ds.cardPadding * 0.5),
                        Expanded(
                          child: Text(
                            _buildFilterInfoText(),
                            style: TextStyle(
                              fontSize: ds.subtitleFontSize,
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
                                Icon(Icons.people_outline, size: ds.iconSize * 2.5, color: Colors.grey.shade400),
                                SizedBox(height: ds.cardPadding),
                                Text(
                                  _searchCtrl.text.isEmpty
                                      ? "No active students found."
                                      : "No active students match your search.",
                                  style: TextStyle(fontSize: ds.bodyFontSize, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _students.length,
                            itemBuilder: (context, index) {
                              final s = _students[index];
                              final String name = [s.surname, s.firstName, s.otherName]
                                  .where((n) => n != null && n.trim().isNotEmpty)
                                  .join(' ')
                                  .trim();

                              return Card(
                                margin: EdgeInsets.symmetric(horizontal: ds.cardPadding * 0.75, vertical: ds.cardPadding * 0.25),
                                child: ListTile(
                                  // NO PHOTO - Removed leading avatar
                                  title: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          name,
                                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: ds.bodyFontSize),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      SiblingMark(show: isSiblingPhone(s.parentPhone, _siblingPhones)),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text("Adm No: ${s.admissionNo}", style: TextStyle(fontSize: ds.subtitleFontSize)),
                                      Text(
                                        "${s.className ?? 'N/A'} - ${s.armName ?? 'N/A'}",
                                        style: TextStyle(
                                          fontSize: ds.subtitleFontSize,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  isThreeLine: true,
                                  trailing: Icon(
                                    Icons.arrow_forward_ios,
                                    size: ds.iconSize * 0.7,
                                  ),
                                  onTap: () {
                                    NavigationHelper.pushWithSidebar(
                                      context,
                                      page: StudentDetailsScreen(student: s),
                                      currentUser: _currentUser ?? {},
                                      pageId: 'student_management/students',
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