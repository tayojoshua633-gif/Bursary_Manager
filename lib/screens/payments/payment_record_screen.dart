// lib/screens/payments/payment_record_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database_helper_wrapper.dart';
import 'payment_receipt_screen.dart';
import '../../utils/backup_reminder_helper.dart';
import '../../utils/cloud_sync_helper.dart';
import '../../utils/display_settings_helper.dart';
import '../../utils/navigation_helper.dart';
import '../../widgets/sibling_mark.dart';
import '../students/siblings_information_screen.dart';

class PaymentRecordScreen extends StatefulWidget {
  final int studentId;
  final String studentName;

  const PaymentRecordScreen({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<PaymentRecordScreen> createState() => _PaymentRecordScreenState();
}

class _PaymentRecordScreenState extends State<PaymentRecordScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  bool _loading = true;

  Map<String, dynamic>? _student;
  // Populated when this student shares a parent phone with other active
  // students, so we can nudge staff toward the consolidated Family Payment.
  Map<String, dynamic>? _siblingGroup;
  String _term = "";
  String _session = "";

  // CORRECTED: Term-specific calculations
  double _previousBalance = 0.0;     // Debt from previous terms
  double _currentTermBill = 0.0;     // Fees for current term only
  double _grandTotal = 0.0;          // Previous Balance + Current Term Bill
  double _paymentsThisTerm = 0.0;    // Payments made this term
  double _outstanding = 0.0;         // Grand Total - Payments This Term

  // For display: Sum of all grand totals across all terms

  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  String? _selectedMethod;
  DateTime _selectedDate = DateTime.now();

  // Payment methods
  final List<String> _methods = ["Cash", "Transfer", "POS"];

  // Payment For
  static const String _kPaymentPurposesKey = 'payment_purposes';
  static const String _defaultPurpose = 'School Fees';
  List<String> _paymentPurposes = [_defaultPurpose, 'Tuition Fee'];
  String _selectedPaymentFor = _defaultPurpose;
  Map<String, dynamic>? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadData();
    _loadPaymentPurposes();
  }

