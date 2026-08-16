import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../db/database_helper.dart';
import '../../models/external_examination.dart';
import '../../models/examination_registration.dart';
import '../../utils/display_settings_helper.dart';
import '../../utils/sibling_helper.dart';
import '../../widgets/sibling_mark.dart';

class RegisteredStudentsScreen extends StatefulWidget {
  const RegisteredStudentsScreen({super.key});

  @override
  State<RegisteredStudentsScreen> createState() =>
      _RegisteredStudentsScreenState();
}

class _RegisteredStudentsScreenState extends State<RegisteredStudentsScreen> {
  final _db = DatabaseHelper();

  List<ExternalExamination> _examinations = [];
  ExternalExamination? _selectedExam; // null = all
  List<String> _sessions = [];
  String? _selectedSession; // null = active session (set on init)
  List<ExaminationRegistration> _all = [];
  List<ExaminationRegistration> _filtered = [];
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  Set<String> _siblingPhones = {};

  @override
  void initState() {
    super.initState();
    _loadInit();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInit() async {
    final examRows = await _db.getExternalExaminations();
    final sessionData = await _db.getActiveSession();
    final activeSession = sessionData?['sessionName'] as String? ?? '';
    final sessionList = await _db.getExamRegistrationSessions();
    // Ensure active session is in the list even if no registrations yet
    final allSessions = {activeSession, ...sessionList}
        .where((s) => s.isNotEmpty)
        .toList();
    if (!mounted) return;
    setState(() {
      _examinations = examRows.map(ExternalExamination.fromMap).toList();
      _sessions = allSessions;
      _selectedSession = activeSession.isNotEmpty ? activeSession : null;
    });
    await _loadStudents();
  }

  Future<void> _loadStudents() async {
    setState(() => _loading = true);
    final rows = await _db.getExaminationRegistrations(
        examinationId: _selectedExam?.id, session: _selectedSession);
    final siblingPhones = computeSiblingPhones(await _db.getActiveStudents());
    if (!mounted) return;
    setState(() {
      _all = rows.map(ExaminationRegistration.fromMap).toList();
      _siblingPhones = siblingPhones;
      _loading = false;
    });
    _applyFilter();
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = _all.where((r) {
        if (q.isEmpty) return true;
        return (r.fullName.toLowerCase().contains(q)) ||
            (r.admissionNo?.toLowerCase().contains(q) ?? false) ||
            (r.className?.toLowerCase().contains(q) ?? false) ||
            (r.armName?.toLowerCase().contains(q) ?? false) ||
            (r.examinationName?.toLowerCase().contains(q) ?? false) ||
            (r.examinationCode?.toLowerCase().contains(q) ?? false);
      }).toList();
    });
  }

  // ---------- PDF generation ----------

  Future<pw.Document> _buildPdf(String schoolName) async {
    final pdf = pw.Document();
    final examLabel = _selectedExam == null
        ? 'All Examinations'
        : '${_selectedExam!.name} (${_selectedExam!.code})';
    final sessionLabel = _selectedSession ?? 'All Sessions';
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    // Group students by exam when showing "all"
    final Map<String, List<ExaminationRegistration>> groups = {};
    for (final r in _filtered) {
      final key = _selectedExam == null
          ? '${r.examinationName} (${r.examinationCode})'
          : examLabel;
      groups.putIfAbsent(key, () => []).add(r);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              schoolName,
              style: pw.TextStyle(
                  fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'External Examination — Registered Students',
              style: pw.TextStyle(
                  fontSize: 12, color: PdfColors.grey700),
            ),
            pw.Text(
              examLabel,
              style: pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.indigo700,
                  fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Session: $sessionLabel',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 1),
          ],
        ),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generated: $dateStr',
                style: const pw.TextStyle(
                    fontSize: 7, color: PdfColors.grey600)),
            pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(
                    fontSize: 7, color: PdfColors.grey600)),
          ],
        ),
        build: (_) {
          final widgets = <pw.Widget>[];

          for (final entry in groups.entries) {
            widgets.add(pw.SizedBox(height: 10));
            widgets.add(pw.Text(
              entry.key,
              style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.indigo800),
            ));
            widgets.add(pw.SizedBox(height: 4));
            widgets.add(
              pw.TableHelper.fromTextArray(
                headers: [
                  'S/N',
                  'Adm. No.',
                  'Full Name',
                  'Gender',
                  'Class',
                  'Arm',
                  'Reg. Date',
                ],
                data: entry.value.asMap().entries.map((e) {
                  final idx = e.key + 1;
                  final r = e.value;
                  return [
                    '$idx',
                    r.admissionNo ?? '',
                    r.fullName,
                    r.gender ?? '',
                    r.className ?? '',
                    r.armName ?? '',
                    r.registrationDate,
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 8,
                    color: PdfColors.white),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.indigo700),
                cellStyle: const pw.TextStyle(fontSize: 8),
                cellAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.center,
                  4: pw.Alignment.centerLeft,
                  5: pw.Alignment.centerLeft,
                  6: pw.Alignment.center,
                },
                border: pw.TableBorder.all(
                    color: PdfColors.grey300, width: 0.5),
                rowDecoration: const pw.BoxDecoration(
                    color: PdfColors.white),
                oddRowDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey100),
              ),
            );
            widgets.add(pw.SizedBox(height: 4));
            widgets.add(pw.Text(
              'Total: ${entry.value.length} student(s)',
              style: pw.TextStyle(
                  fontSize: 8,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColors.grey700),
            ));
            widgets.add(pw.SizedBox(height: 8));
          }

          if (_filtered.isEmpty) {
            widgets.add(pw.Center(
                child: pw.Text('No students registered.',
                    style: const pw.TextStyle(
                        fontSize: 10, color: PdfColors.grey600))));
          }

          widgets.add(pw.SizedBox(height: 16));
          widgets.add(pw.Divider());
          widgets.add(pw.Text(
            'Total Registered: ${_filtered.length} student(s)',
            style: pw.TextStyle(
                fontSize: 9, fontWeight: pw.FontWeight.bold),
          ));

          return widgets;
        },
      ),
    );

    return pdf;
  }

  Future<String> _getSchoolName() async {
    final db = await _db.database;
    final rows = await db.query('school_profile', limit: 1);
    if (rows.isNotEmpty && rows.first['name'] != null) {
      return rows.first['name'] as String;
    }
    return 'School';
  }

  Future<void> _exportPdf() async {
    try {
      _showProgress('Generating PDF…');
      final schoolName = await _getSchoolName();
      final pdf = await _buildPdf(schoolName);
      final bytes = await pdf.save();

      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final file = File('${dir.path}/exam_registered_$stamp.pdf');
      await file.writeAsBytes(bytes);

      if (!mounted) return;
      Navigator.pop(context); // close progress

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Examination Registered Students',
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _printDocument() async {
    try {
      _showProgress('Preparing print…');
      final schoolName = await _getSchoolName();
      final pdf = await _buildPdf(schoolName);

      if (!mounted) return;
      Navigator.pop(context); // close progress

      await Printing.layoutPdf(
        onLayout: (_) async => pdf.save(),
        name: 'Exam Registered Students',
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print failed: $e')));
    }
  }

  Widget _statusBadge(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  void _showProgress(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text(message),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registered Students'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Print (A4)',
            onPressed: _filtered.isEmpty ? null : _printDocument,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export PDF',
            onPressed: _filtered.isEmpty ? null : _exportPdf,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter bar
          Container(
            color: Colors.indigo.withValues(alpha: 0.06),
            padding: EdgeInsets.all(ds.cardPadding),
            child: Column(
              children: [
                DropdownButtonFormField<ExternalExamination?>(
                  initialValue: _selectedExam,
                  decoration: const InputDecoration(
                    labelText: 'Filter by Examination',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.filter_list),
                  ),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('All Examinations')),
                    ..._examinations.map((e) => DropdownMenuItem(
                          value: e,
                          child: Text('${e.name} (${e.code})'),
                        )),
                  ],
                  onChanged: (v) {
                    setState(() => _selectedExam = v);
                    _loadStudents();
                  },
                ),
                SizedBox(height: ds.cardPadding * 0.75),
                DropdownButtonFormField<String?>(
                  key: ValueKey(_selectedSession),
                  initialValue: _selectedSession,
                  decoration: const InputDecoration(
                    labelText: 'Academic Session',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All Sessions')),
                    ..._sessions.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                  ],
                  onChanged: (v) {
                    setState(() => _selectedSession = v);
                    _loadStudents();
                  },
                ),
                SizedBox(height: ds.cardPadding * 0.75),
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search by name, admission no, class…',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => _searchCtrl.clear(),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),

          // Summary bar
          Container(
            color: Colors.indigo.withValues(alpha: 0.1),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.people, size: 16, color: Colors.indigo.shade700),
                const SizedBox(width: 6),
                Text(
                  '${_filtered.length} registered student(s)',
                  style: TextStyle(
                      fontSize: ds.subtitleFontSize,
                      color: Colors.indigo.shade700,
                      fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                if (_filtered.isNotEmpty) ...[
                  TextButton.icon(
                    onPressed: _printDocument,
                    icon: Icon(Icons.print_outlined,
                        size: 16, color: Colors.indigo.shade700),
                    label: Text('Print',
                        style: TextStyle(
                            fontSize: ds.subtitleFontSize,
                            color: Colors.indigo.shade700)),
                  ),
                  TextButton.icon(
                    onPressed: _exportPdf,
                    icon: Icon(Icons.picture_as_pdf_outlined,
                        size: 16, color: Colors.indigo.shade700),
                    label: Text('PDF',
                        style: TextStyle(
                            fontSize: ds.subtitleFontSize,
                            color: Colors.indigo.shade700)),
                  ),
                ],
              ],
            ),
          ),

          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_outline,
                                size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text(
                              'No students registered',
                              style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: ds.titleFontSize * 0.9),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadStudents,
                        child: ListView.separated(
                          padding: EdgeInsets.all(ds.cardPadding),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, _) =>
                              SizedBox(height: ds.cardPadding * 0.4),
                          itemBuilder: (_, i) {
                            final r = _filtered[i];
                            return Card(
                              elevation: 1.5,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              child: ListTile(
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: ds.cardPadding,
                                    vertical: ds.cardPadding * 0.3),
                                leading: CircleAvatar(
                                  backgroundColor:
                                      Colors.indigo.withValues(alpha: 0.12),
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.indigo.shade700),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        r.fullName,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: ds.titleFontSize * 0.82),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    SiblingMark(show: isSiblingPhone(r.parentPhone, _siblingPhones)),
                                    if (r.isStudentDeleted)
                                      _statusBadge('Deleted', Colors.red),
                                    if (r.isStudentDeactivated)
                                      _statusBadge('Inactive', Colors.orange),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${r.admissionNo ?? ''}  •  ${r.classArm}',
                                      style: TextStyle(
                                          fontSize: ds.subtitleFontSize,
                                          color: Colors.grey[600]),
                                    ),
                                    if (_selectedExam == null)
                                      Container(
                                        margin:
                                            const EdgeInsets.only(top: 3),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.indigo
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '${r.examinationName} (${r.examinationCode})',
                                          style: TextStyle(
                                              fontSize:
                                                  ds.subtitleFontSize * 0.88,
                                              color:
                                                  Colors.indigo.shade700),
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: Text(
                                  r.registrationDate,
                                  style: TextStyle(
                                      fontSize: ds.subtitleFontSize * 0.85,
                                      color: Colors.grey[500]),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
