// lib/screens/billing/debt_notification_hub_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/debt_notification_pdf_generator.dart';
import 'debt_notification_screen.dart';
import 'debt_notification_setup_screen.dart';

class DebtNotificationHubScreen extends StatefulWidget {
  const DebtNotificationHubScreen({super.key});

  @override
  State<DebtNotificationHubScreen> createState() =>
      _DebtNotificationHubScreenState();
}

class _DebtNotificationHubScreenState
    extends State<DebtNotificationHubScreen>
    with SingleTickerProviderStateMixin {
  final _db = DatabaseHelperWrapper();
  final _currency = NumberFormat('#,##0.00');
  late final TabController _tabController;

  // ── Applied settings ───────────────────────────────────────────────────────
  DebtNotificationSettings _settings = DebtNotificationSettings(
    letterType: 'current',
    copiesPerPage: 1,
    letterDate: DateTime.now(),
    signatoryName: '',
  );

  // ── Setup-tab local state (applied on "Apply & View Students") ────────────
  late String _setupLetterType;
  late int _setupCopiesPerPage;
  late DateTime _setupLetterDate;
  DateTime? _setupDeadline;
  // PTA fields
  DateTime? _setupPtaMeetingDate;
  late final TextEditingController _ptaTimeController;
  late final TextEditingController _ptaVenueController;
  // Mid-term fields
  DateTime? _setupMidTermStart;
  DateTime? _setupMidTermReturn;
  late final TextEditingController _signatoryController;
  late final TextEditingController _openingController;
  late final TextEditingController _closingController;

  // ── School / term ─────────────────────────────────────────────────────────
  String _term = '';
  String _session = '';
  String _prevTerm = '';
  String _prevSession = '';
  Map<String, dynamic>? _school;

  // ── Class / arm filters ───────────────────────────────────────────────────
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _arms = [];
  int? _selectedClassId;
  int? _selectedArmId;

  // ── Students ──────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _allStudents = [];
  List<Map<String, dynamic>> _filtered = [];
  final _searchController = TextEditingController();

  // ── State flags ───────────────────────────────────────────────────────────
  bool _loadingMeta = true;
  bool _loadingStudents = false;
  bool _exporting = false;
  bool _studentsLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _setupLetterType = _settings.letterType;
    _setupCopiesPerPage = _settings.copiesPerPage;
    _setupLetterDate = _settings.letterDate;
    _signatoryController =
        TextEditingController(text: _settings.signatoryName);
    _openingController =
        TextEditingController(text: _settings.customOpening);
    _closingController =
        TextEditingController(text: _settings.customClosing);
    _ptaTimeController = TextEditingController();
    _ptaVenueController = TextEditingController();
    _loadMeta();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _signatoryController.dispose();
    _openingController.dispose();
    _closingController.dispose();
    _ptaTimeController.dispose();
    _ptaVenueController.dispose();
    super.dispose();
  }

  // ── Meta ──────────────────────────────────────────────────────────────────

  Future<void> _loadMeta() async {
    setState(() => _loadingMeta = true);
    _term = await _db.getActiveTerm();
    final sessionData = await _db.getActiveSession();
    _session = sessionData?['sessionName'] ?? '';
    _school = await _db.getSchoolProfile();
    _classes = await _db.getClasses();
    _prevTerm = _computePrevTerm(_term);
    _prevSession = _computePrevSession(_term, _session);
    if (mounted) setState(() => _loadingMeta = false);
  }

  static String _computePrevTerm(String term) {
    if (term == 'Second Term') return 'First Term';
    if (term == 'Third Term') return 'Second Term';
    return 'Third Term'; // First Term → previous is Third Term of last session
  }

  static String _computePrevSession(String term, String session) {
    if (term != 'First Term') return session;
    final parts = session.split('/');
    if (parts.length == 2) {
      final start = int.tryParse(parts[0].trim());
      final end = int.tryParse(parts[1].trim());
      if (start != null && end != null) {
        return '${start - 1}/${end - 1}';
      }
    }
    return session;
  }

  // ── Apply setup ───────────────────────────────────────────────────────────

  Future<void> _applySetup() async {
    final newSettings = DebtNotificationSettings(
      letterType: _setupLetterType,
      copiesPerPage: _setupCopiesPerPage,
      letterDate: _setupLetterDate,
      signatoryName: _signatoryController.text.trim(),
      customOpening: _openingController.text.trim(),
      customClosing: _closingController.text.trim(),
      paymentDeadline: _setupDeadline,
      ptaMeetingDate: _setupPtaMeetingDate,
      ptaMeetingTime: _ptaTimeController.text.trim(),
      ptaVenue: _ptaVenueController.text.trim(),
      midTermStartDate: _setupMidTermStart,
      midTermReturnDate: _setupMidTermReturn,
    );
    final typeChanged = newSettings.letterType != _settings.letterType;
    setState(() {
      _settings = newSettings;
      if (typeChanged) {
        _allStudents = [];
        _filtered = [];
        _studentsLoaded = false;
      }
    });
    _tabController.animateTo(1);
    await _loadStudents();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _setupLetterDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _setupLetterDate = picked);
  }

  Future<void> _pickPtaMeetingDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _setupPtaMeetingDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _setupPtaMeetingDate = picked);
  }

  Future<void> _pickMidTermStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _setupMidTermStart ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _setupMidTermStart = picked);
  }

  Future<void> _pickMidTermReturn() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _setupMidTermReturn ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _setupMidTermReturn = picked);
  }

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _setupDeadline ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _setupDeadline = picked);
  }

  // ── Filters ───────────────────────────────────────────────────────────────

  Future<void> _onClassChanged(int? classId) async {
    setState(() {
      _selectedClassId = classId;
      _selectedArmId = null;
      _arms = [];
      _allStudents = [];
      _filtered = [];
      _studentsLoaded = false;
    });
    if (classId != null) {
      final arms = await _db.getArmsByClass(classId);
      if (mounted) setState(() => _arms = arms);
    }
    await _loadStudents();
  }

  Future<void> _onArmChanged(int? armId) async {
    setState(() {
      _selectedArmId = armId;
      _allStudents = [];
      _filtered = [];
      _studentsLoaded = false;
    });
    await _loadStudents();
  }

  // ── Load students ─────────────────────────────────────────────────────────

  Future<void> _loadStudents() async {
    if (_loadingMeta) return;
    setState(() => _loadingStudents = true);

    try {
      List<Map<String, dynamic>> students = [];

      if (_settings.letterType == 'current' || _settings.letterType == 'zero') {
        final classesToQuery = _selectedClassId != null
            ? _classes
                .where((c) => c['id'] == _selectedClassId)
                .toList()
            : _classes;

        for (final cls in classesToQuery) {
          final classId = (cls['id'] ?? 0) as int;
          if (classId == 0) continue;

          final rows = await _db.getDebtorsList(
            classId: classId,
            term: _term,
            session: _session,
            minPercentagePaid: 0,
          );

          for (final row in rows) {
            final paid = ((row['totalPaid'] ?? 0) as num).toDouble();
            // For zero-payment type, only include students who paid nothing
            if (_settings.letterType == 'zero' && paid > 0) continue;
            students.add({
              ...Map<String, dynamic>.from(row),
              'studentName':
                  '${row['surname'] ?? ''} ${row['firstName'] ?? ''}'
                      .trim(),
              'totalBills': ((row['totalBill'] ?? 0) as num).toDouble(),
              'totalPaid': paid,
              'outstanding':
                  ((row['outstanding'] ?? 0) as num).toDouble(),
            });
          }
        }

        // Arm filter — getDebtorsList has no armId param, so filter post-load
        if (_selectedArmId != null && _arms.isNotEmpty) {
          final arm = _arms.firstWhere(
            (a) => a['id'] == _selectedArmId,
            orElse: () => <String, dynamic>{},
          );
          final armName = (arm['name'] ?? '').toString();
          if (armName.isNotEmpty) {
            students = students
                .where((s) =>
                    (s['armName'] ?? '').toString() == armName)
                .toList();
          }
        }
      } else if (_settings.letterType == 'pta') {
        // All active students
        var rows = await _db.getActiveStudentsWithDetails();
        if (_selectedClassId != null) {
          rows = rows
              .where((r) => r['classId'] == _selectedClassId)
              .toList();
        }
        if (_selectedArmId != null && _arms.isNotEmpty) {
          rows = rows
              .where((r) => r['armId'] == _selectedArmId)
              .toList();
        }
        for (final row in rows) {
          students.add({
            ...Map<String, dynamic>.from(row),
            'studentName':
                '${row['surname'] ?? ''} ${row['firstName'] ?? ''}'.trim(),
            'totalBills': 0.0,
            'totalPaid': 0.0,
            'outstanding': 0.0,
          });
        }
      } else if (_settings.letterType == 'midterm') {
        // Current term debtors (same query as 'current')
        final classesToQuery = _selectedClassId != null
            ? _classes.where((c) => c['id'] == _selectedClassId).toList()
            : _classes;

        for (final cls in classesToQuery) {
          final classId = (cls['id'] ?? 0) as int;
          if (classId == 0) continue;

          final rows = await _db.getDebtorsList(
            classId: classId,
            term: _term,
            session: _session,
            minPercentagePaid: 0,
          );

          for (final row in rows) {
            students.add({
              ...Map<String, dynamic>.from(row),
              'studentName':
                  '${row['surname'] ?? ''} ${row['firstName'] ?? ''}'.trim(),
              'totalBills': ((row['totalBill'] ?? 0) as num).toDouble(),
              'totalPaid': ((row['totalPaid'] ?? 0) as num).toDouble(),
              'outstanding': ((row['outstanding'] ?? 0) as num).toDouble(),
            });
          }
        }

        if (_selectedArmId != null && _arms.isNotEmpty) {
          final arm = _arms.firstWhere(
            (a) => a['id'] == _selectedArmId,
            orElse: () => <String, dynamic>{},
          );
          final armName = (arm['name'] ?? '').toString();
          if (armName.isNotEmpty) {
            students = students
                .where((s) => (s['armName'] ?? '').toString() == armName)
                .toList();
          }
        }
      } else {
        // Last-term debtors
        final rows = await _db.getLastTermDebtors(
          term: _term,
          session: _session,
          classId: _selectedClassId ?? 0,
          armId: _selectedArmId ?? 0,
        );

        for (final row in rows) {
          final prevBal =
              ((row['previousBalance'] ?? 0) as num).toDouble();
          final paid =
              ((row['totalPaidThisTerm'] ?? 0) as num).toDouble();
          final applied = paid >= prevBal ? prevBal : paid;
          final outstanding =
              (prevBal - applied).clamp(0.0, double.infinity);

          if (outstanding > 0.005) {
            students.add({
              ...Map<String, dynamic>.from(row),
              'studentName':
                  '${row['surname'] ?? ''} ${row['firstName'] ?? ''}'
                      .trim(),
              'totalBills': prevBal,
              'totalPaid': applied,
              'outstanding': outstanding,
            });
          }
        }
      }

      students.sort((a, b) {
        final c = (a['className'] ?? '')
            .toString()
            .compareTo((b['className'] ?? '').toString());
        if (c != 0) return c;
        return (a['studentName'] ?? '')
            .toString()
            .compareTo((b['studentName'] ?? '').toString());
      });

      _allStudents = students;
      _applySearch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error loading students: $e'),
              backgroundColor: Colors.red),
        );
      }
    }

    if (mounted) {
      setState(() {
        _loadingStudents = false;
        _studentsLoaded = true;
      });
    }
  }

  void _applySearch() {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) {
      _filtered = List.of(_allStudents);
    } else {
      _filtered = _allStudents.where((d) {
        final name =
            '${d['surname'] ?? ''} ${d['firstName'] ?? ''} ${d['otherName'] ?? ''}'
                .toLowerCase();
        final adm = (d['admissionNo'] ?? '').toString().toLowerCase();
        final cls =
            '${d['className'] ?? ''} ${d['armName'] ?? ''}'.toLowerCase();
        return name.contains(q) || adm.contains(q) || cls.contains(q);
      }).toList();
    }
  }

  // ── Export ────────────────────────────────────────────────────────────────

  Future<void> _exportAll({bool previewOnly = false}) async {
    if (_filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No students to export')),
      );
      return;
    }
    setState(() => _exporting = true);
    try {
      final result = await DebtNotificationPdfGenerator.generateBulk(
        schoolProfile: _school ?? {},
        students: _filtered,
        term: _settings.letterType == 'last' ? _prevTerm : _term,
        session: _settings.letterType == 'last' ? _prevSession : _session,
        letterDate: _settings.letterDate,
        signatoryName: _settings.signatoryName,
        customOpening: _settings.customOpening.isEmpty
            ? null
            : _settings.customOpening,
        customClosing: _settings.customClosing.isEmpty
            ? null
            : _settings.customClosing,
        paymentDeadline: _settings.paymentDeadline,
        twoUp: _settings.copiesPerPage == 2,
        threeUp: _settings.copiesPerPage == 3,
        isLastTerm: _settings.letterType == 'last',
        isZeroPayment: _settings.letterType == 'zero',
        isPta: _settings.letterType == 'pta',
        isMidTerm: _settings.letterType == 'midterm',
        ptaMeetingDate: _settings.ptaMeetingDate,
        ptaMeetingTime: _settings.ptaMeetingTime,
        ptaVenue: _settings.ptaVenue,
        midTermStartDate: _settings.midTermStartDate,
        midTermReturnDate: _settings.midTermReturnDate,
        saveToFile: !previewOnly,
      );
      if (!mounted) return;
      if (previewOnly) {
        await Printing.layoutPdf(
          onLayout: (_) async => result.bytes,
          name: 'DebtNotification_All',
        );
      } else if (result.filePath != null) {
        await Share.shareXFiles(
          [XFile(result.filePath!)],
          subject: 'Debt Notification Letters — $_term, $_session',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Export failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _openSingleStudent(Map<String, dynamic> s) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DebtNotificationScreen(
          schoolProfile: _school ?? {},
          studentName: (s['studentName'] ?? '').toString(),
          admissionNo: (s['admissionNo'] ?? '').toString(),
          className:
              '${s['className'] ?? ''} ${s['armName'] ?? ''}'.trim(),
          term: _settings.letterType == 'last' ? _prevTerm : _term,
          session: _settings.letterType == 'last' ? _prevSession : _session,
          totalBills: (s['totalBills'] as num).toDouble(),
          totalPaid: (s['totalPaid'] as num).toDouble(),
          outstanding: (s['outstanding'] as num).toDouble(),
          initialDate: _settings.letterDate,
          initialSignatory: _settings.signatoryName,
          initialOpening: _settings.customOpening,
          initialClosing: _settings.customClosing,
          initialDeadline: _settings.paymentDeadline,
          isLastTerm: _settings.letterType == 'last',
          isZeroPayment: _settings.letterType == 'zero',
          isPta: _settings.letterType == 'pta',
          isMidTerm: _settings.letterType == 'midterm',
          ptaMeetingDate: _settings.ptaMeetingDate,
          ptaMeetingTime: _settings.ptaMeetingTime,
          ptaVenue: _settings.ptaVenue,
          midTermStartDate: _settings.midTermStartDate,
          midTermReturnDate: _settings.midTermReturnDate,
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loadingMeta) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Debt Notification'),
          backgroundColor: Colors.red.shade700,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debt Notification'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        actions: [
          if (!_exporting && _studentsLoaded && _filtered.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.visibility_outlined),
              tooltip: 'Preview All',
              onPressed: () => _exportAll(previewOnly: true),
            ),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Export All PDF',
              onPressed: () => _exportAll(),
            ),
          ],
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.settings_outlined), text: 'Setup'),
            Tab(icon: Icon(Icons.people_outline), text: 'Students'),
          ],
        ),
      ),
      body: _exporting
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Generating PDF…'),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _setupTab(),
                _studentsTab(),
              ],
            ),
    );
  }

  // ── Setup tab ─────────────────────────────────────────────────────────────

  Widget _setupTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // (a) Letter component
          _sectionCard(
            label: '(a)  Letter Component',
            child: Column(
              children: [
                _typeOption(
                  value: 'current',
                  title: 'Current Term Debtors',
                  subtitle:
                      'Students with outstanding balance in the active term',
                  icon: Icons.receipt_long_outlined,
                ),
                const SizedBox(height: 10),
                _typeOption(
                  value: 'last',
                  title: 'Last Term Debtors',
                  subtitle:
                      'Students who carried unpaid debt from a previous term',
                  icon: Icons.history_edu_outlined,
                ),
                const SizedBox(height: 10),
                _typeOption(
                  value: 'zero',
                  title: 'Zero Payment (Nothing Paid)',
                  subtitle:
                      'Students who have not made any payment at all this term',
                  icon: Icons.money_off_outlined,
                ),
                const SizedBox(height: 10),
                _typeOption(
                  value: 'pta',
                  title: 'PTA Meeting Notification',
                  subtitle: 'Invite all parents to a PTA meeting',
                  icon: Icons.groups_outlined,
                ),
                const SizedBox(height: 10),
                _typeOption(
                  value: 'midterm',
                  title: 'Mid-Term Holiday Notice',
                  subtitle:
                      'Notify parents of mid-term dates and outstanding balance',
                  icon: Icons.event_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // PTA meeting details (shown only when 'pta' is selected)
          if (_setupLetterType == 'pta') ...[
            _sectionCard(
              label: 'PTA Meeting Details',
              child: Column(
                children: [
                  // Meeting date
                  InkWell(
                    onTap: _pickPtaMeetingDate,
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Meeting Date',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today, size: 18),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                      child: Text(
                        _setupPtaMeetingDate != null
                            ? DateFormat('EEEE, d MMMM yyyy')
                                .format(_setupPtaMeetingDate!)
                            : 'Tap to set meeting date',
                        style: TextStyle(
                          fontSize: 15,
                          color: _setupPtaMeetingDate != null
                              ? Colors.black87
                              : Colors.grey.shade500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Meeting time
                  TextField(
                    controller: _ptaTimeController,
                    decoration: const InputDecoration(
                      labelText: 'Meeting Time',
                      hintText: 'e.g. 10:00 AM',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.access_time, size: 18),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Venue
                  TextField(
                    controller: _ptaVenueController,
                    decoration: const InputDecoration(
                      labelText: 'Venue',
                      hintText: 'e.g. School Hall (defaults to school name)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.location_on_outlined, size: 18),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Mid-term dates (shown only when 'midterm' is selected)
          if (_setupLetterType == 'midterm') ...[
            _sectionCard(
              label: 'Mid-Term Holiday Dates',
              child: Column(
                children: [
                  // Break start
                  InkWell(
                    onTap: _pickMidTermStart,
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Break Starts',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today, size: 18),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                      child: Text(
                        _setupMidTermStart != null
                            ? DateFormat('d MMMM, yyyy')
                                .format(_setupMidTermStart!)
                            : 'Tap to set break start date',
                        style: TextStyle(
                          fontSize: 15,
                          color: _setupMidTermStart != null
                              ? Colors.black87
                              : Colors.grey.shade500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Return date
                  InkWell(
                    onTap: _pickMidTermReturn,
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Students Resume On',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today, size: 18),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                      child: Text(
                        _setupMidTermReturn != null
                            ? DateFormat('d MMMM, yyyy')
                                .format(_setupMidTermReturn!)
                            : 'Tap to set return date',
                        style: TextStyle(
                          fontSize: 15,
                          color: _setupMidTermReturn != null
                              ? Colors.black87
                              : Colors.grey.shade500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // (b) Letters per page
          _sectionCard(
            label: '(b)  Letters Per Page',
            child: Row(
              children: [
                _pageOption(
                  value: 1,
                  label: '1 per page',
                  sublabel: 'Full-size letter',
                  icon: Icons.article_outlined,
                ),
                const SizedBox(width: 8),
                _pageOption(
                  value: 2,
                  label: '2 per page',
                  sublabel: 'Saves paper',
                  icon: Icons.content_copy,
                  badge: 'RECOMMENDED',
                ),
                const SizedBox(width: 8),
                _pageOption(
                  value: 3,
                  label: '3 per page',
                  sublabel: 'Max saving',
                  icon: Icons.filter_none,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // (c) Letter date
          _sectionCard(
            label: '(c)  Letter Date',
            child: InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today, size: 18),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
                child: Text(
                  DateFormat('d MMMM, yyyy').format(_setupLetterDate),
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // (d) Payment deadline
          _sectionCard(
            label: '(d)  Payment Deadline (optional)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'If set, the letter will say "on or before [date]".',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _pickDeadline,
                        borderRadius: BorderRadius.circular(8),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.event, size: 18),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
                          ),
                          child: Text(
                            _setupDeadline != null
                                ? DateFormat('d MMMM, yyyy')
                                    .format(_setupDeadline!)
                                : 'No deadline — tap to set',
                            style: TextStyle(
                              fontSize: 15,
                              color: _setupDeadline != null
                                  ? Colors.black87
                                  : Colors.grey.shade500,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_setupDeadline != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Remove deadline',
                        onPressed: () =>
                            setState(() => _setupDeadline = null),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Signatory
          _sectionCard(
            label: 'Signatory Name (optional)',
            child: TextField(
              controller: _signatoryController,
              decoration: const InputDecoration(
                hintText: 'e.g. Mr. John Eze  (defaults to school name)',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // (d) Opening paragraph
          _sectionCard(
            label: '(d)  Opening Paragraph (optional)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Leave blank to use the default opening text.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _openingController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText:
                        'e.g. We write to bring to your notice that your child/ward…',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // (e) Closing paragraph
          _sectionCard(
            label: '(e)  Closing Paragraph (optional)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Leave blank to use the default closing text.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _closingController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText:
                        'e.g. Kindly make payment of the outstanding amount promptly…',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Apply button
          ElevatedButton.icon(
            onPressed: _applySetup,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Apply & View Students'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              textStyle: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.black87)),
        const SizedBox(height: 10),
        child,
      ],
    );
  }

  Widget _typeOption({
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final selected = _setupLetterType == value;
    return GestureDetector(
      onTap: () => setState(() => _setupLetterType = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? Colors.red.shade50 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? Colors.red.shade700 : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: selected
                    ? Colors.red.shade700
                    : Colors.grey.shade500,
                size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: selected
                              ? Colors.red.shade800
                              : Colors.black87)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle,
                  color: Colors.red.shade700, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _pageOption({
    required int value,
    required String label,
    required String sublabel,
    required IconData icon,
    String? badge,
  }) {
    final selected = _setupCopiesPerPage == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _setupCopiesPerPage = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.indigo : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? Colors.indigo : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 30,
                  color:
                      selected ? Colors.white : Colors.grey.shade600),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: selected ? Colors.white : Colors.black87)),
              Text(sublabel,
                  style: TextStyle(
                      fontSize: 11,
                      color: selected
                          ? Colors.white70
                          : Colors.grey.shade500)),
              if (badge != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white24
                        : Colors.green.shade600,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(badge,
                      style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Students tab ──────────────────────────────────────────────────────────

  Widget _studentsTab() {
    return Column(
      children: [
        _filterBar(),
        Expanded(child: _studentList()),
      ],
    );
  }

  Widget _filterBar() {
    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  key: ValueKey('cls_$_selectedClassId'),
                  initialValue: _selectedClassId,
                  decoration: InputDecoration(
                    labelText: 'Class',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('All Classes')),
                    ..._classes.map((c) => DropdownMenuItem(
                          value: c['id'] as int,
                          child: Text(c['name'] as String),
                        )),
                  ],
                  onChanged: _onClassChanged,
                ),
              ),
              if (_arms.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    key: ValueKey('arm_$_selectedArmId'),
                    initialValue: _selectedArmId,
                    decoration: InputDecoration(
                      labelText: 'Arm',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('All Arms')),
                      ..._arms.map((a) => DropdownMenuItem(
                            value: a['id'] as int,
                            child: Text(a['name'] as String),
                          )),
                    ],
                    onChanged: _onArmChanged,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by name, admission no. or class…',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        setState(_applySearch);
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              isDense: true,
            ),
            onChanged: (_) => setState(_applySearch),
          ),
        ],
      ),
    );
  }

  Widget _studentList() {
    if (_loadingStudents) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_studentsLoaded) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mail_outline,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Tap "Apply & View Students" on the Setup tab\nto load debtors.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _loadStudents,
              icon: const Icon(Icons.refresh),
              label: const Text('Load Now'),
            ),
          ],
        ),
      );
    }

    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline,
                size: 64, color: Colors.green.shade300),
            const SizedBox(height: 12),
            Text(
              _allStudents.isEmpty
                  ? 'No outstanding balances found'
                  : 'No students match your search',
              style: TextStyle(
                  fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    final pageCount = _settings.copiesPerPage == 3
        ? ((_filtered.length / 3).ceil())
        : _settings.copiesPerPage == 2
            ? ((_filtered.length / 2).ceil())
            : _filtered.length;

    return Column(
      children: [
        // Count + export bar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          color: Colors.red.shade50,
          child: Row(
            children: [
              Icon(Icons.people_outline,
                  size: 16, color: Colors.red.shade700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${_filtered.length} student${_filtered.length == 1 ? '' : 's'}  ·  '
                  'PDF: $pageCount page${pageCount == 1 ? '' : 's'}',
                  style: TextStyle(
                      fontSize: 12, color: Colors.red.shade800),
                ),
              ),
              TextButton.icon(
                onPressed:
                    _exporting ? null : () => _exportAll(previewOnly: true),
                icon: const Icon(Icons.visibility_outlined, size: 15),
                label:
                    const Text('Preview', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.indigo,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4)),
              ),
              TextButton.icon(
                onPressed: _exporting ? null : () => _exportAll(),
                icon: const Icon(Icons.picture_as_pdf, size: 15),
                label: const Text('Export All',
                    style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4)),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView.separated(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _filtered.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (_, i) => _studentCard(_filtered[i]),
          ),
        ),
      ],
    );
  }

  Widget _studentCard(Map<String, dynamic> s) {
    final surname = (s['surname'] ?? '').toString();
    final firstName = (s['firstName'] ?? '').toString();
    final className =
        '${s['className'] ?? ''} ${s['armName'] ?? ''}'.trim();
    final admNo = (s['admissionNo'] ?? '').toString();
    final outstanding = (s['outstanding'] as num).toDouble();

    return Card(
      elevation: 1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openSingleStudent(s),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.red.shade100,
                child: Text(
                  surname.isNotEmpty ? surname[0].toUpperCase() : '?',
                  style: TextStyle(
                      color: Colors.red.shade800,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$surname $firstName',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
                    Text('$className  ·  $admNo',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600)),
                  ],
                ),
              ),
              if (outstanding > 0) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'N${_currency.format(outstanding)}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700),
                    ),
                    Text('outstanding',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500)),
                  ],
                ),
                const SizedBox(width: 6),
              ],
              IconButton(
                icon: Icon(Icons.picture_as_pdf,
                    color: Colors.red.shade400, size: 20),
                tooltip: 'Export letter for this student',
                onPressed: () => _openSingleStudent(s),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
