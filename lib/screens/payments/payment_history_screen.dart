// lib/screens/payments/payment_history_screen.dart
// UPDATED VERSION with 3 Export Options (PDF, JPEG, Thermal)

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../data/database_helper_wrapper.dart';
import '../../utils/display_settings_helper.dart';
import '../../utils/printer_settings_helper.dart';  // NEW IMPORT
import '../../utils/thermal_printer_manager.dart';
import '../../utils/usb_printer_manager.dart';
import '../../utils/print_counter_helper.dart';
import '../../utils/permission_helper.dart';
import '../../screens/settings/thermal_printer_screen.dart';
import '../../screens/settings/usb_printer_screen.dart';
import '../../screens/billing/debt_notification_screen.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import '../../utils/payment_date_time_formatter.dart';

class PaymentHistoryScreen extends StatefulWidget {
  final int studentId;
  final String studentName;

  const PaymentHistoryScreen({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final GlobalKey _historyKey = GlobalKey();

  List<Map<String, dynamic>> _payments = [];
  final Map<int, Map<String, dynamic>> _lastEditByPaymentId = {};
  Map<String, dynamic>? _student;
  Map<String, dynamic>? _school;

  double _totalPaid = 0;
  double _previousBalance = 0;
  double _currentTermBill = 0;
  double _grandTotal = 0;
  double _outstanding = 0;

  bool _loading = true;
  bool _exporting = false;
  bool _canEditPayments = false;

  String _activeTerm = "";
  String _activeSession = "";

  @override
  void initState() {
    super.initState();
    _checkEditPermission();
    _load();
  }

  Future<void> _checkEditPermission() async {
    final prefs = await SharedPreferences.getInstance();
    final userType = prefs.getString('userType') ?? 'bursar';
    final userId = prefs.getInt('userId') ?? 0;
    final username = prefs.getString('username') ?? 'User';

    final currentUser = {
      'id': userId,
      'userType': userType,
      'username': username,
    };

    final canEdit = await PermissionHelper.hasPermission(currentUser, 'payments_edit');

    if (mounted) {
      setState(() {
        _canEditPayments = canEdit;
      });
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final db = await _db.database;

    _activeTerm = await _db.getActiveTerm();
    _activeSession = (await _db.getActiveSession())?['sessionName'] ?? "";

    _school = await _db.getSchoolProfile();
    
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

    // Load payments for CURRENT TERM only
    _payments = await db.query(
      "payments",
      where: "studentId = ? AND term = ? AND session = ?",
      whereArgs: [widget.studentId, _activeTerm, _activeSession],
      orderBy: "paymentDate ASC",
    );

    _totalPaid = 0;
    for (var p in _payments) {
      final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
      _totalPaid += amt;
    }

    // ALWAYS calculate previous balance fresh (same as Bill Generate Screen)
    // This ensures it reflects any updates made to previous term bills/payments
    _previousBalance = await _db.computeOutstandingBeforeTerm(
      widget.studentId,
      term: _activeTerm,
      session: _activeSession,
    );

    // Get current term bill
    final bill = await _db.getBillForStudent(widget.studentId, _activeTerm, _activeSession);

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

    _outstanding = _grandTotal - _totalPaid;

    // Load latest edit (if any) per payment, so an "Edited by ..." badge
    // can be shown inline — surfaces edits without needing a separate screen
    _lastEditByPaymentId.clear();
    for (final payment in _payments) {
      final paymentId = payment['id'] as int?;
      if (paymentId == null) continue;
      final entries = await _db.getAuditLog(entityType: 'payment', entityId: paymentId);
      final lastUpdate = entries.firstWhere(
        (e) => e['action'] == 'update',
        orElse: () => const {},
      );
      if (lastUpdate.isNotEmpty) {
        _lastEditByPaymentId[paymentId] = lastUpdate;
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  void _showAuditDiffDialog(Map<String, dynamic> auditEntry) {
    final changesRaw = auditEntry['changes'] as String?;
    Map<String, dynamic> diff = {};
    if (changesRaw != null && changesRaw.isNotEmpty) {
      try {
        diff = Map<String, dynamic>.from(jsonDecode(changesRaw) as Map);
      } catch (_) {}
    }
    final username = auditEntry['username']?.toString() ?? 'Unknown';
    final timestamp = DateTime.tryParse(auditEntry['timestamp']?.toString() ?? '');
    final formattedWhen = timestamp != null
        ? DateFormat('dd/MM/yyyy, h:mm a').format(timestamp)
        : '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.history, color: Colors.orange),
            SizedBox(width: 8),
            Text('Edit History'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edited by $username',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if (formattedWhen.isNotEmpty)
                Text(formattedWhen,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              ...diff.entries.map((e) {
                final change = e.value as Map;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${e.key}: ${change['old']} → ${change['new']}',
                    style: const TextStyle(fontSize: 13),
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ========================================
  // DELETE PAYMENT CONFIRMATION
  // ========================================
  Future<void> _showDeletePaymentDialog(Map<String, dynamic> payment) async {
    final paymentId = payment['id'] as int;
    final amount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
    final dateStr = payment['paymentDate']?.toString() ?? "";
    final parsedDate = DateTime.tryParse(dateStr) ?? DateTime.now();
    final formattedDate = DateFormat("dd/MM/yyyy").format(parsedDate);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Payment?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to delete this payment?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDeleteInfoRow('Date:', formattedDate),
                  const SizedBox(height: 8),
                  _buildDeleteInfoRow('Method:', payment['method']?.toString() ?? 'N/A'),
                  const SizedBox(height: 8),
                  _buildDeleteInfoRow('Amount:', 'N${NumberFormat("#,##0.00").format(amount)}'),
                  if (payment['note']?.toString().isNotEmpty ?? false) ...[
                    const SizedBox(height: 8),
                    _buildDeleteInfoRow('Note:', payment['note']?.toString() ?? ''),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This action cannot be undone!',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_forever),
            label: const Text('Delete Payment'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Proceed with deletion
    try {
      await _db.deletePayment(paymentId);

      // Reload data
      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete payment: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildDeleteInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }

  // ========================================
  // EDIT PAYMENT DIALOG
  // ========================================
  Future<void> _showEditPaymentDialog(Map<String, dynamic> payment) async {
    final paymentId = payment['id'] as int;
    final amountController = TextEditingController(
      text: (payment['amount'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00',
    );
    final noteController = TextEditingController(
      text: payment['note']?.toString() ?? '',
    );

    final List<String> methods = ["Cash", "Transfer", "POS"];
    // A stored value outside this fixed list (legacy data, different casing,
    // empty string) would make DropdownButtonFormField's initialValue match
    // no item and throw on build — fall back to the first option instead.
    String selectedMethod = payment['method']?.toString() ?? 'Cash';
    if (!methods.contains(selectedMethod)) selectedMethod = methods.first;
    DateTime selectedDate = DateTime.tryParse(payment['paymentDate']?.toString() ?? '') ?? DateTime.now();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.edit, color: Colors.orange),
              SizedBox(width: 8),
              Text('Edit Payment'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Amount
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: 'N ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Payment Method
                DropdownButtonFormField<String>(
                  initialValue: selectedMethod,
                  decoration: const InputDecoration(
                    labelText: 'Payment Method',
                    border: OutlineInputBorder(),
                  ),
                  items: methods.map((method) {
                    return DropdownMenuItem(
                      value: method,
                      child: Text(method),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        selectedMethod = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Payment Date
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        selectedDate = picked;
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Payment Date',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(
                      DateFormat('dd/MM/yyyy').format(selectedDate),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Note (optional)
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Note (Optional)',
                    border: OutlineInputBorder(),
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
            ElevatedButton.icon(
              onPressed: () async {
                final amount = double.tryParse(amountController.text.trim()) ?? 0.0;

                if (amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter a valid amount')),
                  );
                  return;
                }

                // Update payment in database
                await _db.updatePayment(paymentId, {
                  'amount': amount,
                  'method': selectedMethod,
                  'paymentDate': selectedDate.toIso8601String(),
                  'note': noteController.text.trim(),
                });

                Navigator.pop(context);

                // Reload data
                await _load();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Payment updated successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.save),
              label: const Text('Save Changes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========================================
  // DEBT NOTIFICATION LETTER
  // ========================================
  void _openDebtNotification() {
    final studentName =
        '${_student?['firstName'] ?? ''} ${_student?['surname'] ?? ''}'.trim();
    final admissionNo = _student?['admissionNo']?.toString() ?? '';
    final className =
        '${_student?['className'] ?? ''} ${_student?['armName'] ?? ''}'.trim();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DebtNotificationScreen(
          schoolProfile: _school ?? {},
          studentName: studentName.isNotEmpty ? studentName : widget.studentName,
          admissionNo: admissionNo,
          className: className,
          term: _activeTerm,
          session: _activeSession,
          totalBills: _grandTotal,
          totalPaid: _totalPaid,
          outstanding: _outstanding,
        ),
      ),
    );
  }

  // ========================================
  // NEW: EXPORT OPTIONS DIALOG
  // ========================================
  void _showExportOptionsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.share, color: Colors.blue),
            SizedBox(width: 8),
            Text('Export Payment History'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Choose format to export and share:',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 20),

            // Debt Notification (only shown when there is an outstanding balance)
            if (_outstanding > 0) ...[
              _buildExportOption(
                icon: Icons.mail_outline,
                iconColor: Colors.red.shade700,
                title: 'Debt Notification Letter',
                subtitle: 'Formal letter to parent/guardian',
                onTap: () {
                  if (Navigator.canPop(context)) Navigator.pop(context);
                  _openDebtNotification();
                },
              ),
              const SizedBox(height: 12),
            ],

            // Option 1: PDF
            _buildExportOption(
              icon: Icons.picture_as_pdf,
              iconColor: Colors.red,
              title: 'PDF Document',
              subtitle: 'Standard A4 format, full details',
              onTap: () {
                if (Navigator.canPop(context)) Navigator.pop(context);
                _exportAsPDF();
              },
            ),

            const SizedBox(height: 12),

            // Option 2: JPEG
            _buildExportOption(
              icon: Icons.image,
              iconColor: Colors.green,
              title: 'JPEG Image',
              subtitle: 'High quality image format',
              onTap: () {
                if (Navigator.canPop(context)) Navigator.pop(context);
                _exportAsJPEG();
              },
            ),

            const SizedBox(height: 12),

            // Option 3: Thermal Printer
            _buildExportOption(
              icon: Icons.print,
              iconColor: Colors.orange,
              title: 'Thermal Printer',
              subtitle: 'Select size and print',
              onTap: () {
                if (Navigator.canPop(context)) Navigator.pop(context);
                _showThermalPrinterSizeDialog();
              },
            ),

            const SizedBox(height: 12),

            // Option 4: USB Printer
            _buildExportOption(
              icon: Icons.usb,
              iconColor: Colors.deepPurple,
              title: 'USB Printer (OTG)',
              subtitle: 'Print via USB cable',
              onTap: () {
                if (Navigator.canPop(context)) Navigator.pop(context);
                _showUsbPrinterSizeDialog();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (Navigator.canPop(context)) Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildExportOption({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  // ========================================
  // THERMAL PRINTER SIZE SELECTION DIALOG (Bluetooth Direct Print)
  // ========================================
  Future<void> _showThermalPrinterSizeDialog() async {
    // Check if printer is connected
    if (!ThermalPrinterManager.isConnected) {
      if (!mounted) return;

      // Show message and navigate to printer connection screen
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please connect to a thermal printer first'),
          duration: Duration(seconds: 2),
        ),
      );

      // Navigate to thermal printer connection screen
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ThermalPrinterScreen()),
      );

      // Check again if printer is connected after returning
      if (!ThermalPrinterManager.isConnected) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Printer not connected. History printing cancelled.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.print, color: Colors.orange),
            const SizedBox(width: 8),
            const Text('Print History'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'CONNECTED',
                style: TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 58mm Option
            ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.orange),
              title: const Text('58mm Paper'),
              subtitle: const Text('Standard thermal receipt'),
              onTap: () {
                if (Navigator.canPop(context)) Navigator.pop(context);
                _printViaBluetooth(PaperSize.mm58);
              },
            ),

            const Divider(),

            // 80mm Option
            ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.green),
              title: const Text('80mm Paper'),
              subtitle: const Text('Wider format (Recommended)'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'RECOMMENDED',
                  style: TextStyle(fontSize: 9, color: Colors.white),
                ),
              ),
              onTap: () {
                if (Navigator.canPop(context)) Navigator.pop(context);
                _printViaBluetooth(PaperSize.mm80);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (Navigator.canPop(context)) Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  // ========================================
  // DIRECT BLUETOOTH THERMAL PRINTING
  // ========================================
  Future<void> _printViaBluetooth(PaperSize paperSize) async {
    setState(() => _exporting = true);

    try {
      final schoolName = _school?['name'] ?? "School Name";
      final schoolAddress = _school?['address'] ?? "";
      final studentClass = "${_student?['className'] ?? 'N/A'} - ${_student?['armName'] ?? 'N/A'}";

      // Prepare payments for thermal printer
      final payments = _payments.map((payment) {
        final rawDate = payment['paymentDate']?.toString() ?? '';
        String formattedDate = rawDate;
        try {
          final dt = DateTime.parse(rawDate);
          final d = dt.day.toString().padLeft(2, '0');
          final mo = dt.month.toString().padLeft(2, '0');
          final h = dt.hour.toString().padLeft(2, '0');
          final mi = dt.minute.toString().padLeft(2, '0');
          // Short date for same-line layout: DD/MM/YY HH:MM
          formattedDate = '$d/$mo/${dt.year.toString().substring(2)} $h:$mi';
        } catch (_) {}
        return {
          'date': formattedDate,
          'method': payment['method']?.toString() ?? 'Cash',
          'amount': (payment['amount'] as num?)?.toDouble() ?? 0.0,
          'paymentFor': payment['paymentFor']?.toString() ?? '',
        };
      }).toList();

      // Print via Bluetooth
      await ThermalPrinterManager.printPaymentHistory(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        studentName: widget.studentName,
        studentClass: studentClass,
        payments: payments,
        totalPaid: _totalPaid,
        totalBills: _grandTotal,
        outstanding: _outstanding,
        schoolPhone: _school?['phone']?.toString(),
        bankAccounts: _getBankAccounts(),
        paperSize: paperSize,
      );

      // Increment print counter
      await PrintCounterHelper.incrementPaymentHistoryPrinted();

      setState(() => _exporting = false);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment history printed successfully on ${paperSize == PaperSize.mm58 ? "58mm" : "80mm"} paper!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      setState(() => _exporting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Print failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // ========================================
  // USB PRINTER SIZE SELECTION DIALOG
  // ========================================
  Future<void> _showUsbPrinterSizeDialog() async {
    if (!UsbPrinterManager.isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect a USB printer first'), duration: Duration(seconds: 2)),
      );
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const UsbPrinterScreen()));
      if (!UsbPrinterManager.isConnected) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('USB printer not connected. Cancelled.'), backgroundColor: Colors.orange),
        );
        return;
      }
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(children: [Icon(Icons.usb, color: Colors.deepPurple), SizedBox(width: 8), Text('USB Print History')]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.orange),
              title: const Text('58mm Paper'),
              subtitle: const Text('Standard thermal receipt'),
              onTap: () { Navigator.pop(context); _printViaUsb(PaperSize.mm58); },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.green),
              title: const Text('80mm Paper'),
              subtitle: const Text('Wider format (Recommended)'),
              onTap: () { Navigator.pop(context); _printViaUsb(PaperSize.mm80); },
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
      ),
    );
  }

  // ========================================
  // DIRECT USB PRINTING
  // ========================================
  Future<void> _printViaUsb(PaperSize paperSize) async {
    setState(() => _exporting = true);

    try {
      final schoolName = _school?['name'] ?? "School Name";
      final schoolAddress = _school?['address'] ?? "";
      final studentClass = "${_student?['className'] ?? 'N/A'} - ${_student?['armName'] ?? 'N/A'}";

      final payments = _payments.map((payment) {
        final rawDate = payment['paymentDate']?.toString() ?? '';
        String formattedDate = rawDate;
        try {
          final dt = DateTime.parse(rawDate);
          final d = dt.day.toString().padLeft(2, '0');
          final mo = dt.month.toString().padLeft(2, '0');
          final h = dt.hour.toString().padLeft(2, '0');
          final mi = dt.minute.toString().padLeft(2, '0');
          formattedDate = '$d/$mo/${dt.year.toString().substring(2)} $h:$mi';
        } catch (_) {}
        return {
          'date': formattedDate,
          'method': payment['method']?.toString() ?? 'Cash',
          'amount': (payment['amount'] as num?)?.toDouble() ?? 0.0,
          'paymentFor': payment['paymentFor']?.toString() ?? '',
        };
      }).toList();

      await UsbPrinterManager.printPaymentHistory(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        studentName: widget.studentName,
        studentClass: studentClass,
        payments: payments,
        totalPaid: _totalPaid,
        totalBills: _grandTotal,
        outstanding: _outstanding,
        schoolPhone: _school?['phone']?.toString(),
        bankAccounts: _getBankAccounts(),
        paperSize: paperSize,
      );

      await PrintCounterHelper.incrementPaymentHistoryPrinted();

      setState(() => _exporting = false);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment history printed via USB on ${paperSize == PaperSize.mm58 ? "58mm" : "80mm"} paper!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      setState(() => _exporting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('USB print failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Widget _buildSizeOption({
    required PrinterSize size,
    required bool isRecommended,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isRecommended ? Colors.orange : Colors.grey.shade300,
            width: isRecommended ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isRecommended ? Colors.orange.shade50 : null,
        ),
        child: Row(
          children: [
            Icon(
              Icons.receipt_long,
              color: isRecommended ? Colors.orange : Colors.grey,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        size.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isRecommended ? Colors.orange.shade900 : Colors.black,
                        ),
                      ),
                      if (isRecommended) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'STANDARD',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    PrinterSettingsHelper.getSizeDescription(size.name),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  // ========================================
  // EXPORT AS PDF (A4 Format)
  // ========================================
  Future<void> _exportAsPDF() async {
    setState(() => _exporting = true);

    try {
      final pdf = pw.Document();
      
      final schoolName = _school?['name'] ?? "School Name";
      final schoolAddress = _school?['address'] ?? "";
      final schoolPhone = _school?['phone'] ?? "";
      final studentClass = "${_student?['className'] ?? 'N/A'} - ${_student?['armName'] ?? 'N/A'}";
      final admissionNo = _student?['admissionNo'] ?? 'N/A';

      // A4 FORMAT
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      schoolName.toUpperCase(),
                      style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                    ),
                    if (schoolAddress.isNotEmpty) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(schoolAddress, style: const pw.TextStyle(fontSize: 12)),
                    ],
                    if (schoolPhone.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(schoolPhone, style: const pw.TextStyle(fontSize: 12)),
                    ],
                  ],
                ),
              ),

              pw.SizedBox(height: 30),
              pw.Divider(thickness: 2),
              pw.SizedBox(height: 20),

              // Title
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'PAYMENT HISTORY',
                      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      '$_activeTerm - $_activeSession',
                      style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 30),

              // Student Info
              pw.Container(
                padding: const pw.EdgeInsets.all(15),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildPdfRow('Student Name:', widget.studentName),
                    pw.SizedBox(height: 8),
                    _buildPdfRow('Class:', studentClass),
                    pw.SizedBox(height: 8),
                    _buildPdfRow('Admission No:', admissionNo),
                  ],
                ),
              ),

              pw.SizedBox(height: 20),

              // Payment List Header
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Date', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Method', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Amount', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),

              // Payment List
              ...(_payments.isEmpty
                  ? [
                      pw.Container(
                        padding: const pw.EdgeInsets.all(20),
                        child: pw.Center(
                          child: pw.Text(
                            'No payments recorded yet',
                            style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
                          ),
                        ),
                      ),
                    ]
                  : _payments.map((payment) {
                      final amount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
                      final dateStr = payment['paymentDate']?.toString() ?? "";
                      final parsedDate = DateTime.tryParse(dateStr) ?? DateTime.now();
                      final formattedDate = DateFormat("dd/MM/yyyy").format(parsedDate);
                      final method = payment['method']?.toString() ?? "";
                      final paymentFor = payment['paymentFor']?.toString() ?? "";

                      return pw.Container(
                        padding: const pw.EdgeInsets.all(10),
                        decoration: pw.BoxDecoration(
                          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300)),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text(formattedDate, style: const pw.TextStyle(fontSize: 12)),
                                pw.Text(method, style: const pw.TextStyle(fontSize: 12)),
                                pw.Text(
                                  'N ${NumberFormat("#,##0.00").format(amount)}',
                                  style: const pw.TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                            if (paymentFor.isNotEmpty)
                              pw.Padding(
                                padding: const pw.EdgeInsets.only(top: 3),
                                child: pw.Text(
                                  'For: $paymentFor',
                                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList()),

              pw.SizedBox(height: 30),

              // Total Paid - Green themed
              pw.Center(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(25),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.green50,
                    border: pw.Border.all(width: 2, color: PdfColors.green),
                    borderRadius: pw.BorderRadius.circular(12),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'TOTAL PAID',
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.green900,
                        ),
                      ),
                      pw.SizedBox(height: 15),
                      pw.Text(
                        'N ${NumberFormat("#,##0.00").format(_totalPaid)}',
                        style: pw.TextStyle(
                          fontSize: 36,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.green900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              pw.SizedBox(height: 30),

              // Financial Summary
              pw.Container(
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border.all(width: 1.5, color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Column(
                  children: [
                    pw.Center(
                      child: pw.Text(
                        'FINANCIAL SUMMARY',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey800,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 15),
                    _buildPdfRow(
                      'Total Bills (Term):',
                      'N ${NumberFormat("#,##0.00").format(_grandTotal)}',
                      bold: true,
                      fontSize: 15,
                    ),
                    pw.SizedBox(height: 10),
                    _buildPdfRow(
                      'Total Paid (Term):',
                      'N ${NumberFormat("#,##0.00").format(_totalPaid)}',
                      bold: true,
                      fontSize: 15,
                    ),
                    pw.SizedBox(height: 10),
                    pw.Divider(thickness: 2, color: PdfColors.grey600),
                    pw.SizedBox(height: 10),
                    _buildPdfRow(
                      'Outstanding Balance:',
                      'N ${NumberFormat("#,##0.00").format(_outstanding)}',
                      bold: true,
                      fontSize: 18,
                    ),
                    pw.SizedBox(height: 15),
                    pw.Center(
                      child: pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 10,
                        ),
                        decoration: pw.BoxDecoration(
                          color: _outstanding <= 0
                              ? PdfColors.green100
                              : PdfColors.orange100,
                          borderRadius: pw.BorderRadius.circular(8),
                          border: pw.Border.all(
                            color: _outstanding <= 0
                                ? PdfColors.green800
                                : PdfColors.orange800,
                            width: 2,
                          ),
                        ),
                        child: pw.Text(
                          _outstanding <= 0 ? 'BALANCED' : 'YET TO BALANCE',
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: _outstanding <= 0
                                ? PdfColors.green900
                                : PdfColors.orange900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              pw.Spacer(),

              // Bank details
              _buildBankDetailsPdf(),

              // Footer
              pw.Divider(),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'Payment history for $_activeTerm - $_activeSession',
                      style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Generated: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

      // Save and share PDF
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'PaymentHistory_${widget.studentName}_PDF.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      setState(() => _exporting = false);

      if (!mounted) return;

      // Share immediately
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Payment History - ${widget.studentName}',
        text: 'Payment history for $_activeTerm - $_activeSession',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF saved and shared: $fileName'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() => _exporting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF export failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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

  pw.Widget _buildBankDetailsPdf() {
    final accounts = _getBankAccounts();
    if (accounts.isEmpty) return pw.SizedBox();
    return pw.Column(
      children: [
        pw.SizedBox(height: 20),
        pw.Text('BANK DETAILS', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        ...accounts.map((acc) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Text(
            '${acc['bankName']} - ${acc['accountNumber']} - ${acc['accountName']}',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 11),
          ),
        )),
      ],
    );
  }

  pw.Widget _buildPdfRow(String label, String value, {bool bold = false, double fontSize = 14}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    );
  }

  // ========================================
  // EXPORT AS JPEG
  // ========================================
  Future<void> _exportAsJPEG() async {
    setState(() => _exporting = true);

    try {
      // Capture the history widget as image
      final RenderRepaintBoundary boundary = _historyKey.currentContext!
          .findRenderObject() as RenderRepaintBoundary;
      
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      // Save as JPEG
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'PaymentHistory_${widget.studentName}_IMAGE.jpg';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(pngBytes);

      setState(() => _exporting = false);

      if (!mounted) return;

      // Share immediately
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Payment History - ${widget.studentName}',
        text: 'Payment history for $_activeTerm - $_activeSession',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Image saved and shared: $fileName'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() => _exporting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Image export failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ========================================
  // UI BUILD
  // ========================================
  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment History'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          if (!_loading && !_exporting && _outstanding > 0)
            IconButton(
              icon: const Icon(Icons.mail_outline),
              onPressed: _openDebtNotification,
              tooltip: 'Debt Notification Letter',
            ),
          if (!_loading && !_exporting)
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: _showExportOptionsDialog,
              tooltip: 'Export & Share',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _exporting
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Exporting...'),
                    ],
                  ),
                )
              : RepaintBoundary(
                  key: _historyKey,
                  child: Container(
                    color: Colors.white,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(ds.cardPadding),
                      child: _buildContent(ds),
                    ),
                  ),
                ),
    );
  }

  Widget _buildContent(DisplaySettings ds) {
    final className = _student?['className'] ?? "";
    final armName = _student?['armName'] ?? "";
    final admissionNo = _student?['admissionNo'] ?? "";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // School Header
        Center(
          child: Column(
            children: [
              Text(
                (_school?['name'] ?? "School Name").toUpperCase(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              if ((_school?['address'] ?? "").isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _school?['address'] ?? "",
                  style: const TextStyle(fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
              if ((_school?['phone'] ?? "").isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  _school?['phone'] ?? "",
                  style: const TextStyle(fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 20),
        const Divider(thickness: 2),
        const SizedBox(height: 20),

        // Title
        Center(
          child: Column(
            children: [
              const Text(
                'PAYMENT HISTORY',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$_activeTerm - $_activeSession',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Student Info
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              _buildRow('Student:', widget.studentName),
              const SizedBox(height: 8),
              _buildRow('Class:', '$className - $armName'),
              const SizedBox(height: 8),
              _buildRow('Admission No:', admissionNo),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Payment List Header
        Container(
          padding: const EdgeInsets.all(10),
          color: Colors.grey.shade200,
          child: Row(
            children: [
              const Expanded(
                flex: 2,
                child: Text('Date', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const Expanded(
                flex: 2,
                child: Text('Method', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'Amount',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  textAlign: _canEditPayments ? TextAlign.left : TextAlign.right,
                ),
              ),
              // Space for edit and delete button columns
              if (_canEditPayments)
                const SizedBox(width: 96), // Space for 2 IconButtons
            ],
          ),
        ),

        // Payment List
        if (_payments.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: Text(
                'No payments recorded yet',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ),
          )
        else
          ..._payments.map((payment) {
            final amount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
            final rawDate = payment['paymentDate']?.toString();
            final formattedDate = formatPaymentDateOnly(rawDate);
            final formattedTime = formatPaymentTimeOnly(rawDate);
            final method = payment['method']?.toString() ?? "";
            final paymentFor = payment['paymentFor']?.toString() ?? "";

            return Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Date + Time
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(formattedDate, style: const TextStyle(fontSize: 14)),
                            if (formattedTime.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 2),
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
                                      formattedTime,
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
                        ),
                      ),
                      // Method
                      Expanded(
                        flex: 2,
                        child: Text(method, style: const TextStyle(fontSize: 14)),
                      ),
                      // Amount
                      Expanded(
                        flex: 3,
                        child: Text(
                          'N${NumberFormat("#,##0.00").format(amount)}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          textAlign: _canEditPayments ? TextAlign.left : TextAlign.right,
                        ),
                      ),
                      // Edit and Delete buttons (only for users with payments_edit permission)
                      if (_canEditPayments) ...[
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20, color: Colors.orange),
                          onPressed: () => _showEditPaymentDialog(payment),
                          tooltip: 'Edit Payment',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                          onPressed: () => _showDeletePaymentDialog(payment),
                          tooltip: 'Delete Payment',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ],
                  ),
                  if (paymentFor.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        'For: $paymentFor',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ),
                  if (_lastEditByPaymentId.containsKey(payment['id']))
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: InkWell(
                        onTap: () => _showAuditDiffDialog(
                          _lastEditByPaymentId[payment['id']]!,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit_note, size: 14, color: Colors.orange.shade700),
                            const SizedBox(width: 3),
                            Text(
                              'Edited by ${_lastEditByPaymentId[payment['id']]!['username'] ?? 'Unknown'}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange.shade700,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),

        const SizedBox(height: 20),

        // Summary
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              // Previous Balance
              if (_previousBalance > 0) ...[
                _buildRow(
                  'Previous Balance:',
                  'N${NumberFormat("#,##0.00").format(_previousBalance)}',
                  bold: true,
                  color: Colors.orange,
                ),
                const SizedBox(height: 8),
              ],
              // Current Term Fees
              _buildRow(
                'Current Term Fees:',
                'N${NumberFormat("#,##0.00").format(_currentTermBill)}',
                bold: true,
              ),
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
              // Grand Total
              _buildRow(
                'Grand Total:',
                'N${NumberFormat("#,##0.00").format(_grandTotal)}',
                bold: true,
                color: Colors.purple,
              ),
              const SizedBox(height: 8),
              _buildRow(
                'Total Paid:',
                'N${NumberFormat("#,##0.00").format(_totalPaid)}',
                bold: true,
                color: Colors.green,
              ),
              const Divider(thickness: 2),
              const SizedBox(height: 8),
              _buildRow(
                'Outstanding Balance:',
                'N${NumberFormat("#,##0.00").format(_outstanding)}',
                bold: true,
                color: _outstanding > 0 ? Colors.red : Colors.green,
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 10),

        // Footer
        Center(
          child: Column(
            children: [
              const Text(
                'Payment history for current term',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Generated: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 30),

        // Large Export Button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: _exporting ? null : _showExportOptionsDialog,
            icon: _exporting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.share, size: 28),
            label: Text(
              _exporting ? 'Exporting...' : 'Export & Share History',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
            ),
          ),
        ),

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildRow(String label, String value, {bool bold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 14,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}