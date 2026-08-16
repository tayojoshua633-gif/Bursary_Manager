// lib/screens/students/student_details_screen.dart

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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
import '../../utils/thermal_printer_manager.dart';
import '../../utils/print_counter_helper.dart';
import '../../utils/navigation_helper.dart';
import '../../widgets/sibling_mark.dart';
import '../settings/thermal_printer_screen.dart';
import '../../utils/usb_printer_manager.dart';
import '../settings/usb_printer_screen.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import '../../utils/payment_date_time_formatter.dart';
import '../../utils/sms_service.dart';

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

  Future<void> _sendBillSms() async {
    if (_activeTerm.isEmpty || _activeSession.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill data is not loaded yet')),
      );
      return;
    }

    final studentName = "${current.surname} ${current.firstName}".trim();
    final message = buildBillSummarySms(
      schoolName: _school?['name']?.toString() ?? 'the school',
      studentName: studentName,
      grandTotal: _grandTotal,
      totalPaid: _totalPaid,
      outstanding: _outstanding,
      term: _activeTerm,
      session: _activeSession,
      bankAccounts: _getBankAccounts(),
    );

    final result = await SmsService.send(
      rawPhone: current.parentPhone,
      message: message,
      studentId: current.id,
      context: 'student_bill',
    );

    if (mounted) {
      final label = result.success
          ? (result.requiresManualConfirmation ? 'Messaging app opened — tap Send to deliver it' : 'Bill/Payment SMS sent to parent')
          : (result.errorMessage ?? 'Failed to send SMS');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(label),
          backgroundColor: result.success ? Colors.green : Colors.red,
        ),
      );
    }
  }

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
            onPressed: () async {
              final uri = Uri(scheme: 'tel', path: phone);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not open dialer')),
                );
              }
            },
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
              onPressed: () async {
                final changed = await NavigationHelper.pushWithSidebar(
                  context,
                  page: StudentEditScreen(student: current),
                  currentUser: _currentUser ?? {},
                  pageId: 'student_management/students',
                );

                if (changed == true) {
                  // Reload student with class/arm names
                  _loadStudentWithClassArm();
                }
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
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
                              onPressed: _sendBillSms,
                              icon: Icon(Icons.sms_outlined, color: Colors.teal.shade700),
                              tooltip: 'Send Bill/Payment SMS',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            SizedBox(width: ds.cardPadding * 0.25),
                            // Previous term comparison button
                            IconButton(
                              onPressed: _showPreviousTermBills,
                              icon: Icon(Icons.compare_arrows, color: Colors.teal.shade700),
                              tooltip: 'Previous Term Bills',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            SizedBox(width: ds.cardPadding * 0.25),
                            // Print button
                            IconButton(
                              onPressed: _showBillPrintOptions,
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

            // ACTION BUTTONS SECTION
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
                  onPressed: () async {
                    await NavigationHelper.pushWithSidebar(
                      context,
                      page: BillGenerateScreen(
                        studentId: current.id!,
                        studentName:
                            "${current.surname} ${current.firstName}",
                        isSibling: _siblings.isNotEmpty,
                      ),
                      currentUser: _currentUser ?? {},
                      pageId: 'student_management/students',
                    );
                    if (mounted) _loadBillData();
                  },
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
                  onPressed: () async {
                    await NavigationHelper.pushWithSidebar(
                      context,
                      page: PaymentRecordScreen(
                        studentId: current.id!,
                        studentName:
                            "${current.surname} ${current.firstName}",
                        ),
                      currentUser: _currentUser ?? {},
                      pageId: 'student_management/students',
                    );
                    if (mounted) _loadBillData();
                  },
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
                  onPressed: () async {
                    await NavigationHelper.pushWithSidebar(
                      context,
                      page: PaymentHistoryScreen(
                        studentId: current.id!,
                        studentName:
                            "${current.surname} ${current.firstName}",
                        ),
                      currentUser: _currentUser ?? {},
                      pageId: 'student_management/students',
                    );
                    if (mounted) _loadBillData();
                  },
                ),
              ],
            ),

            SizedBox(height: ds.cardPadding * 0.75),

            // REFRESH BUTTON
            TextButton.icon(
              icon: Icon(Icons.refresh, size: ds.iconSize),
              label: Text("Refresh Data", style: TextStyle(fontSize: ds.bodyFontSize)),
              onPressed: _loadStudentWithClassArm,
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getBankAccounts() {
    if (_school == null) return [];
    final accounts = <Map<String, dynamic>>[];
    for (int i = 1; i <= 3; i++) {
      final bankName = _school!['bankName$i']?.toString() ?? '';
      final accNum = _school!['accountNumber$i']?.toString() ?? '';
      final accName = _school!['accountName$i']?.toString() ?? '';
      if (bankName.isNotEmpty && accNum.isNotEmpty) {
        accounts.add({'bankName': bankName, 'accountNumber': accNum, 'accountName': accName});
      }
    }
    return accounts;
  }

  List<pw.Widget> _buildBankDetailsPdf() {
    final bankAccounts = _getBankAccounts();
    if (bankAccounts.isEmpty) return [];
    return [
      pw.SizedBox(height: 15),
      pw.Text('Bank Account Details', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
      pw.SizedBox(height: 5),
      pw.TableHelper.fromTextArray(
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.teal100),
        cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerLeft},
        data: [
          ['Bank Name', 'Account Number', 'Account Name'],
          ...bankAccounts.map((a) => [
            a['bankName']?.toString() ?? '',
            a['accountNumber']?.toString() ?? '',
            a['accountName']?.toString() ?? '',
          ]),
        ],
      ),
    ];
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

  void _showBillPrintOptions() {
    final formatter = NumberFormat('#,##0.00');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.print, color: Colors.teal.shade700),
            const SizedBox(width: 8),
            const Text('Print Statement'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${current.surname} ${current.firstName}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              '$_activeTerm - $_activeSession',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Grand Total:'),
                      Text('₦${formatter.format(_grandTotal)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Paid:'),
                      Text('₦${formatter.format(_totalPaid)}', style: TextStyle(color: Colors.green.shade700)),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_outstanding >= 0 ? 'Outstanding:' : 'Overpayment:'),
                      Text(
                        '₦${formatter.format(_outstanding.abs())}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _outstanding > 0 ? Colors.red.shade700 : Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _printBillAsJPEG();
            },
            icon: const Icon(Icons.image),
            label: const Text('JPEG'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _printBillAsPDF();
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _printBillThermal();
            },
            icon: const Icon(Icons.print),
            label: const Text('Thermal'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _printBillViaUsb();
            },
            icon: const Icon(Icons.usb),
            label: const Text('USB'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printBillAsPDF() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final pdf = pw.Document();
      final formatter = NumberFormat('#,##0.00');
      final studentName = '${current.surname} ${current.firstName} ${current.otherName ?? ''}'.trim();
      final className = current.className ?? 'N/A';
      final armName = current.armName;
      final classDisplay = armName != null && armName.isNotEmpty ? '$className - $armName' : className;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            return [
              // School Header
              pw.Center(
                child: pw.Text(
                  _school?['name']?.toString().toUpperCase() ?? 'SCHOOL NAME',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.teal700),
                ),
              ),
              pw.SizedBox(height: 5),
              if (_school?['address'] != null)
                pw.Center(
                  child: pw.Text(
                    _school!['address'].toString(),
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                  ),
                ),
              pw.SizedBox(height: 15),

              // Title
              pw.Center(
                child: pw.Text(
                  'STUDENT BILL STATEMENT',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Center(
                child: pw.Text(
                  '$_activeTerm - $_activeSession',
                  style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
                ),
              ),
              pw.SizedBox(height: 20),

              // Student Info
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.teal300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Student: $studentName', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.Text('Adm No: ${current.admissionNo}'),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text('Class: $classDisplay', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Bill Items Table
              if (_billItems.isNotEmpty) ...[
                pw.Text('Bill Breakdown', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                pw.SizedBox(height: 8),
                pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.teal100),
                  cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight},
                  data: [
                    ['Fee Item', 'Amount'],
                    ..._billItems.map((item) => [
                      item['feeName']?.toString() ?? 'Fee Item',
                      'N${formatter.format((item['amount'] as num?)?.toDouble() ?? 0)}',
                    ]),
                  ],
                ),
                pw.SizedBox(height: 15),
              ],

              // Summary
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.teal50,
                  border: pw.Border.all(color: PdfColors.teal400, width: 1.5),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Current Term Bill:', style: const pw.TextStyle(fontSize: 11)),
                        pw.Text('N${formatter.format(_currentTermBill)}'),
                      ],
                    ),
                    if (_previousBalance != 0)
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(_previousBalance > 0 ? 'Previous Balance:' : 'Previous Credit:', style: const pw.TextStyle(fontSize: 11)),
                          pw.Text('N${formatter.format(_previousBalance.abs())}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _previousBalance > 0 ? PdfColors.orange700 : PdfColors.green700)),
                        ],
                      ),
                    pw.Divider(),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Grand Total:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                        pw.Text('N${formatter.format(_grandTotal)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.purple700)),
                      ],
                    ),
                    pw.SizedBox(height: 5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Total Paid:', style: const pw.TextStyle(fontSize: 11)),
                        pw.Text('N${formatter.format(_totalPaid)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.green700)),
                      ],
                    ),
                    pw.Divider(thickness: 1.5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(_outstanding >= 0 ? 'OUTSTANDING:' : 'OVERPAYMENT:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                        pw.Text(
                          'N${formatter.format(_outstanding.abs())}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13, color: _outstanding > 0 ? PdfColors.red700 : PdfColors.green700),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Payments Table
              if (_payments.isNotEmpty) ...[
                pw.Text('Payment History', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                pw.SizedBox(height: 8),
                pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.green100),
                  cellAlignments: {0: pw.Alignment.center, 1: pw.Alignment.centerRight, 2: pw.Alignment.center, 3: pw.Alignment.center},
                  data: [
                    ['S/N', 'Amount', 'Method', 'Date', 'Receipt'],
                    ..._payments.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final p = entry.value;
                      return [
                        '${idx + 1}',
                        'N${formatter.format((p['amount'] as num?)?.toDouble() ?? 0)}',
                        p['method']?.toString() ?? 'Cash',
                        p['paymentDate']?.toString() ?? '',
                        p['note']?.toString() ?? '-',
                      ];
                    }),
                  ],
                ),
              ],

              // Bank Account Details
              ..._buildBankDetailsPdf(),

              pw.SizedBox(height: 30),
              pw.Divider(),
              pw.Text(
                'Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            ];
          },
        ),
      );

      final dir = await getApplicationDocumentsDirectory();
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File('${dir.path}/bill_${current.surname}_${current.firstName}_$dateStr.pdf');
      await file.writeAsBytes(await pdf.save());

      if (!mounted) return;
      Navigator.pop(context);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Bill Statement - ${current.surname} ${current.firstName}',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill PDF generated successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e')),
      );
    }
  }

  Future<void> _printBillAsJPEG() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      // Capture the bill card as an image
      final boundary = _billCardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not capture bill card')),
        );
        return;
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not generate image')),
        );
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File('${dir.path}/bill_${current.surname}_${current.firstName}_$dateStr.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      if (!mounted) return;
      Navigator.pop(context);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Bill Statement - ${current.surname} ${current.firstName}',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill image generated successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating image: $e')),
      );
    }
  }

  Future<void> _printBillThermal() async {
    if (!ThermalPrinterManager.isConnected) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please connect to a thermal printer first'),
          duration: Duration(seconds: 2),
        ),
      );

      await NavigationHelper.pushWithSidebar(
        context,
        page: const ThermalPrinterScreen(),
        currentUser: _currentUser ?? {},
        pageId: 'student_management/students',
      );

      if (!ThermalPrinterManager.isConnected) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Printer not connected. Printing cancelled.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final schoolName = _school?['name'] ?? 'School Name';
      final schoolAddress = _school?['address'] ?? '';
      final studentName = '${current.surname} ${current.firstName}'.trim();
      final className = current.className ?? 'N/A';
      final armName = current.armName;
      final classDisplay = armName != null && armName.isNotEmpty ? '$className - $armName' : className;

      // Build fee items for thermal print
      final List<Map<String, dynamic>> feeItems = [];
      for (final item in _billItems) {
        feeItems.add(<String, dynamic>{
          'name': item['feeName']?.toString() ?? 'Fee',
          'amount': (item['amount'] as num?)?.toDouble() ?? 0.0,
        });
      }

      // Add previous balance (or credit, shown as a negative deduction) if any
      if (_previousBalance != 0) {
        feeItems.insert(0, <String, dynamic>{
          'name': _previousBalance > 0 ? 'Previous Balance' : 'Previous Credit',
          'amount': _previousBalance,
        });
      }

      await ThermalPrinterManager.printBill(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        schoolPhone: _school?['phone']?.toString(),
        bankAccounts: _getBankAccounts(),
        studentName: studentName,
        studentClass: classDisplay,
        term: '$_activeTerm $_activeSession',
        feeItems: feeItems,
        total: _grandTotal,
        billDate: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      );
      await PrintCounterHelper.incrementBillsPrinted();

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill printed successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error printing: $e')),
      );
    }
  }

  Future<void> _printBillViaUsb() async {
    if (!UsbPrinterManager.isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please connect a USB printer first'),
          duration: Duration(seconds: 2),
        ),
      );
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const UsbPrinterScreen()),
      );
      if (!UsbPrinterManager.isConnected) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No USB printer connected. Printing cancelled.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final schoolName = _school?['name'] ?? 'School Name';
      final schoolAddress = _school?['address'] ?? '';
      final studentName = '${current.surname} ${current.firstName}'.trim();
      final className = current.className ?? 'N/A';
      final armName = current.armName;
      final classDisplay = armName != null && armName.isNotEmpty
          ? '$className - $armName'
          : className;

      final List<Map<String, dynamic>> feeItems = [];
      if (_previousBalance != 0) {
        feeItems.add({
          'name': _previousBalance > 0 ? 'Previous Balance' : 'Previous Credit',
          'amount': _previousBalance,
        });
      }
      for (final item in _billItems) {
        feeItems.add({
          'name': item['feeName']?.toString() ?? 'Fee',
          'amount': (item['amount'] as num?)?.toDouble() ?? 0.0,
        });
      }

      final paperSize = await UsbPrinterManager.getPaperSize();

      await UsbPrinterManager.printBill(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        schoolPhone: _school?['phone']?.toString(),
        bankAccounts: _getBankAccounts(),
        studentName: studentName,
        studentClass: classDisplay,
        term: '$_activeTerm $_activeSession',
        feeItems: feeItems,
        total: _grandTotal,
        billDate: DateFormat('yyyy-MM-dd').format(DateTime.now()),
        paperSize: paperSize == 'mm58' ? PaperSize.mm58 : PaperSize.mm80,
      );
      await PrintCounterHelper.incrementBillsPrinted();

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill printed via USB successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('USB print error: $e')),
      );
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

  Future<void> _showPreviousTermBills() async {
    final prevTermSession = DatabaseHelperWrapper.previousTermSession(
      term: _activeTerm,
      session: _activeSession,
    );

    if (prevTermSession == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No previous term data available')),
      );
      return;
    }

    final prevTerm = prevTermSession['term']!;
    final prevSession = prevTermSession['session']!;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final dbHelper = DatabaseHelperWrapper();
      final db = await dbHelper.database;

      final bill = await dbHelper.getBillForStudent(current.id!, prevTerm, prevSession);

      double prevCurrentTermBill = 0;
      List<Map<String, dynamic>> prevBillItems = [];

      if (bill != null) {
        final storedTotal = (bill['totalAmount'] as num?)?.toDouble() ?? 0.0;
        final storedPrevBal = (bill['previousBalance'] as num?)?.toDouble() ?? 0.0;
        prevCurrentTermBill = storedTotal - storedPrevBal;

        final items = await db.rawQuery('''
          SELECT sfb.id, sfb.feeItemId, sfb.amount,
                 COALESCE(NULLIF(TRIM(sfb.label), ''), fi.name, 'Fee Item') as feeName
          FROM student_fee_breakdown sfb
          LEFT JOIN fee_items fi ON sfb.feeItemId = fi.id
          WHERE sfb.billId = ?
          ORDER BY sfb.id ASC
        ''', [bill['id']]);
        prevBillItems = items.map((e) => Map<String, dynamic>.from(e)).toList();
      }

      final paymentsSum = await db.rawQuery('''
        SELECT COALESCE(SUM(amount), 0) as totalPaid
        FROM payments WHERE studentId = ? AND term = ? AND session = ?
      ''', [current.id, prevTerm, prevSession]);
      final prevTotalPaid = (paymentsSum.first['totalPaid'] as num?)?.toDouble() ?? 0.0;

      // Derive the previous term's carry-in balance from the current term's already-correct
      // _previousBalance rather than calling computeOutstandingBeforeTerm(prevTerm), which
      // would incorrectly include future bills (current term's bill already exists in the DB).
      //
      // _previousBalance = net outstanding for ALL terms before the current term.
      // prevTerm's own net = prevCurrentTermBill - prevTotalPaid.
      // Everything before prevTerm = _previousBalance − prevTerm's net.
      final prevNetOutstanding = prevCurrentTermBill - prevTotalPaid;
      final prevPreviousBalance = (_previousBalance - prevNetOutstanding).clamp(0.0, double.infinity);
      final prevGrandTotal = prevPreviousBalance + prevCurrentTermBill;
      final prevOutstanding = prevGrandTotal - prevTotalPaid;

      final paymentsList = await db.rawQuery('''
        SELECT id, amount, method, note, paymentDate
        FROM payments WHERE studentId = ? AND term = ? AND session = ?
        ORDER BY paymentDate DESC
      ''', [current.id, prevTerm, prevSession]);
      final prevPayments = paymentsList.map((p) => Map<String, dynamic>.from(p)).toList();

      if (!mounted) return;
      Navigator.pop(context);

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => _PreviousTermBillSheet(
          studentName: '${current.surname} ${current.firstName}',
          prevTerm: prevTerm,
          prevSession: prevSession,
          prevPreviousBalance: prevPreviousBalance,
          prevCurrentTermBill: prevCurrentTermBill,
          prevGrandTotal: prevGrandTotal,
          prevTotalPaid: prevTotalPaid,
          prevOutstanding: prevOutstanding,
          prevBillItems: prevBillItems,
          prevPayments: prevPayments,
          currentTerm: _activeTerm,
          currentSession: _activeSession,
          currentPreviousBalance: _previousBalance,
          currentTermBill: _currentTermBill,
          currentGrandTotal: _grandTotal,
          currentTotalPaid: _totalPaid,
          currentOutstanding: _outstanding,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading previous term data: $e')),
      );
    }
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

