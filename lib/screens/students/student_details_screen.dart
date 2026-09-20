// lib/screens/students/student_details_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../main.dart' show appRouteObserver;
import '../../models/student.dart';
import '../../data/database_helper_wrapper.dart';
import '../payments/payment_record_screen.dart';
import '../payments/payment_history_screen.dart';
import '../billing/bill_generate_screen.dart';
import 'student_edit_screen.dart';
import 'siblings_information_screen.dart';
import '../../utils/permission_helper.dart';
import '../../utils/display_settings_helper.dart';
import '../../utils/navigation_helper.dart';
import '../../widgets/sibling_mark.dart';
import '../../utils/payment_date_time_formatter.dart';
import '../../utils/age_helper.dart';
import '../../utils/student_bill_actions.dart';

class StudentDetailsScreen extends StatefulWidget {
  final Student student;

  const StudentDetailsScreen({super.key, required this.student});

  @override
  State<StudentDetailsScreen> createState() => _StudentDetailsScreenState();
}

class _StudentDetailsScreenState extends State<StudentDetailsScreen> with RouteAware {
  late Student current;
  bool _loading = true;
  bool _canManageStudents = false;
  Map<String, dynamic>? _currentUser;
  List<Map<String, dynamic>> _siblings = [];

  String? _parentPhone2;

  // Bill data
  String _activeTerm = "";
  String _activeSession = "";
  double _previousBalance = 0;
  double _currentTermBill = 0;
  double _grandTotal = 0;
  double _totalPaid = 0;
  double _outstanding = 0;
  List<Map<String, dynamic>> _billItems = [];
  List<Map<String, dynamic>> _payments = [];
  Map<String, dynamic>? _school;
  Map<String, dynamic>? _transportAllocation;
  final GlobalKey _billCardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _loadStudentWithClassArm();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    appRouteObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  /// Called when a page above this one is popped — refresh data every time.
  @override
  void didPopNext() {
    _loadStudentWithClassArm();
  }

  Future<void> _checkPermissions() async {
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

    if (mounted) {
      setState(() {
        _currentUser = currentUser;
        _canManageStudents = canManage;
      });
    }
  }

  // Load student with class and arm names using JOIN
  Future<void> _loadStudentWithClassArm() async {
    setState(() => _loading = true);

    try {
      final db = await DatabaseHelperWrapper().database;

      // Query with JOIN to get class and arm names
      final result = await db.rawQuery('''
        SELECT
          s.*,
          c.name as className,
          a.name as armName
        FROM students s
        LEFT JOIN classes c ON s.classId = c.id
        LEFT JOIN arms a ON s.armId = a.id
        WHERE s.id = ?
      ''', [widget.student.id]);

      if (result.isNotEmpty && mounted) {
        setState(() {
          current = Student.fromMap(result.first);
        });
        // Load bill data and siblings after loading student
        await _loadBillData();
        await _loadSiblings();
        await _loadParentPhone2();
        if (mounted) {
          setState(() => _loading = false);
        }
      } else {
        // Fallback to original student data
        setState(() {
          current = widget.student;
          _loading = false;
        });
      }
    } catch (e) {
      // Fallback to original student data on error
      if (mounted) {
        setState(() {
          current = widget.student;
          _loading = false;
        });
      }
    }
  }

