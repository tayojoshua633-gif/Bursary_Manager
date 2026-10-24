// lib/screens/students/admission_register_screen.dart

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database_helper_wrapper.dart';
import '../../models/student.dart';
import '../../utils/admission_register_pdf_generator.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/pdf_export_helper.dart';
import '../../widgets/student_quick_actions_panel.dart';
import '../../widgets/term_session_filter.dart';
import 'student_details_screen.dart';

/// Admission Register: every student ever admitted (active and left), filtered
/// by the session/term of admission (default: all sessions and terms), with
/// print to the document printer and PDF export.
///
/// A student's admission term/session is the term of their earliest bill
/// carrying a registration fee — the same rule View New Students uses.
class AdmissionRegisterScreen extends StatefulWidget {
  const AdmissionRegisterScreen({super.key});

  @override
  State<AdmissionRegisterScreen> createState() => _AdmissionRegisterScreenState();
}

class _AdmissionRegisterScreenState extends State<AdmissionRegisterScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _verticalScroll = ScrollController();
  final ScrollController _horizontalScroll = ScrollController();

  List<Map<String, dynamic>> _register = [];
  List<Map<String, dynamic>> _filtered = [];
  List<String> _sessions = [];
  // null = All Sessions / All Terms (the default)
  String? _session;
  String? _term;
  String _searchQuery = '';
  bool _loading = true;
  bool _busy = false;
  Map<String, dynamic> _currentUser = {};

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadRegister();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _verticalScroll.dispose();
    _horizontalScroll.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUser = {
      'id': prefs.getInt('userId') ?? 0,
      'userType': prefs.getString('userType') ?? 'bursar',
      'username': prefs.getString('username') ?? 'User',
    };
    if (mounted) setState(() => _currentUser = currentUser);
  }

  Future<void> _loadRegister() async {
    setState(() => _loading = true);
    try {
      final rows = (await _db.getAdmissionRegister())
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
      // Oldest admission first; undated records are treated as oldest (as on
      // New Students), then admission number, then registration order.
      rows.sort((a, b) {
        final aDate = (a['dateOfAdmission'] ?? '').toString();
        final bDate = (b['dateOfAdmission'] ?? '').toString();
        if (aDate.isNotEmpty != bDate.isNotEmpty) return aDate.isNotEmpty ? 1 : -1;
        final dateComp = aDate.compareTo(bDate);
        if (dateComp != 0) return dateComp;
        final admComp = (a['admissionNo'] ?? '').toString().compareTo((b['admissionNo'] ?? '').toString());
        if (admComp != 0) return admComp;
        return (a['id'] as int? ?? 0).compareTo(b['id'] as int? ?? 0);
      });

      final sessionNames = TermSessionFilter.sessionNames(await _db.getAllSessions(), _session);
      // Include admission sessions that no longer exist in the sessions table.
      final allSessions = {
        ...sessionNames,
        ...rows.map((r) => (r['admissionSession'] ?? '').toString()).where((s) => s.isNotEmpty),
      }.toList()
        ..sort((a, b) => b.compareTo(a));

      if (!mounted) return;
      setState(() {
        _register = rows;
        _sessions = allSessions;
        _loading = false;
      });
      _applyFilters();
    } catch (e) {
      debugPrint('Error loading admission register: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading admission register: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _applyFilters() {
    final query = _searchQuery.toLowerCase();
    setState(() {
      _filtered = _register.where((s) {
        if (_session != null && s['admissionSession'] != _session) return false;
        if (_term != null && s['admissionTerm'] != _term) return false;
        if (query.isEmpty) return true;
        return AdmissionRegisterPdfGenerator.studentName(s).toLowerCase().contains(query) ||
            (s['admissionNo'] ?? '').toString().toLowerCase().contains(query) ||
            (s['parentName'] ?? '').toString().toLowerCase().contains(query) ||
            AdmissionRegisterPdfGenerator.admittedClass(s).toLowerCase().contains(query);
      }).toList();
    });
  }

  void _onSessionChanged(String? session) {
    _session = session;
    _applyFilters();
  }

  void _onTermChanged(String? term) {
    _term = term;
    _applyFilters();
  }

  bool _ensureRows() {
    if (_filtered.isNotEmpty) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No students in the register for this selection')),
    );
    return false;
  }

  Future<void> _print() async {
    if (!_ensureRows()) return;
    setState(() => _busy = true);
    try {
      final schoolProfile = await _db.getSchoolProfile();
      final pdf = AdmissionRegisterPdfGenerator.buildDocument(
        students: _filtered,
        session: _session,
        term: _term,
        schoolProfile: schoolProfile ?? {},
      );
      final bytes = await pdf.save();
      if (mounted) setState(() => _busy = false);
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Admission_Register.pdf',
        format: AdmissionRegisterPdfGenerator.pageFormat.landscape,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _exportPdf() async {
    if (!_ensureRows()) return;
    final students = List<Map<String, dynamic>>.from(_filtered);
    final session = _session;
    final term = _term;
    final label = AdmissionRegisterPdfGenerator.filterLabel(session, term);
    await PdfExportHelper.exportPdf(
      context,
      generate: ({required bool saveToDownloads}) async {
        final schoolProfile = await _db.getSchoolProfile();
        return AdmissionRegisterPdfGenerator.generatePdf(
          students: students,
          session: session,
          term: term,
          schoolProfile: schoolProfile ?? {},
          saveToDownloads: saveToDownloads,
        );
      },
      shareSubject: 'Admission Register - $label',
      successMessage: 'Admission register ($label, ${students.length} students) exported.',
    );
  }

  void _openStudent(Map<String, dynamic> studentData) {
    NavigationHelper.pushWithSidebar(
      context,
      page: StudentDetailsScreen(student: Student.fromMap(studentData)),
      currentUser: _currentUser,
      pageId: 'student_management/admission_register',
    ).then((value) {
      if (value == true) _loadRegister();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admission Register'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _busy || _loading ? null : _print,
            tooltip: 'Print (Document Printer)',
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _busy || _loading ? null : _exportPdf,
            tooltip: 'Export PDF',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadRegister,
            tooltip: 'Refresh',
          ),
        ],
      ),
      endDrawer: StudentQuickAccess.buildEndDrawer(
        context,
        current: StudentQuickAction.admissionRegister,
        onReturn: _loadRegister,
      ),
      body: StudentQuickAccess.wrapBody(
        context,
        current: StudentQuickAction.admissionRegister,
        onReturn: _loadRegister,
        body: Column(
          children: [
            _buildHeader(),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _register.isEmpty
                      ? _buildEmptyState('No Students Admitted Yet', 'Registered students will appear here.')
                      : _filtered.isEmpty
                          ? _buildEmptyState('No Results', 'No student matches this session/term or search.')
                          : _buildTable(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final male = _filtered.where((s) => s['gender'] == 'Male').length;
    final female = _filtered.where((s) => s['gender'] == 'Female').length;
    final active = _filtered.where((s) => s['isActive'] != 0).length;
    final undated = _register.where((s) => s['admissionSession'] == null).length;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.teal.shade50, Colors.blue.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: Colors.grey.shade300, blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.shade600,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.menu_book, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admission Register',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal.shade900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AdmissionRegisterPdfGenerator.filterLabel(_session, _term),
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TermSessionFilter(
            sessions: _sessions,
            session: _session,
            term: _term,
            allowAll: true,
            onSessionChanged: _onSessionChanged,
            onTermChanged: _onTermChanged,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (value) {
              _searchQuery = value;
              _applyFilters();
            },
            decoration: InputDecoration(
              hintText: 'Search by name, admission no, parent or class...',
              prefixIcon: const Icon(Icons.search, color: Colors.teal),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        _searchQuery = '';
                        _applyFilters();
                      },
                    )
                  : null,
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _statChip('Total', _filtered.length, Colors.teal),
              _statChip('Male', male, Colors.blue),
              _statChip('Female', female, Colors.pink),
              _statChip('Active', active, Colors.green),
              _statChip('Left', _filtered.length - active, Colors.red),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _busy || _loading ? null : _print,
                icon: const Icon(Icons.print, size: 18),
                label: const Text('Print'),
              ),
              OutlinedButton.icon(
                onPressed: _busy || _loading ? null : _exportPdf,
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('Export PDF'),
              ),
            ],
          ),
          if (undated > 0 && (_session != null || _term != null)) ...[
            const SizedBox(height: 8),
            Text(
              '$undated student(s) have no registration-fee bill, so their admission term is unknown; '
              'they only appear under All Sessions & All Terms.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statChip(String label, int count, MaterialColor color) {
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: color.shade50,
      side: BorderSide(color: color.shade200),
      label: Text(
        '$label: $count',
        style: TextStyle(fontWeight: FontWeight.w600, color: color.shade800),
      ),
    );
  }

  Widget _buildTable() {
    const columns = [
      'S/N',
      'Adm. No',
      'Student Name',
      'Gender',
      'Date of Birth',
      'Date of Adm.',
      'Term/Session of Adm.',
      'Class Admitted',
      'Parent/Guardian',
      'Phone',
      'Address',
      'State/LGA',
      'Status',
    ];

    // Explicit controllers: on desktop a controller-less Scrollbar has no
    // PrimaryScrollController attached, so its thumb never moves or drags.
    // Both bars wrap the viewport so they stay at its edges; the inner one
    // listens to the nested horizontal scroll view (depth 1).
    return Scrollbar(
      controller: _verticalScroll,
      thumbVisibility: true,
      child: Scrollbar(
        controller: _horizontalScroll,
        thumbVisibility: true,
        notificationPredicate: (notification) => notification.depth == 1,
        child: SingleChildScrollView(
          controller: _verticalScroll,
          child: SingleChildScrollView(
          controller: _horizontalScroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: DataTable(
            showCheckboxColumn: false,
            headingRowColor: WidgetStatePropertyAll(Colors.teal.shade50),
            columnSpacing: 20,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 56,
            columns: columns
                .map((c) => DataColumn(label: Text(c, style: const TextStyle(fontWeight: FontWeight.bold))))
                .toList(),
            rows: _filtered.asMap().entries.map((entry) {
              final s = entry.value;
              final left = s['isActive'] == 0;
              return DataRow(
                onSelectChanged: (_) => _openStudent(s),
                cells: [
                  DataCell(Text('${entry.key + 1}')),
                  DataCell(Text((s['admissionNo'] ?? '').toString())),
                  DataCell(Text(AdmissionRegisterPdfGenerator.studentName(s))),
                  DataCell(Text((s['gender'] ?? '').toString())),
                  DataCell(Text(AdmissionRegisterPdfGenerator.formatDate(s['dob'] as String?))),
                  DataCell(Text(AdmissionRegisterPdfGenerator.formatDate(s['dateOfAdmission'] as String?))),
                  DataCell(Text(AdmissionRegisterPdfGenerator.admissionPeriod(s))),
                  DataCell(Text(AdmissionRegisterPdfGenerator.admittedClass(s))),
                  DataCell(Text((s['parentName'] ?? '').toString())),
                  DataCell(Text((s['parentPhone'] ?? '').toString())),
                  DataCell(ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text((s['address'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                  )),
                  DataCell(Text(AdmissionRegisterPdfGenerator.stateLga(s))),
                  DataCell(ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      AdmissionRegisterPdfGenerator.status(s),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: left ? Colors.red.shade700 : Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )),
                ],
              );
            }).toList(),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildEmptyState(String title, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}