  Future<void> _loadPaymentPurposes() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_kPaymentPurposesKey);
    if (stored != null && stored.isNotEmpty) {
      // Ensure "School Fees" is always first, even for existing saved lists
      final merged = [
        _defaultPurpose,
        ...stored.where((p) => p != _defaultPurpose),
      ];
      setState(() {
        _paymentPurposes = merged;
        _selectedPaymentFor = _defaultPurpose;
      });
      // Persist the merged list so it's consistent on next load
      await prefs.setStringList(_kPaymentPurposesKey, merged);
    }
  }

  Future<void> _addPaymentPurpose(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _paymentPurposes.contains(trimmed)) return;
    final prefs = await SharedPreferences.getInstance();
    final updated = [..._paymentPurposes, trimmed];
    await prefs.setStringList(_kPaymentPurposesKey, updated);
    setState(() {
      _paymentPurposes = updated;
      _selectedPaymentFor = trimmed;
    });
  }

  Future<void> _removePaymentPurpose(String name) async {
    if (name == _defaultPurpose) return;
    final prefs = await SharedPreferences.getInstance();
    final updated = _paymentPurposes.where((p) => p != name).toList();
    await prefs.setStringList(_kPaymentPurposesKey, updated);
    setState(() {
      _paymentPurposes = updated;
      if (_selectedPaymentFor == name) _selectedPaymentFor = _defaultPurpose;
    });
  }

  void _showManagePurposesDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          title: const Text("Manage Payment Purposes"),
          contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _paymentPurposes.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final purpose = _paymentPurposes[i];
                final isDefault = purpose == _defaultPurpose;
                return ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.label_outline,
                    size: 18,
                    color: isDefault ? Colors.green.shade700 : Colors.grey.shade600,
                  ),
                  title: Text(
                    purpose,
                    style: TextStyle(
                      fontWeight: isDefault ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: isDefault
                      ? Tooltip(
                          message: 'Default — cannot remove',
                          child: Icon(Icons.lock_outline, size: 18, color: Colors.grey.shade400),
                        )
                      : IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          tooltip: 'Remove',
                          onPressed: () async {
                            await _removePaymentPurpose(purpose);
                            setDState(() {});
                          },
                        ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Done"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddPurposeDialog() async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Add Payment Purpose"),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: "Purpose name",
            hintText: "e.g. Development Levy",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Add"),
          ),
        ],
      ),
    );
    if (confirmed == true) await _addPaymentPurpose(ctrl.text);
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userType = prefs.getString('userType') ?? 'bursar';
    final userId = prefs.getInt('userId') ?? 0;
    final username = prefs.getString('username') ?? 'User';

    if (mounted) {
      setState(() {
        _currentUser = {
          'id': userId,
          'userType': userType,
          'username': username,
        };
      });
    }
  }

  // ---------------------------------------------------------------------------
  // LOAD ALL BILLING + PAYMENT DATA
  // ---------------------------------------------------------------------------
  Future<void> _loadData() async {
    setState(() => _loading = true);

    final db = await _db.database;

    // Load student WITH class and arm names using JOIN
    final studentRows = await db.rawQuery('''
      SELECT 
        s.*,
        c.name as className,
        a.name as armName
      FROM students s
      LEFT JOIN classes c ON s.classId = c.id
      LEFT JOIN arms a ON s.armId = a.id
      WHERE s.id = ?
    ''', [widget.studentId]);

    if (studentRows.isNotEmpty) {
      _student = studentRows.first;
    }

    // Detect siblings (same parentPhone, other active students) so we can
    // surface the Family Payment nudge.
    final parentPhone = _student?['parentPhone'] as String?;
    if (parentPhone != null && parentPhone.trim().isNotEmpty) {
      final siblingRows = await db.rawQuery('''
        SELECT
          s.id, s.surname, s.firstName, s.otherName, s.gender,
          s.parentPhone, s.parentName,
          c.name as className, a.name as armName
        FROM students s
        LEFT JOIN classes c ON s.classId = c.id
        LEFT JOIN arms a ON s.armId = a.id
        WHERE s.isActive = 1 AND s.parentPhone = ?
        ORDER BY s.surname, s.firstName
      ''', [parentPhone]);

      _siblingGroup = siblingRows.length > 1
          ? {
              'parentPhone': parentPhone,
              'parentName': siblingRows.first['parentName'] ?? 'Parent',
              'students':
                  siblingRows.map((s) => Map<String, dynamic>.from(s)).toList(),
            }
          : null;
    } else {
      _siblingGroup = null;
    }

    _term = await _db.getActiveTerm();
    _session = (await _db.getActiveSession())?['sessionName'] ?? "";

    // ALWAYS calculate previous balance fresh (same as Bill Generate Screen)
    // This ensures it reflects any updates made to previous term bills/payments
    _previousBalance = await _db.computeOutstandingBeforeTerm(
      widget.studentId,
      term: _term,
      session: _session,
    );

    // Get current term bill
    final bill = await _db.getBillForStudent(widget.studentId, _term, _session);

    if (bill != null) {
      // Get stored bill total and calculate current term fees
      final storedTotal = (bill['totalAmount'] as num?)?.toDouble() ?? 0.0;
      final storedPrevBalance = (bill['previousBalance'] as num?)?.toDouble() ?? 0.0;

      // Current Term Bill = what was billed for current term only (excluding old previous balance)
      _currentTermBill = storedTotal - storedPrevBalance;

      // Grand Total = Fresh Previous Balance + Current Term Fees
      _grandTotal = _previousBalance + _currentTermBill;
    } else {
      // No bill exists yet
      _grandTotal = _previousBalance;
      _currentTermBill = 0.0;
    }

    // Get payments for CURRENT TERM only
    final pays = await _db.getPayments(
      widget.studentId,
      term: _term,
      session: _session,
    );

    _paymentsThisTerm = pays.fold<double>(
      0.0,
      (sum, p) => sum + ((p['amount'] as num?)?.toDouble() ?? 0.0),
    );

    // CORRECTED: Outstanding = Grand Total (Current Term) - Payments (Current Term)
    _outstanding = _grandTotal - _paymentsThisTerm;


    if (mounted) setState(() => _loading = false);
  }

  // ---------------------------------------------------------------------------
  Future<void> _goToFamilyPayment() async {
    if (_siblingGroup == null) return;
    await NavigationHelper.pushWithSidebar(
      context,
      page: SiblingsInformationScreen(
        siblingGroup: _siblingGroup!,
        groupColor: Colors.teal.shade700,
      ),
      currentUser: _currentUser ?? {},
      pageId: 'student_management/siblings',
    );
    if (mounted) _loadData();
  }

  // ---------------------------------------------------------------------------
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: _selectedDate,
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  // ---------------------------------------------------------------------------
  Future<void> _savePayment() async {
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;

    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a valid amount")),
      );
      return;
    }

    if (_selectedMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Select a payment method")),
      );
      return;
    }

    final payment = {
      'studentId': widget.studentId,
      'amount': amount,
      'method': _selectedMethod,
      'note': _noteCtrl.text.trim(),
      'paymentDate': _selectedDate.toIso8601String(),
      'term': _term,
      'session': _session,
      'paymentFor': _selectedPaymentFor,
    };

    int paymentId = 0;

    try {
      paymentId = await _db.insertPayment(payment);

      // Track activity for backup reminder
      await BackupReminderHelper.incrementTransactionCount();
      // Fire-and-forget: silently sync to Google Drive if auto-backup is on
      CloudSyncHelper.triggerAutoBackup();

      if (!mounted) return;

      // Show success toast
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Payment recorded successfully"),
          backgroundColor: Colors.green,
        ),
      );

      // Capture route reference before await to detect sidebar navigation
      final currentRoute = ModalRoute.of(context);

      // OPEN RECEIPT PAGE
      await NavigationHelper.pushWithSidebar(
        context,
        page: PaymentReceiptScreen(
          paymentId: paymentId,
          studentId: widget.studentId,
        ),
        currentUser: _currentUser ?? {},
        pageId: 'bills_payment/payments',
      );

      // After returning from receipt, close this screen too
      // Skip if our route was already popped (e.g. sidebar navigated home)
      if (mounted && currentRoute?.isActive == true) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Record Payment — "),
            Flexible(child: Text(widget.studentName, overflow: TextOverflow.ellipsis)),
            SiblingMark(show: _siblingGroup != null),
          ],
        ),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(ds.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Student Info Card
                  Card(
                    elevation: 2,
                    color: Colors.blue.shade50,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.shade700,
                        child: const Icon(Icons.person, color: Colors.white),
                      ),
                      title: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              widget.studentName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: ds.titleFontSize,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SiblingMark(show: _siblingGroup != null),
                        ],
                      ),
                      subtitle: Text(
                        "${_student?['className'] ?? 'No Class'} - ${_student?['armName'] ?? 'No Arm'}",
                        style: TextStyle(fontSize: ds.bodyFontSize),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Adm. No:',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          Text(
                            _student?['admissionNo'] ?? 'N/A',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Family Payment nudge — shown only when this student has siblings
                  if (_siblingGroup != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.teal.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.family_restroom, color: Colors.teal.shade700),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'This student has siblings',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.teal.shade800,
                                  ),
                                ),
                                Text(
                                  'Use Family Payment for a better-organized, consolidated record.',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.teal.shade700),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _goToFamilyPayment,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal.shade700,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Family Payment'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Term/Session Info
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.indigo.shade200),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.event, size: 20, color: Colors.indigo),
                              const SizedBox(height: 4),
                              Text(
                                _term,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.indigo.shade200),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.calendar_today, size: 20, color: Colors.indigo),
                              const SizedBox(height: 4),
                              Text(
                                _session,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── FINANCIAL SUMMARY SECTION ──────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.indigo.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.indigo.shade50,
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Solid indigo header strip
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          color: Colors.indigo.shade700,
                          child: Row(
                            children: [
                              const Icon(Icons.account_balance_wallet, color: Colors.white, size: 22),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "FINANCIAL SUMMARY",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                  Text(
                                    "Current Term Overview",
                                    style: TextStyle(
                                      color: Colors.indigo.shade100,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Body
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              _infoCard(
                                "Previous Balance",
                                _previousBalance,
                                Colors.orange,
                                Icons.history,
                              ),
                              const SizedBox(height: 8),
                              _infoCard(
                                "Current Term Fees",
                                _currentTermBill,
                                Colors.blue,
                                Icons.receipt_long,
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Divider(thickness: 1),
                              ),
                              _infoCard(
                                "Grand Total (This Term)",
                                _grandTotal,
                                Colors.purple,
                                Icons.summarize,
                                subtitle: "Previous + Current Fees",
                              ),
                              const SizedBox(height: 8),
                              _infoCard(
                                "Paid This Term",
                                _paymentsThisTerm,
                                Colors.green,
                                Icons.payment,
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Divider(thickness: 2),
                              ),

                              // Outstanding balance
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: _outstanding > 0
                                      ? Colors.red.shade50
                                      : Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _outstanding > 0
                                        ? Colors.red.shade200
                                        : Colors.green.shade200,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          _outstanding > 0
                                              ? Icons.warning_rounded
                                              : Icons.check_circle,
                                          color: _outstanding > 0
                                              ? Colors.red.shade700
                                              : Colors.green.shade700,
                                          size: 26,
                                        ),
                                        const SizedBox(width: 10),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              "Outstanding (This Term)",
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              "Grand Total − Paid This Term",
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    Text(
                                      "₦${NumberFormat("#,##0.00").format(_outstanding)}",
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: _outstanding > 0
                                            ? Colors.red.shade700
                                            : Colors.green.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Section Divider ─────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Row(
                      children: [
                        Expanded(child: Divider(thickness: 1.5, color: Colors.grey.shade300)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.green.shade700,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              "RECORD PAYMENT",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ),
                        Expanded(child: Divider(thickness: 1.5, color: Colors.grey.shade300)),
                      ],
                    ),
                  ),

                  // ── RECORD NEW PAYMENT SECTION ──────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.green.shade300),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.shade100,
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Solid green header strip
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          color: Colors.green.shade700,
                          child: Row(
                            children: [
                              const Icon(Icons.add_card, color: Colors.white, size: 22),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "RECORD NEW PAYMENT",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                  Text(
                                    "Enter payment details below",
                                    style: TextStyle(
                                      color: Colors.green.shade100,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Form body
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Amount Field
                              TextField(
                                controller: _amountCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: "Amount Paid",
                                  prefixText: "₦",
                                  prefixIcon: const Icon(Icons.money),
                                  border: const OutlineInputBorder(),
                                  filled: true,
                                  fillColor: Colors.green.shade50,
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Payment For
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _selectedPaymentFor,
                                      decoration: InputDecoration(
                                        labelText: "Payment For",
                                        prefixIcon: const Icon(Icons.label_outline),
                                        border: const OutlineInputBorder(),
                                        filled: true,
                                        fillColor: Colors.green.shade50,
                                      ),
                                      items: _paymentPurposes
                                          .map((p) => DropdownMenuItem<String>(
                                                value: p,
                                                child: Text(p),
                                              ))
                                          .toList(),
                                      onChanged: (v) =>
                                          setState(() => _selectedPaymentFor = v!),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Tooltip(
                                    message: "Add new purpose",
                                    child: InkWell(
                                      onTap: _showAddPurposeDialog,
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        margin: const EdgeInsets.only(top: 4),
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade700,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.add,
                                            color: Colors.white, size: 22),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Tooltip(
                                    message: "Manage purposes",
                                    child: InkWell(
                                      onTap: _showManagePurposesDialog,
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        margin: const EdgeInsets.only(top: 4),
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade600,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.edit_note,
                                            color: Colors.white, size: 22),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),

                              // Payment Method Dropdown
                              DropdownButtonFormField<String>(
                                decoration: InputDecoration(
                                  labelText: "Payment Method",
                                  prefixIcon: const Icon(Icons.payment),
                                  border: const OutlineInputBorder(),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                ),
                                items: _methods
                                    .map((m) => DropdownMenuItem<String>(
                                        value: m, child: Text(m)))
                                    .toList(),
                                onChanged: (v) => setState(() => _selectedMethod = v),
                              ),

                              const SizedBox(height: 16),

                              // Payment Date Field
                              TextFormField(
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: "Payment Date",
                                  prefixIcon: const Icon(Icons.calendar_today),
                                  border: const OutlineInputBorder(),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.edit_calendar),
                                    onPressed: _pickDate,
                                  ),
                                ),
                                controller: TextEditingController(
                                  text: DateFormat("EEEE, MMM dd, yyyy")
                                      .format(_selectedDate),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Note Field
                              TextField(
                                controller: _noteCtrl,
                                maxLines: 3,
                                decoration: InputDecoration(
                                  labelText: "Note (Optional)",
                                  prefixIcon: const Icon(Icons.note),
                                  border: const OutlineInputBorder(),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  hintText: "Enter any additional notes...",
                                ),
                              ),

                              const SizedBox(height: 24),

                              // Save Button
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.save, size: 26),
                                  label: const Text(
                                    "Save Payment & Print Receipt",
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: _savePayment,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green.shade700,
                                    foregroundColor: Colors.white,
                                    elevation: 4,
                                    shadowColor: Colors.green.shade300,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _infoCard(
    String title,
    double amount,
    Color color,
    IconData icon, {
    String? subtitle,
  }) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                  ],
                ),
              ],
            ),
            Text(
              "₦${NumberFormat("#,##0.00").format(amount)}",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}