// ---------------------------------------------------------------------------
// Previous Term Bill Comparison Sheet
// ---------------------------------------------------------------------------

class _PreviousTermBillSheet extends StatelessWidget {
  final String studentName;
  final String prevTerm;
  final String prevSession;
  final double prevPreviousBalance;
  final double prevCurrentTermBill;
  final double prevGrandTotal;
  final double prevTotalPaid;
  final double prevOutstanding;
  final List<Map<String, dynamic>> prevBillItems;
  final List<Map<String, dynamic>> prevPayments;

  final String currentTerm;
  final String currentSession;
  final double currentPreviousBalance;
  final double currentTermBill;
  final double currentGrandTotal;
  final double currentTotalPaid;
  final double currentOutstanding;

  const _PreviousTermBillSheet({
    required this.studentName,
    required this.prevTerm,
    required this.prevSession,
    required this.prevPreviousBalance,
    required this.prevCurrentTermBill,
    required this.prevGrandTotal,
    required this.prevTotalPaid,
    required this.prevOutstanding,
    required this.prevBillItems,
    required this.prevPayments,
    required this.currentTerm,
    required this.currentSession,
    required this.currentPreviousBalance,
    required this.currentTermBill,
    required this.currentGrandTotal,
    required this.currentTotalPaid,
    required this.currentOutstanding,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    final outstandingLabel =
        prevOutstanding <= 0 && currentOutstanding <= 0 ? 'Overpayment' : 'Outstanding';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) => Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Gradient header
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.teal.shade800, Colors.teal.shade500],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.compare_arrows, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Term Comparison',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        studentName,
                        style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
              children: [
                // Comparison card
                Card(
                  elevation: 2,
                  shadowColor: Colors.black12,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Column(
                      children: [
                        // Term chips header — flex mirrors _CompRow layout
                        Container(
                          color: Colors.grey.shade50,
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                          child: Row(
                            children: [
                              const Expanded(flex: 5, child: SizedBox()),
                              Expanded(
                                flex: 4,
                                child: _TermChip(
                                  label: prevTerm,
                                  sub: prevSession,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                              // matches: SizedBox(6) + deltaIcon(14) + SizedBox(4) in _CompRow
                              const SizedBox(width: 24),
                              Expanded(
                                flex: 4,
                                child: _TermChip(
                                  label: currentTerm,
                                  sub: currentSession,
                                  color: Colors.teal.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const _RowDivider(),
                        _CompRow(
                          label: 'Previous Balance',
                          prevAmt: prevPreviousBalance,
                          currAmt: currentPreviousBalance,
                          fmt: fmt,
                          prevColor: prevPreviousBalance > 0 ? Colors.orange.shade700 : Colors.grey.shade400,
                          currColor: currentPreviousBalance > 0 ? Colors.orange.shade700 : Colors.grey.shade400,
                        ),
                        const _RowDivider(),
                        _CompRow(
                          label: 'Term Bill',
                          prevAmt: prevCurrentTermBill,
                          currAmt: currentTermBill,
                          fmt: fmt,
                        ),
                        const _RowDivider(),
                        _CompRow(
                          label: 'Grand Total',
                          prevAmt: prevGrandTotal,
                          currAmt: currentGrandTotal,
                          fmt: fmt,
                          bold: true,
                          highlight: true,
                          prevColor: Colors.purple.shade700,
                          currColor: Colors.purple.shade700,
                        ),
                        const _RowDivider(),
                        _CompRow(
                          label: 'Total Paid',
                          prevAmt: prevTotalPaid,
                          currAmt: currentTotalPaid,
                          fmt: fmt,
                          prevColor: Colors.green.shade700,
                          currColor: Colors.green.shade700,
                        ),
                        const _RowDivider(),
                        _CompRow(
                          label: outstandingLabel,
                          prevAmt: prevOutstanding.abs(),
                          currAmt: currentOutstanding.abs(),
                          fmt: fmt,
                          bold: true,
                          highlight: true,
                          showDelta: true,
                          prevColor: prevOutstanding > 0 ? Colors.red.shade700 : Colors.green.shade700,
                          currColor: currentOutstanding > 0 ? Colors.red.shade700 : Colors.green.shade700,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Bill breakdown section
                _SectionHeader(
                  icon: Icons.receipt_long,
                  label: '$prevTerm Bill Breakdown',
                  color: Colors.orange.shade700,
                ),
                const SizedBox(height: 8),
                if (prevBillItems.isNotEmpty) ...[
                  Card(
                    elevation: 1,
                    shadowColor: Colors.black12,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.orange.shade100),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Column(
                        children: prevBillItems.asMap().entries.map((entry) {
                          final i = entry.key;
                          final item = entry.value;
                          final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
                          final isLast = i == prevBillItems.length - 1;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: i.isOdd ? Colors.orange.shade50.withValues(alpha: 0.4) : Colors.white,
                              border: isLast
                                  ? null
                                  : Border(bottom: BorderSide(color: Colors.orange.shade100)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade300,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    item['feeName']?.toString() ?? 'Fee Item',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                Text(
                                  '₦${fmt.format(amount)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  if (prevPreviousBalance > 0) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.history, size: 14, color: Colors.orange.shade700),
                              const SizedBox(width: 6),
                              Text(
                                '+ Previous Balance',
                                style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                              ),
                            ],
                          ),
                          Text(
                            '₦${fmt.format(prevPreviousBalance)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ] else
                  _EmptyState(message: 'No bill found for $prevTerm $prevSession'),

                // Payment history section
                if (prevPayments.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _SectionHeader(
                    icon: Icons.payments_outlined,
                    label: '$prevTerm Payments',
                    color: Colors.green.shade700,
                    badge: '${prevPayments.length}',
                  ),
                  const SizedBox(height: 8),
                  ...prevPayments.map((p) {
                    final amount = (p['amount'] as num?)?.toDouble() ?? 0.0;
                    final method = p['method']?.toString() ?? 'Cash';
                    final date = p['paymentDate']?.toString() ?? '';
                    final note = p['note']?.toString() ?? '';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade100),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.shade50,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.green.shade50,
                          child: Icon(Icons.check_circle, color: Colors.green.shade600, size: 20),
                        ),
                        title: Text(
                          '₦${fmt.format(amount)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: date.isNotEmpty
                            ? Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 6,
                                runSpacing: 2,
                                children: [
                                  Text(
                                    '$method  ·  ${formatPaymentDateOnly(date)}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.green.shade100),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.access_time, size: 10, color: Colors.green.shade700),
                                        const SizedBox(width: 3),
                                        Text(
                                          formatPaymentTimeOnly(date),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.green.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                method,
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                        trailing: note.isNotEmpty
                            ? Container(
                                constraints: const BoxConstraints(maxWidth: 90),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  note,
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )
                            : null,
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helper widgets for the comparison sheet
// ---------------------------------------------------------------------------

class _TermChip extends StatelessWidget {
  final String label;
  final String sub;
  final Color color;

  const _TermChip({required this.label, required this.sub, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color),
              textAlign: TextAlign.center),
          Text(sub,
              style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.75)),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String? badge;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 18,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
        if (badge != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(badge!,
                style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
          ),
        ],
      ],
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, color: Colors.grey.shade100);
}

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          Text(message, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        ],
      ),
    );
  }
}

class _CompRow extends StatelessWidget {
  final String label;
  final double prevAmt;
  final double currAmt;
  final NumberFormat fmt;
  final Color? prevColor;
  final Color? currColor;
  final bool bold;
  final bool highlight;
  final bool showDelta;

  const _CompRow({
    required this.label,
    required this.prevAmt,
    required this.currAmt,
    required this.fmt,
    this.prevColor,
    this.currColor,
    this.bold = false,
    this.highlight = false,
    this.showDelta = false,
  });

  @override
  Widget build(BuildContext context) {
    final diff = currAmt - prevAmt;
    final fontWeight = bold ? FontWeight.bold : FontWeight.normal;

    Widget deltaIcon = const SizedBox(width: 14);
    if (showDelta && diff != 0) {
      deltaIcon = Icon(
        diff > 0 ? Icons.arrow_upward : Icons.arrow_downward,
        size: 11,
        color: Colors.grey.shade400,
      );
    }

    return Container(
      color: highlight ? Colors.grey.shade50 : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: fontWeight, color: Colors.grey.shade800),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              '₦${fmt.format(prevAmt)}',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                fontWeight: fontWeight,
                color: prevColor ?? Colors.grey.shade800,
              ),
            ),
          ),
          const SizedBox(width: 6),
          deltaIcon,
          const SizedBox(width: 4),
          Expanded(
            flex: 4,
            child: Text(
              '₦${fmt.format(currAmt)}',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                fontWeight: fontWeight,
                color: currColor ?? Colors.grey.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}