  // Load student's bill data
  Future<void> _loadBillData() async {
    try {
      final dbHelper = DatabaseHelperWrapper();
      final db = await dbHelper.database;

      // Get current term and session
      _activeTerm = await dbHelper.getActiveTerm();
      final sessionData = await dbHelper.getActiveSession();
      _activeSession = sessionData?['sessionName'] ?? "";
      _school = await dbHelper.getSchoolProfile();

      if (_activeTerm.isEmpty || _activeSession.isEmpty) return;

      _transportAllocation = await dbHelper.getStudentTransportAllocation(
        current.id!,
        _activeTerm,
        _activeSession,
      );

      // Calculate previous balance
      _previousBalance = await dbHelper.computeOutstandingBeforeTerm(
        current.id!,
        term: _activeTerm,
        session: _activeSession,
      );

      // Get current term bill
      final bill = await dbHelper.getBillForStudent(current.id!, _activeTerm, _activeSession);

      _currentTermBill = 0;
      _grandTotal = _previousBalance;
      _billItems = [];

      if (bill != null) {
        final storedTotal = (bill['totalAmount'] as num?)?.toDouble() ?? 0.0;
        final storedPrevBalance = (bill['previousBalance'] as num?)?.toDouble() ?? 0.0;
        _currentTermBill = storedTotal - storedPrevBalance;
        _grandTotal = _previousBalance + _currentTermBill;

        // Load bill items from student_fee_breakdown table
        // Use NULLIF to treat empty strings as NULL, then COALESCE to get the best available name
        final items = await db.rawQuery('''
          SELECT sfb.id, sfb.billId, sfb.feeItemId, sfb.amount,
                 COALESCE(
                   NULLIF(TRIM(sfb.label), ''),
                   fi.name,
                   'Fee Item'
                 ) as feeName
          FROM student_fee_breakdown sfb
          LEFT JOIN fee_items fi ON sfb.feeItemId = fi.id
          WHERE sfb.billId = ?
          ORDER BY sfb.id ASC
        ''', [bill['id']]);
        _billItems = items.map((item) => Map<String, dynamic>.from(item)).toList();
      }

      // Get total payments for current term (sum)
      final paymentsSum = await db.rawQuery('''
        SELECT COALESCE(SUM(amount), 0) as totalPaid
        FROM payments
        WHERE studentId = ? AND term = ? AND session = ?
      ''', [current.id, _activeTerm, _activeSession]);

      _totalPaid = (paymentsSum.first['totalPaid'] as num?)?.toDouble() ?? 0.0;
      _outstanding = _grandTotal - _totalPaid;

      // Get payment details list
      final paymentsList = await db.rawQuery('''
        SELECT id, amount, method, note, paymentDate
        FROM payments
        WHERE studentId = ? AND term = ? AND session = ?
        ORDER BY paymentDate DESC
      ''', [current.id, _activeTerm, _activeSession]);

      _payments = paymentsList.map((p) => Map<String, dynamic>.from(p)).toList();

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading bill data: $e');
    }
  }

  StudentBillSnapshot _billSnapshot() => StudentBillSnapshot(
        studentId: current.id!,
        surname: current.surname,
        firstName: current.firstName,
        otherName: current.otherName,
        className: current.className,
        armName: current.armName,
        admissionNo: current.admissionNo,
        parentPhone: current.parentPhone,
        term: _activeTerm,
        session: _activeSession,
        previousBalance: _previousBalance,
        currentTermBill: _currentTermBill,
        grandTotal: _grandTotal,
        totalPaid: _totalPaid,
        outstanding: _outstanding,
        billItems: _billItems,
        payments: _payments,
        school: _school,
      );

  Future<void> _loadParentPhone2() async {
    try {
      if (current.parentPhone.isEmpty) return;
      final db = await DatabaseHelperWrapper().database;
      final result = await db.rawQuery('''
        SELECT phoneNumber2 FROM parents
        WHERE phoneNumber = ?
        LIMIT 1
      ''', [current.parentPhone]);
      if (result.isNotEmpty && mounted) {
        setState(() {
          _parentPhone2 = result.first['phoneNumber2'] as String?;
        });
      }
    } catch (e) {
      debugPrint('Error loading parent phone 2: $e');
    }
  }

  // Load siblings - students with same parent phone or linked to same parent record
  Future<void> _loadSiblings() async {
    try {
      final db = await DatabaseHelperWrapper().database;

      // Find other students with same parent phone number
      // This also covers cases where a parent record is linked to multiple students
      // (since parent linking is done via phone number matching)
      final siblings = await db.rawQuery('''
        SELECT
          s.id,
          s.surname,
          s.firstName,
          s.otherName,
          s.admissionNo,
          s.gender,
          s.photoPath,
          c.name as className,
          a.name as armName
        FROM students s
        LEFT JOIN classes c ON s.classId = c.id
        LEFT JOIN arms a ON s.armId = a.id
        WHERE s.id != ?
          AND s.isActive = 1
          AND s.parentPhone IS NOT NULL
          AND s.parentPhone != ''
          AND s.parentPhone = ?
        ORDER BY s.surname, s.firstName
      ''', [current.id, current.parentPhone]);

      if (mounted) {
        setState(() {
          _siblings = siblings;
        });
      }
    } catch (e) {
      debugPrint('Error loading siblings: $e');
    }
  }

