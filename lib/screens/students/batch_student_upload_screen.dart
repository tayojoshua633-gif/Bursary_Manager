// lib/screens/students/batch_student_upload_screen.dart

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../db/database_helper.dart';
import '../../utils/batch_student_upload_helper.dart';

class BatchStudentUploadScreen extends StatefulWidget {
  const BatchStudentUploadScreen({super.key});

  @override
  State<BatchStudentUploadScreen> createState() => _BatchStudentUploadScreenState();
}

class _BatchStudentUploadScreenState extends State<BatchStudentUploadScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  final BatchStudentUploadHelper _uploadHelper = BatchStudentUploadHelper();

  bool _processing = false;
  String? _selectedFilePath;
  String? _selectedFileName;
  
  List<StudentUploadData>? _parsedStudents;
  List<ValidationError>? _validationErrors;
  BatchUploadResult? _uploadResult;

  int _currentStep = 0; // 0: Select file, 1: Preview/Validate, 2: Results

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Batch Student Upload'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _downloadTemplate,
            tooltip: 'Download Template',
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showHelp,
            tooltip: 'Help',
          ),
        ],
      ),
      body: _processing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Processing file...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStepper(),
                  const SizedBox(height: 24),
                  if (_currentStep == 0) _buildFileSelection(),
                  if (_currentStep == 1) _buildPreviewAndValidation(),
                  if (_currentStep == 2) _buildResults(),
                ],
              ),
            ),
    );
  }

  // ========================================
  // STEPPER
  // ========================================
  Widget _buildStepper() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _buildStepIndicator(
              step: 1,
              label: 'Select File',
              isActive: _currentStep == 0,
              isCompleted: _currentStep > 0,
            ),
            Expanded(child: _buildStepLine(_currentStep > 0)),
            _buildStepIndicator(
              step: 2,
              label: 'Preview',
              isActive: _currentStep == 1,
              isCompleted: _currentStep > 1,
            ),
            Expanded(child: _buildStepLine(_currentStep > 1)),
            _buildStepIndicator(
              step: 3,
              label: 'Results',
              isActive: _currentStep == 2,
              isCompleted: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator({
    required int step,
    required String label,
    required bool isActive,
    required bool isCompleted,
  }) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted
                ? Colors.green
                : isActive
                    ? Colors.indigo
                    : Colors.grey.shade300,
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : Text(
                    '$step',
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.grey.shade600,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? Colors.indigo : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine(bool isCompleted) {
    return Container(
      height: 2,
      margin: const EdgeInsets.only(bottom: 20),
      color: isCompleted ? Colors.green : Colors.grey.shade300,
    );
  }

  // ========================================
  // STEP 1: FILE SELECTION
  // ========================================
  Widget _buildFileSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Upload Student Data',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Upload an Excel (.xlsx) or CSV file containing student information',
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),

        // Info card
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    const Text(
                      'Before you start:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildInfoItem('Download the template file first'),
                _buildInfoItem('Fill in student information'),
                _buildInfoItem('Required fields: Surname, First Name, Admission No, Class, Arm'),
                _buildInfoItem('Save and upload the file'),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Template download button
        OutlinedButton.icon(
          onPressed: _downloadTemplate,
          icon: const Icon(Icons.download),
          label: const Text('Download Template'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.all(16),
            side: const BorderSide(color: Colors.indigo, width: 2),
            foregroundColor: Colors.indigo,
          ),
        ),

        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 24),

        // File selection
        if (_selectedFileName == null) ...[
          InkWell(
            onTap: _pickFile,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.indigo, width: 2, style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(12),
                color: Colors.indigo.shade50,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_upload, size: 64, color: Colors.indigo.shade300),
                  const SizedBox(height: 16),
                  const Text(
                    'Tap to select file',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Excel (.xlsx) or CSV (.csv)',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          // Selected file display
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green.shade700, size: 32),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'File Selected',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedFileName!,
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _selectedFilePath = null;
                            _selectedFileName = null;
                            _parsedStudents = null;
                            _validationErrors = null;
                          });
                        },
                        icon: const Icon(Icons.close),
                        tooltip: 'Remove file',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _parseFile,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Next: Preview Data'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, size: 20, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  // ========================================
  // STEP 2: PREVIEW & VALIDATION
  // ========================================
  Widget _buildPreviewAndValidation() {
    if (_parsedStudents == null) {
      return const Center(child: Text('No data parsed'));
    }

    final hasErrors = _validationErrors != null && _validationErrors!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Preview & Validation',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _currentStep = 0;
                  _parsedStudents = null;
                  _validationErrors = null;
                });
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Summary card
        Card(
          color: hasErrors ? Colors.orange.shade50 : Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      hasErrors ? Icons.warning : Icons.check_circle,
                      color: hasErrors ? Colors.orange.shade700 : Colors.green.shade700,
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasErrors ? 'Validation Issues Found' : 'Ready to Import',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_parsedStudents!.length} students found in file',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (hasErrors) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.orange.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${_validationErrors!.length} validation errors found. Please fix them before importing.',
                            style: TextStyle(color: Colors.orange.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Errors section
        if (hasErrors) ...[
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border(bottom: BorderSide(color: Colors.red.shade200)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Validation Errors (${_validationErrors!.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _validationErrors!.length > 10 ? 10 : _validationErrors!.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final error = _validationErrors![index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.red.shade100,
                        child: Text(
                          '${error.rowNumber}',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(error.field),
                      subtitle: Text(error.message),
                    );
                  },
                ),
                if (_validationErrors!.length > 10) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'And ${_validationErrors!.length - 10} more errors...',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Preview section
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  border: Border(bottom: BorderSide(color: Colors.indigo.shade200)),
                ),
                child: const Text(
                  'Data Preview (First 5 rows)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Row')),
                    DataColumn(label: Text('Surname')),
                    DataColumn(label: Text('First Name')),
                    DataColumn(label: Text('Admission No')),
                    DataColumn(label: Text('Class')),
                    DataColumn(label: Text('Status')),
                  ],
                  rows: _parsedStudents!
                      .take(5)
                      .map((student) {
                        final hasError = _validationErrors?.any(
                          (e) => e.rowNumber == student.rowNumber,
                        ) ?? false;
                        
                        return DataRow(
                          color: WidgetStateProperty.all(
                            hasError ? Colors.red.shade50 : null,
                          ),
                          cells: [
                            DataCell(Text('${student.rowNumber}')),
                            DataCell(Text(student.surname)),
                            DataCell(Text(student.firstName)),
                            DataCell(Text(student.admissionNo)),
                            DataCell(Text('${student.classId}')),
                            DataCell(
                              Icon(
                                hasError ? Icons.error : Icons.check_circle,
                                color: hasError ? Colors.red : Colors.green,
                                size: 20,
                              ),
                            ),
                          ],
                        );
                      })
                      .toList(),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _currentStep = 0;
                    _parsedStudents = null;
                    _validationErrors = null;
                  });
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: hasErrors ? null : _importStudents,
                icon: const Icon(Icons.upload),
                label: Text(hasErrors ? 'Fix Errors First' : 'Import Students'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                  disabledBackgroundColor: Colors.grey.shade300,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ========================================
  // STEP 3: RESULTS
  // ========================================
  Widget _buildResults() {
    if (_uploadResult == null) {
      return const Center(child: Text('No results'));
    }

    final result = _uploadResult!;
    final hasFailures = result.failureCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Import Results',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        // Summary card
        Card(
          color: hasFailures ? Colors.orange.shade50 : Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(
                  hasFailures ? Icons.warning : Icons.check_circle,
                  color: hasFailures ? Colors.orange.shade700 : Colors.green.shade700,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  hasFailures ? 'Import Completed with Errors' : 'Import Successful!',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(
                      'Total',
                      '${result.totalRows}',
                      Colors.blue,
                    ),
                    _buildStatItem(
                      'Success',
                      '${result.successCount}',
                      Colors.green,
                    ),
                    _buildStatItem(
                      'Failed',
                      '${result.failureCount}',
                      Colors.red,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Failures section
        if (result.duplicates.isNotEmpty) ...[
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    border: Border(bottom: BorderSide(color: Colors.orange.shade200)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.orange.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Duplicate Admission Numbers (${result.duplicates.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: result.duplicates.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    return ListTile(
                      leading: Icon(Icons.error, color: Colors.orange.shade700),
                      title: Text(result.duplicates[index]),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],

        if (result.errors.isNotEmpty) ...[
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border(bottom: BorderSide(color: Colors.red.shade200)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Import Errors (${result.errors.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: result.errors.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final error = result.errors[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.red.shade100,
                        child: Text(
                          '${error.rowNumber}',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(error.field),
                      subtitle: Text(error.message),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Action buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _currentStep = 0;
                    _selectedFilePath = null;
                    _selectedFileName = null;
                    _parsedStudents = null;
                    _validationErrors = null;
                    _uploadResult = null;
                  });
                },
                icon: const Icon(Icons.upload),
                label: const Text('Upload Another File'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, result.successCount),
                icon: const Icon(Icons.check),
                label: const Text('Done'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  // ========================================
  // ACTIONS
  // ========================================
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'csv'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFilePath = result.files.single.path;
          _selectedFileName = result.files.single.name;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _parseFile() async {
    if (_selectedFilePath == null) return;

    setState(() => _processing = true);

    try {
      // Load classes and arms
      final db = await _db.database;
      
      // Get classes
      final classes = await db.query('classes', orderBy: 'name ASC');
      
      // Get arms
      final arms = await db.query('arms', orderBy: 'name ASC');

      // Build maps for lookup
      final Map<String, int> classNameToId = {};
      for (var cls in classes) {
        classNameToId[cls['name'].toString()] = cls['id'] as int;
      }

      final Map<String, Map<int, int>> armNameToId = {};
      for (var arm in arms) {
        final armName = arm['name'].toString();
        final classId = arm['classId'] as int;
        final armId = arm['id'] as int;

        if (!armNameToId.containsKey(armName)) {
          armNameToId[armName] = {};
        }
        armNameToId[armName]![classId] = armId;
      }

      // Parse file
      List<StudentUploadData> students;
      if (_selectedFilePath!.endsWith('.xlsx')) {
        students = await _uploadHelper.parseExcelFile(
          _selectedFilePath!,
          classNameToId,
          armNameToId,
        );
      } else {
        students = await _uploadHelper.parseCsvFile(
          _selectedFilePath!,
          classNameToId,
          armNameToId,
        );
      }

      // Validate
      final errors = await _uploadHelper.validateStudents(students);

      setState(() {
        _parsedStudents = students;
        _validationErrors = errors;
        _currentStep = 1;
        _processing = false;
      });
    } catch (e) {
      setState(() => _processing = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error parsing file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _importStudents() async {
    if (_parsedStudents == null) return;

    setState(() => _processing = true);

    try {
      final result = await _uploadHelper.importStudents(_parsedStudents!);

      setState(() {
        _uploadResult = result;
        _currentStep = 2;
        _processing = false;
      });
    } catch (e) {
      setState(() => _processing = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error importing students: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _downloadTemplate() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final outputPath = '${dir.path}/student_upload_template.xlsx';
      
      final file = await _uploadHelper.generateTemplate(outputPath);

      if (!mounted) return;

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Student Upload Template',
        text: 'Use this template to upload student data',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Template ready to share'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating template: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batch Upload Help'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'How to upload students:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              _buildHelpStep('1', 'Download the template file'),
              _buildHelpStep('2', 'Fill in student information'),
              _buildHelpStep('3', 'Upload the completed file'),
              _buildHelpStep('4', 'Review and fix any errors'),
              _buildHelpStep('5', 'Import students'),
              const SizedBox(height: 16),
              const Text(
                'Required Fields:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text('• Surname'),
              const Text('• First Name'),
              const Text('• Admission Number (must be unique)'),
              const Text('• Class (must match existing class name)'),
              const Text('• Arm (must match existing arm name)'),
              const SizedBox(height: 16),
              const Text(
                'Optional Fields:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text('• Other Name'),
              const Text('• Guardian Name'),
              const Text('• Guardian Phone'),
              const Text('• Guardian Email'),
              const Text('• Address'),
              const Text('• Gender (M/F or Male/Female)'),
              const Text('• Date of Birth (YYYY-MM-DD)'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Colors.indigo,
            child: Text(
              number,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}