  // Open siblings information screen
  void _openSiblingsInformation() {
    // Build sibling group including current student
    final List<Map<String, dynamic>> allSiblings = [
      {
        'id': current.id,
        'surname': current.surname,
        'firstName': current.firstName,
        'otherName': current.otherName,
        'gender': current.gender,
        'className': current.className,
        'armName': current.armName,
        'parentPhone': current.parentPhone,
        'parentName': current.parentName,
      },
      ..._siblings.map((s) => Map<String, dynamic>.from(s)),
    ];

    final siblingGroup = {
      'parentPhone': current.parentPhone,
      'parentName': current.parentName,
      'students': allSiblings,
    };

    NavigationHelper.pushWithSidebar(
      context,
      page: SiblingsInformationScreen(
        siblingGroup: siblingGroup,
        groupColor: Colors.purple,
      ),
      currentUser: _currentUser ?? {},
      pageId: 'student_management/students',
    ).then((_) {
      _loadStudentWithClassArm();
    });
  }

  Future<void> _dialPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open dialer')),
      );
    }
  }

  Future<void> _openEditStudent() async {
    final changed = await NavigationHelper.pushWithSidebar(
      context,
      page: StudentEditScreen(student: current),
      currentUser: _currentUser ?? {},
      pageId: 'student_management/students',
    );

    if (changed == true && mounted) {
      // Reload student with class/arm names
      _loadStudentWithClassArm();
    }
  }

  Future<void> _openGenerateBill() async {
    await NavigationHelper.pushWithSidebar(
      context,
      page: BillGenerateScreen(
        studentId: current.id!,
        studentName: "${current.surname} ${current.firstName}",
        isSibling: _siblings.isNotEmpty,
      ),
      currentUser: _currentUser ?? {},
      pageId: 'student_management/students',
    );
    if (mounted) _loadBillData();
  }

  Future<void> _openRecordPayment() async {
    await NavigationHelper.pushWithSidebar(
      context,
      page: PaymentRecordScreen(
        studentId: current.id!,
        studentName: "${current.surname} ${current.firstName}",
      ),
      currentUser: _currentUser ?? {},
      pageId: 'student_management/students',
    );
    if (mounted) _loadBillData();
  }

  Future<void> _openPaymentHistory() async {
    await NavigationHelper.pushWithSidebar(
      context,
      page: PaymentHistoryScreen(
        studentId: current.id!,
        studentName: "${current.surname} ${current.firstName}",
      ),
      currentUser: _currentUser ?? {},
      pageId: 'student_management/students',
    );
    if (mounted) _loadBillData();
  }

  /// Scrolls the details page to the "Bills & Payments" card.
  void _scrollToBillsAndPayments() {
    final billContext = _billCardKey.currentContext;
    if (billContext == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active term — there is no bill to show yet')),
      );
      return;
    }
    Scrollable.ensureVisible(
      billContext,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  Widget info(String label, String? value, DisplaySettings ds) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: ds.cardPadding * 0.3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: ds.cardPadding * 8,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: ds.bodyFontSize,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value ?? '-',
              style: TextStyle(fontSize: ds.bodyFontSize),
            ),
          ),
        ],
      ),
    );
  }

  Widget _phoneRow(String label, String phone, DisplaySettings ds) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: ds.cardPadding * 0.3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: ds.cardPadding * 8,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: ds.bodyFontSize,
              ),
            ),
          ),
          Expanded(
            child: Text(
              phone,
              style: TextStyle(fontSize: ds.bodyFontSize),
            ),
          ),
          IconButton(
            icon: Icon(Icons.call, color: Colors.green.shade600, size: ds.iconSize),
            tooltip: 'Dial',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _dialPhone(phone),
          ),
          SizedBox(width: ds.cardPadding * 0.5),
          IconButton(
            icon: Icon(Icons.copy, color: Colors.blue.shade600, size: ds.iconSize),
            tooltip: 'Copy',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: phone));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$label copied')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text("Student Details")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    ImageProvider? photo;
    if (current.photoPath != null &&
        current.photoPath!.isNotEmpty &&
        File(current.photoPath!).existsSync()) {
      photo = FileImage(File(current.photoPath!));
    }

    // Same "large screen" rule the sidebar uses (10+ inch displays); phones
    // keep the inline Quick Actions buttons instead.
    final showQuickAccessBar = MediaQuery.of(context).size.shortestSide >= 700;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                "${current.surname} ${current.firstName}",
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SiblingMark(show: _siblings.isNotEmpty),
          ],
        ),
        actions: [
          // EDIT BUTTON - Only shown if user has students_manage permission
          if (_canManageStudents)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: "Edit Student Information",
              onPressed: _openEditStudent,
            ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _buildDetailsBody(ds, photo, showQuickAccessBar),
          ),
          if (showQuickAccessBar) _buildQuickAccessBar(ds),
        ],
      ),
    );
  }

  Widget _buildDetailsBody(
    DisplaySettings ds,
    ImageProvider? photo,
    bool showQuickAccessBar,
  ) {
    return SingleChildScrollView(
        padding: EdgeInsets.all(ds.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [

            // PHOTO
            CircleAvatar(
              radius: ds.iconSize * 2.7,
              backgroundImage: photo,
              backgroundColor: Colors.blue.shade100,
              child: photo == null
                  ? Icon(
                      Icons.person,
                      size: ds.iconSize * 2.9,
                      color: Colors.blue.shade700,
                    )
                  : null,
            ),

            SizedBox(height: ds.cardPadding * 1.25),

            // FULL DETAILS CARD
            Card(
              elevation: 2,
              child: Padding(
                padding: EdgeInsets.all(ds.cardPadding),
                child: Column(
                  children: [
                    info("Admission No:", current.admissionNo, ds),
                    const Divider(),
                    info("Surname:", current.surname, ds),
                    info("First Name:", current.firstName, ds),
                    info("Other Name:", current.otherName, ds),
                    info("Gender:", current.gender, ds),
                    info("Date of Birth:", current.dob, ds),
                    info("Age:", AgeHelper.calculateAge(current.dob)?.toString(), ds),
                    info("Date of Admission:", current.dateOfAdmission ?? 'Not recorded', ds),
                    const Divider(),
                    info("Class:", current.className ?? 'Not Assigned', ds),
                    info("Arm:", current.armName ?? 'Not Assigned', ds),
                    const Divider(),
                    info("Address:", current.address, ds),
                    if (current.nationality != null && current.nationality!.isNotEmpty)
                      info("Nationality:", current.nationality!, ds),
                    if (current.stateOfOrigin != null && current.stateOfOrigin!.isNotEmpty)
                      info("State of Origin:", current.stateOfOrigin!, ds),
                    if (current.lga != null && current.lga!.isNotEmpty)
                      info("LGA:", current.lga!, ds),
                    const Divider(),
                    info("Parent Name:", current.parentName, ds),
                    _phoneRow("Parent Phone:", current.parentPhone, ds),
                    if (_parentPhone2 != null && _parentPhone2!.isNotEmpty)
                      _phoneRow("Parent Phone 2:", _parentPhone2!, ds),
                    info("Parent Email:", current.parentEmail, ds),
                    info("Parent Address:", current.parentAddress, ds),
                  ],
                ),
              ),
            ),

            SizedBox(height: ds.cardPadding * 1.25),

            // TRANSPORTATION CARD
            if (_transportAllocation != null)
              Card(
                elevation: 2,
                color: Colors.indigo.shade50,
                child: Padding(
                  padding: EdgeInsets.all(ds.cardPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.directions_bus, color: Colors.indigo.shade700, size: ds.iconSize),
                          SizedBox(width: ds.cardPadding * 0.5),
                          Text(
                            'Transportation',
                            style: TextStyle(
                              fontSize: ds.titleFontSize,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade900,
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      info("Route:", _transportAllocation!['routeName'] ?? 'Not Assigned', ds),
                      if ((_transportAllocation!['routeDescription'] ?? '').toString().isNotEmpty)
                        info("Description:", _transportAllocation!['routeDescription'], ds),
                      info(
                        "Fare Charged:",
                        '₦${NumberFormat('#,##0.00').format((_transportAllocation!['fareCharged'] as num?)?.toDouble() ?? 0)}',
                        ds,
                      ),
                      info("Term:", '$_activeTerm - $_activeSession', ds),
                    ],
                  ),
                ),
              ),
            if (_transportAllocation != null) SizedBox(height: ds.cardPadding * 1.25),

            // BILLS CARD
            if (_activeTerm.isNotEmpty)
              RepaintBoundary(
                key: _billCardKey,
                child: Card(
                  elevation: 2,
                  color: Colors.teal.shade50,
                  child: Padding(
                    padding: EdgeInsets.all(ds.cardPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header with print button
                        Row(
                          children: [
                            Icon(Icons.receipt_long, color: Colors.teal.shade700, size: ds.iconSize),
                            SizedBox(width: ds.cardPadding * 0.5),
                            Expanded(
                              child: Text(
                                'Bills & Payments',
                                style: TextStyle(
                                  fontSize: ds.titleFontSize,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal.shade900,
                                ),
                              ),
                            ),
                            // Send bill/payment SMS button
                            IconButton(
                              onPressed: () => StudentBillActions.sendSms(context, _billSnapshot()),
                              icon: Icon(Icons.sms_outlined, color: Colors.teal.shade700),
                              tooltip: 'Send Bill/Payment SMS',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            SizedBox(width: ds.cardPadding * 0.25),
                            // Previous term comparison button
                            IconButton(
                              onPressed: () => StudentBillActions.showTermComparison(context, _billSnapshot()),
                              icon: Icon(Icons.compare_arrows, color: Colors.teal.shade700),
                              tooltip: 'Previous Term Bills',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            SizedBox(width: ds.cardPadding * 0.25),
                            // Print button
                            IconButton(
                              onPressed: () => StudentBillActions.showPrintOptions(
                                context,
                                _billSnapshot(),
                                captureKey: _billCardKey,
                                currentUser: _currentUser,
                              ),
                              icon: Icon(Icons.print, color: Colors.teal.shade700),
                              tooltip: 'Print Statement',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            SizedBox(width: ds.cardPadding * 0.5),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: ds.cardPadding * 0.5,
                                vertical: ds.cardPadding * 0.25,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _activeTerm,
                                style: TextStyle(
                                  fontSize: ds.bodyFontSize * 0.85,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.teal.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(),

                        // BILL BREAKDOWN SECTION
                        if (_billItems.isNotEmpty) ...[
                          Row(
                            children: [
                              Icon(Icons.list_alt, size: ds.iconSize * 0.8, color: Colors.teal.shade600),
                              SizedBox(width: ds.cardPadding * 0.3),
                              Text(
                                'Bill Breakdown',
                                style: TextStyle(
                                  fontSize: ds.bodyFontSize,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.teal.shade800,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: ds.cardPadding * 0.3),
                          ..._billItems.map((item) => Padding(
                            padding: EdgeInsets.symmetric(vertical: ds.cardPadding * 0.15),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    item['feeName']?.toString() ?? 'Fee Item',
                                    style: TextStyle(fontSize: ds.bodyFontSize * 0.9),
                                  ),
                                ),
                                Text(
                                  '₦${NumberFormat('#,##0.00').format((item['amount'] as num?)?.toDouble() ?? 0)}',
                                  style: TextStyle(fontSize: ds.bodyFontSize * 0.9),
                                ),
                              ],
                            ),
                          )),
                          Divider(color: Colors.teal.shade200),
                        ],

                        // Summary section
                        _billRow('Current Term Bill', _currentTermBill, ds),
                        if (_previousBalance != 0)
                          _billRow(
                            _previousBalance > 0 ? 'Previous Balance' : 'Previous Credit',
                            _previousBalance.abs(),
                            ds,
                            color: _previousBalance > 0
                                ? Colors.orange.shade700
                                : Colors.green.shade700,
                          ),
                        Divider(color: Colors.teal.shade300, thickness: 1),
                        _billRow('Grand Total', _grandTotal, ds, bold: true, color: Colors.purple.shade700),
                        _billRow('Total Paid', _totalPaid, ds, color: Colors.green.shade700),
                        Divider(color: Colors.teal.shade300, thickness: 1.5),
                        _billRow(
                          _outstanding >= 0 ? 'Outstanding' : 'Overpayment',
                          _outstanding.abs(),
                          ds,
                          bold: true,
                          color: _outstanding > 0 ? Colors.red.shade700 : Colors.green.shade700,
                        ),

                        // PAYMENT STATUS BADGE
                        SizedBox(height: ds.cardPadding * 0.75),
                        Center(
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: ds.cardPadding,
                              vertical: ds.cardPadding * 0.4,
                            ),
                            decoration: BoxDecoration(
                              color: _outstanding <= 0 ? Colors.green.shade600 : Colors.red.shade600,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _outstanding <= 0 ? Icons.check_circle : Icons.warning_rounded,
                                  color: Colors.white,
                                  size: ds.iconSize * 0.85,
                                ),
                                SizedBox(width: ds.cardPadding * 0.4),
                                Text(
                                  _outstanding <= 0 ? 'BALANCED' : 'YET TO BALANCE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: ds.bodyFontSize,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // PAYMENTS SECTION
                        if (_payments.isNotEmpty) ...[
                          SizedBox(height: ds.cardPadding),
                          Divider(color: Colors.teal.shade300),
                          SizedBox(height: ds.cardPadding * 0.5),
                          Row(
                            children: [
                              Icon(Icons.payments, size: ds.iconSize * 0.8, color: Colors.green.shade600),
                              SizedBox(width: ds.cardPadding * 0.3),
                              Text(
                                'Payment History (${_payments.length})',
                                style: TextStyle(
                                  fontSize: ds.bodyFontSize,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green.shade800,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: ds.cardPadding * 0.5),
                          ..._payments.map((payment) => Container(
                            margin: EdgeInsets.only(bottom: ds.cardPadding * 0.4),
                            padding: EdgeInsets.all(ds.cardPadding * 0.5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.all(ds.cardPadding * 0.4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    _getPaymentMethodIcon(payment['method']?.toString() ?? 'Cash'),
                                    size: ds.iconSize * 0.8,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                                SizedBox(width: ds.cardPadding * 0.5),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '₦${NumberFormat('#,##0.00').format((payment['amount'] as num?)?.toDouble() ?? 0)}',
                                        style: TextStyle(
                                          fontSize: ds.bodyFontSize,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                      SizedBox(height: ds.cardPadding * 0.1),
                                      Wrap(
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        spacing: 6,
                                        runSpacing: 2,
                                        children: [
                                          Text(
                                            '${payment['method'] ?? 'Cash'} •',
                                            style: TextStyle(
                                              fontSize: ds.bodyFontSize * 0.8,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                          Text(
                                            formatPaymentDateOnly(payment['paymentDate']?.toString()),
                                            style: TextStyle(
                                              fontSize: ds.bodyFontSize * 0.8,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                          Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: ds.cardPadding * 0.3,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade50,
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: Colors.green.shade100),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.access_time, size: ds.bodyFontSize * 0.75, color: Colors.green.shade700),
                                                const SizedBox(width: 3),
                                                Text(
                                                  formatPaymentTimeOnly(payment['paymentDate']?.toString()),
                                                  style: TextStyle(
                                                    fontSize: ds.bodyFontSize * 0.75,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.green.shade700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (payment['note'] != null && payment['note'].toString().isNotEmpty)
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: ds.cardPadding * 0.4,
                                      vertical: ds.cardPadding * 0.2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      payment['note'].toString(),
                                      style: TextStyle(
                                        fontSize: ds.bodyFontSize * 0.75,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          )),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

            if (_activeTerm.isNotEmpty) SizedBox(height: ds.cardPadding * 1.25),

            // SIBLINGS CARD
            if (_siblings.isNotEmpty)
              Card(
                elevation: 2,
                color: Colors.purple.shade50,
                child: Padding(
                  padding: EdgeInsets.all(ds.cardPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.people, color: Colors.purple.shade700, size: ds.iconSize),
                          SizedBox(width: ds.cardPadding * 0.5),
                          Expanded(
                            child: Text(
                              'Siblings (${_siblings.length})',
                              style: TextStyle(
                                fontSize: ds.titleFontSize,
                                fontWeight: FontWeight.bold,
                                color: Colors.purple.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      ..._siblings.map((sibling) => _buildSiblingTile(sibling, ds)),
                      SizedBox(height: ds.cardPadding * 0.5),
                      // View Siblings Information button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _openSiblingsInformation(),
                          icon: Icon(Icons.family_restroom, size: ds.iconSize * 0.9),
                          label: Text(
                            'View Siblings Information',
                            style: TextStyle(fontSize: ds.bodyFontSize),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.purple.shade700,
                            side: BorderSide(color: Colors.purple.shade300),
                            padding: EdgeInsets.symmetric(vertical: ds.cardPadding * 0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (_siblings.isNotEmpty) SizedBox(height: ds.cardPadding * 1.25),

            // ACTION BUTTONS SECTION — large screens use the right-hand
            // quick access bar instead.
            if (!showQuickAccessBar) ...[
              Text(
                "Quick Actions",
                style: TextStyle(
                  fontSize: ds.titleFontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),

              SizedBox(height: ds.cardPadding * 0.75),

              // BILLING + PAYMENTS + PAYMENT HISTORY
              Wrap(
                spacing: ds.cardPadding * 0.5,
                runSpacing: ds.cardPadding * 0.5,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    icon: Icon(Icons.receipt_long, size: ds.iconSize),
                    label: Text("Generate Bill", style: TextStyle(fontSize: ds.bodyFontSize)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: ds.cardPadding,
                        vertical: ds.cardPadding * 0.75,
                      ),
                    ),
                    onPressed: _openGenerateBill,
                  ),
                  ElevatedButton.icon(
                    icon: Icon(Icons.payment, size: ds.iconSize),
                    label: Text("Record Payment", style: TextStyle(fontSize: ds.bodyFontSize)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: ds.cardPadding,
                        vertical: ds.cardPadding * 0.75,
                      ),
                    ),
                    onPressed: _openRecordPayment,
                  ),
                  ElevatedButton.icon(
                    icon: Icon(Icons.history, size: ds.iconSize),
                    label: Text("Payment History", style: TextStyle(fontSize: ds.bodyFontSize)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: ds.cardPadding,
                        vertical: ds.cardPadding * 0.75,
                      ),
                    ),
                    onPressed: _openPaymentHistory,
                  ),
                ],
              ),

              SizedBox(height: ds.cardPadding * 0.75),
            ],

            // REFRESH BUTTON
            TextButton.icon(
              icon: Icon(Icons.refresh, size: ds.iconSize),
              label: Text("Refresh Data", style: TextStyle(fontSize: ds.bodyFontSize)),
              onPressed: _loadStudentWithClassArm,
            ),
          ],
        ),
    );
  }

  /// Right-hand quick access bar (large screens only).
  Widget _buildQuickAccessBar(DisplaySettings ds) {
    final theme = Theme.of(context);
    final hasParentPhone = current.parentPhone.trim().isNotEmpty;

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(left: BorderSide(color: theme.dividerColor)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(ds.cardPadding * 0.75),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: ds.cardPadding * 0.25,
                bottom: ds.cardPadding * 0.5,
              ),
              child: Text(
                'Quick Access',
                style: TextStyle(
                  fontSize: ds.titleFontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
            _quickAccessTile(
              ds,
              icon: Icons.receipt_long,
              color: Colors.teal,
              label: 'Go to Bills & Payments',
              onTap: _scrollToBillsAndPayments,
            ),
            _quickAccessTile(
              ds,
              icon: Icons.payment,
              color: Colors.green,
              label: 'Record Payment',
              onTap: _openRecordPayment,
            ),
            _quickAccessTile(
              ds,
              icon: Icons.request_quote,
              color: Colors.blue,
              label: 'Generate Bills',
              onTap: _openGenerateBill,
            ),
            _quickAccessTile(
              ds,
              icon: Icons.history,
              color: Colors.deepPurple,
              label: 'Payment History',
              onTap: _openPaymentHistory,
            ),
            if (_siblings.isNotEmpty)
              _quickAccessTile(
                ds,
                icon: Icons.family_restroom,
                color: Colors.purple,
                label: 'View Siblings Information',
                subtitle: '${_siblings.length} sibling${_siblings.length == 1 ? '' : 's'}',
                onTap: _openSiblingsInformation,
              ),
            if (hasParentPhone)
              _quickAccessTile(
                ds,
                icon: Icons.call,
                color: Colors.green.shade700,
                label: 'Dial Parent',
                subtitle: current.parentPhone,
                onTap: () => _dialPhone(current.parentPhone),
              ),
            if (_canManageStudents)
              _quickAccessTile(
                ds,
                icon: Icons.edit,
                color: Colors.orange.shade800,
                label: "Edit Student's Information",
                onTap: _openEditStudent,
              ),
          ],
        ),
      ),
    );
  }

  Widget _quickAccessTile(
    DisplaySettings ds, {
    required IconData icon,
    required Color color,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: ds.cardPadding * 0.5),
      child: Material(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ds.cardPadding * 0.6,
              vertical: ds.cardPadding * 0.6,
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(ds.cardPadding * 0.4),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: ds.iconSize * 0.9, color: Colors.white),
                ),
                SizedBox(width: ds.cardPadding * 0.6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: ds.bodyFontSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: ds.bodyFontSize * 0.85,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getPaymentMethodIcon(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return Icons.payments;
      case 'pos':
        return Icons.credit_card;
      case 'transfer':
        return Icons.account_balance;
      case 'bank transfer':
        return Icons.account_balance;
      default:
        return Icons.payment;
    }
  }

  Widget _buildSiblingTile(Map<String, dynamic> sibling, DisplaySettings ds) {
    final fullName = '${sibling['surname']} ${sibling['firstName']} ${sibling['otherName'] ?? ''}'.trim();
    final className = sibling['className'] ?? 'N/A';
    final armName = sibling['armName'];
    final classDisplay = armName != null && armName.isNotEmpty ? '$className - $armName' : className;
    final gender = sibling['gender'] ?? 'Male';
    final photoPath = sibling['photoPath'];

    ImageProvider? photo;
    if (photoPath != null && photoPath.isNotEmpty && File(photoPath).existsSync()) {
      photo = FileImage(File(photoPath));
    }

    return InkWell(
      onTap: () async {
        // Navigate to sibling's details
        final db = await DatabaseHelperWrapper().database;
        final result = await db.rawQuery('''
          SELECT s.*, c.name as className, a.name as armName
          FROM students s
          LEFT JOIN classes c ON s.classId = c.id
          LEFT JOIN arms a ON s.armId = a.id
          WHERE s.id = ?
        ''', [sibling['id']]);

        if (result.isNotEmpty && mounted) {
          final siblingStudent = Student.fromMap(result.first);
          NavigationHelper.pushWithSidebar(
            context,
            page: StudentDetailsScreen(student: siblingStudent),
            currentUser: _currentUser ?? {},
            pageId: 'student_management/students',
          );
        }
      },
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: ds.cardPadding * 0.5),
        child: Row(
          children: [
            CircleAvatar(
              radius: ds.iconSize * 0.83,
              backgroundColor: gender == 'Male' ? Colors.blue.shade100 : Colors.pink.shade100,
              backgroundImage: photo,
              child: photo == null
                  ? Icon(
                      gender == 'Male' ? Icons.boy : Icons.girl,
                      size: ds.iconSize * 0.83,
                      color: gender == 'Male' ? Colors.blue.shade700 : Colors.pink.shade700,
                    )
                  : null,
            ),
            SizedBox(width: ds.cardPadding * 0.75),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fullName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: ds.bodyFontSize,
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  SizedBox(height: ds.cardPadding * 0.125),
                  Text(
                    classDisplay,
                    style: TextStyle(
                      fontSize: ds.bodyFontSize * 0.85,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: ds.bodyFontSize, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _billRow(String label, double amount, DisplaySettings ds, {bool bold = false, Color? color}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: ds.cardPadding * 0.25),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: ds.bodyFontSize,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '₦${NumberFormat('#,##0.00').format(amount)}',
            style: TextStyle(
              fontSize: ds.bodyFontSize,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
