// lib/utils/student_bill_actions.dart
//
// Bill/payment actions for a single student — send SMS, compare with another
// term, and print the statement (PDF / JPEG / thermal / USB). Shared by the
// "Bills & Payments" card on the student details screen and the per-student
// cards on the Class Bills screen so both behave identically.

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import '../data/database_helper_wrapper.dart';
import '../screens/settings/thermal_printer_screen.dart';
import '../screens/settings/usb_printer_screen.dart';
import 'navigation_helper.dart';
import 'payment_date_time_formatter.dart';
import 'print_counter_helper.dart';
import 'sms_service.dart';
import 'thermal_printer_manager.dart';
import 'usb_printer_manager.dart';

/// Everything the bill actions need about one student's bill for the active term.
class StudentBillSnapshot {
  final int studentId;
  final String surname;
  final String firstName;
  final String? otherName;
  final String? className;
  final String? armName;
  final String admissionNo;
  final String parentPhone;

  final String term;
  final String session;
  final double previousBalance;
  final double currentTermBill;
  final double grandTotal;
  final double totalPaid;
  final double outstanding;
  final List<Map<String, dynamic>> billItems;
  final List<Map<String, dynamic>> payments;
  final Map<String, dynamic>? school;

  const StudentBillSnapshot({
    required this.studentId,
    required this.surname,
    required this.firstName,
    this.otherName,
    this.className,
    this.armName,
    required this.admissionNo,
    required this.parentPhone,
    required this.term,
    required this.session,
    required this.previousBalance,
    required this.currentTermBill,
    required this.grandTotal,
    required this.totalPaid,
    required this.outstanding,
    required this.billItems,
    required this.payments,
    required this.school,
  });

  List<Map<String, dynamic>> get bankAccounts {
    if (school == null) return [];
    final accounts = <Map<String, dynamic>>[];
    for (int i = 1; i <= 3; i++) {
      final bankName = school!['bankName$i']?.toString() ?? '';
      final accNum = school!['accountNumber$i']?.toString() ?? '';
      final accName = school!['accountName$i']?.toString() ?? '';
      if (bankName.isNotEmpty && accNum.isNotEmpty) {
        accounts.add({'bankName': bankName, 'accountNumber': accNum, 'accountName': accName});
      }
    }
    return accounts;
  }
}

class StudentBillActions {
  /// Loads a student's bill data for the active term/session, the same way the
  /// student details screen does. Returns null when the student can't be found
  /// or there is no active term/session.
  static Future<StudentBillSnapshot?> load(int studentId) async {
    final dbHelper = DatabaseHelperWrapper();
    final db = await dbHelper.database;

    final studentRows = await db.rawQuery('''
      SELECT s.id, s.surname, s.firstName, s.otherName, s.admissionNo, s.parentPhone,
             c.name as className, a.name as armName
      FROM students s
      LEFT JOIN classes c ON s.classId = c.id
      LEFT JOIN arms a ON s.armId = a.id
      WHERE s.id = ?
    ''', [studentId]);
    if (studentRows.isEmpty) return null;
    final s = studentRows.first;

    final term = await dbHelper.getActiveTerm();
    final session = (await dbHelper.getActiveSession())?['sessionName']?.toString() ?? '';
    if (term.isEmpty || session.isEmpty) return null;

    final school = await dbHelper.getSchoolProfile();

    final previousBalance = await dbHelper.computeOutstandingBeforeTerm(
      studentId,
      term: term,
      session: session,
    );

    final bill = await dbHelper.getBillForStudent(studentId, term, session);
    double currentTermBill = 0;
    var billItems = <Map<String, dynamic>>[];
    if (bill != null) {
      final storedTotal = (bill['totalAmount'] as num?)?.toDouble() ?? 0.0;
      final storedPrevBalance = (bill['previousBalance'] as num?)?.toDouble() ?? 0.0;
      currentTermBill = storedTotal - storedPrevBalance;

      final items = await db.rawQuery('''
        SELECT sfb.id, sfb.billId, sfb.feeItemId, sfb.amount,
               COALESCE(NULLIF(TRIM(sfb.label), ''), fi.name, 'Fee Item') as feeName
        FROM student_fee_breakdown sfb
        LEFT JOIN fee_items fi ON sfb.feeItemId = fi.id
        WHERE sfb.billId = ?
        ORDER BY sfb.id ASC
      ''', [bill['id']]);
      billItems = items.map((item) => Map<String, dynamic>.from(item)).toList();
    }

    final paidRows = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) as totalPaid
      FROM payments
      WHERE studentId = ? AND term = ? AND session = ?
    ''', [studentId, term, session]);
    final totalPaid = (paidRows.first['totalPaid'] as num?)?.toDouble() ?? 0.0;

    final paymentRows = await db.rawQuery('''
      SELECT id, amount, method, note, paymentDate
      FROM payments
      WHERE studentId = ? AND term = ? AND session = ?
      ORDER BY paymentDate DESC
    ''', [studentId, term, session]);

    final grandTotal = previousBalance + currentTermBill;
    return StudentBillSnapshot(
      studentId: studentId,
      surname: s['surname'] as String? ?? '',
      firstName: s['firstName'] as String? ?? '',
      otherName: s['otherName'] as String?,
      className: s['className'] as String?,
      armName: s['armName'] as String?,
      admissionNo: s['admissionNo']?.toString() ?? '',
      parentPhone: s['parentPhone']?.toString() ?? '',
      term: term,
      session: session,
      previousBalance: previousBalance,
      currentTermBill: currentTermBill,
      grandTotal: grandTotal,
      totalPaid: totalPaid,
      outstanding: grandTotal - totalPaid,
      billItems: billItems,
      payments: paymentRows.map((p) => Map<String, dynamic>.from(p)).toList(),
      school: school,
    );
  }

  static Future<void> sendSms(BuildContext context, StudentBillSnapshot b) async {
    if (b.term.isEmpty || b.session.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill data is not loaded yet')),
      );
      return;
    }

    final studentName = "${b.surname} ${b.firstName}".trim();
    final message = buildBillSummarySms(
      schoolName: b.school?['name']?.toString() ?? 'the school',
      studentName: studentName,
      grandTotal: b.grandTotal,
      totalPaid: b.totalPaid,
      outstanding: b.outstanding,
      term: b.term,
      session: b.session,
      bankAccounts: b.bankAccounts,
    );

    final result = await SmsService.send(
      rawPhone: b.parentPhone,
      message: message,
      studentId: b.studentId,
      context: 'student_bill',
    );

    if (context.mounted) {
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

  static List<pw.Widget> _buildBankDetailsPdf(StudentBillSnapshot b) {
    final bankAccounts = b.bankAccounts;
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

  static void showPrintOptions(
    BuildContext context,
    StudentBillSnapshot b, {
    GlobalKey? captureKey,
    Map<String, dynamic>? currentUser,
  }) {
    final formatter = NumberFormat('#,##0.00');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
              '${b.surname} ${b.firstName}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              '$b.term - $b.session',
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
                      Text('₦${formatter.format(b.grandTotal)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Paid:'),
                      Text('₦${formatter.format(b.totalPaid)}', style: TextStyle(color: Colors.green.shade700)),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(b.outstanding >= 0 ? 'Outstanding:' : 'Overpayment:'),
                      Text(
                        '₦${formatter.format(b.outstanding.abs())}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: b.outstanding > 0 ? Colors.red.shade700 : Colors.green.shade700,
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
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _printBillAsJPEG(context, b, captureKey);
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
              Navigator.pop(dialogContext);
              _printBillAsPDF(context, b);
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
              Navigator.pop(dialogContext);
              _printBillThermal(context, b, currentUser);
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
              Navigator.pop(dialogContext);
              _printBillViaUsb(context, b);
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

  static Future<void> _printBillAsPDF(BuildContext context, StudentBillSnapshot b) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final pdf = pw.Document();
      final formatter = NumberFormat('#,##0.00');
      final studentName = '${b.surname} ${b.firstName} ${b.otherName ?? ''}'.trim();
      final className = b.className ?? 'N/A';
      final armName = b.armName;
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
                  b.school?['name']?.toString().toUpperCase() ?? 'SCHOOL NAME',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.teal700),
                ),
              ),
              pw.SizedBox(height: 5),
              if (b.school?['address'] != null)
                pw.Center(
                  child: pw.Text(
                    b.school!['address'].toString(),
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
                  '$b.term - $b.session',
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
                        pw.Text('Adm No: ${b.admissionNo}'),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text('Class: $classDisplay', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Bill Items Table
              if (b.billItems.isNotEmpty) ...[
                pw.Text('Bill Breakdown', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                pw.SizedBox(height: 8),
                pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.teal100),
                  cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight},
                  data: [
                    ['Fee Item', 'Amount'],
                    ...b.billItems.map((item) => [
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
                        pw.Text('N${formatter.format(b.currentTermBill)}'),
                      ],
                    ),
                    if (b.previousBalance != 0)
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(b.previousBalance > 0 ? 'Previous Balance:' : 'Previous Credit:', style: const pw.TextStyle(fontSize: 11)),
                          pw.Text('N${formatter.format(b.previousBalance.abs())}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: b.previousBalance > 0 ? PdfColors.orange700 : PdfColors.green700)),
                        ],
                      ),
                    pw.Divider(),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Grand Total:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                        pw.Text('N${formatter.format(b.grandTotal)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.purple700)),
                      ],
                    ),
                    pw.SizedBox(height: 5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Total Paid:', style: const pw.TextStyle(fontSize: 11)),
                        pw.Text('N${formatter.format(b.totalPaid)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.green700)),
                      ],
                    ),
                    pw.Divider(thickness: 1.5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(b.outstanding >= 0 ? 'OUTSTANDING:' : 'OVERPAYMENT:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                        pw.Text(
                          'N${formatter.format(b.outstanding.abs())}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13, color: b.outstanding > 0 ? PdfColors.red700 : PdfColors.green700),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Payments Table
              if (b.payments.isNotEmpty) ...[
                pw.Text('Payment History', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                pw.SizedBox(height: 8),
                pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.green100),
                  cellAlignments: {0: pw.Alignment.center, 1: pw.Alignment.centerRight, 2: pw.Alignment.center, 3: pw.Alignment.center},
                  data: [
                    ['S/N', 'Amount', 'Method', 'Date', 'Receipt'],
                    ...b.payments.asMap().entries.map((entry) {
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
              ..._buildBankDetailsPdf(b),

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
      final file = File('${dir.path}/bill_${b.surname}_${b.firstName}_$dateStr.pdf');
      await file.writeAsBytes(await pdf.save());

      if (!context.mounted) return;
      Navigator.pop(context);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Bill Statement - ${b.surname} ${b.firstName}',
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill PDF generated successfully!')),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e')),
      );
    }
  }

  static Future<void> _printBillAsJPEG(
    BuildContext context,
    StudentBillSnapshot b,
    GlobalKey? captureKey,
  ) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      // Capture the bill card as an image
      final boundary = captureKey?.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (!context.mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not capture bill card')),
        );
        return;
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        if (!context.mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not generate image')),
        );
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File('${dir.path}/bill_${b.surname}_${b.firstName}_$dateStr.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      if (!context.mounted) return;
      Navigator.pop(context);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Bill Statement - ${b.surname} ${b.firstName}',
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill image generated successfully!')),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating image: $e')),
      );
    }
  }

  static Future<void> _printBillThermal(
    BuildContext context,
    StudentBillSnapshot b,
    Map<String, dynamic>? currentUser,
  ) async {
    if (!ThermalPrinterManager.isConnected) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please connect to a thermal printer first'),
          duration: Duration(seconds: 2),
        ),
      );

      await NavigationHelper.pushWithSidebar(
        context,
        page: const ThermalPrinterScreen(),
        currentUser: currentUser ?? {},
        pageId: 'student_management/students',
      );

      if (!ThermalPrinterManager.isConnected) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Printer not connected. Printing cancelled.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    if (!context.mounted) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final schoolName = b.school?['name'] ?? 'School Name';
      final schoolAddress = b.school?['address'] ?? '';
      final studentName = '${b.surname} ${b.firstName}'.trim();
      final className = b.className ?? 'N/A';
      final armName = b.armName;
      final classDisplay = armName != null && armName.isNotEmpty ? '$className - $armName' : className;

      // Build fee items for thermal print
      final List<Map<String, dynamic>> feeItems = [];
      for (final item in b.billItems) {
        feeItems.add(<String, dynamic>{
          'name': item['feeName']?.toString() ?? 'Fee',
          'amount': (item['amount'] as num?)?.toDouble() ?? 0.0,
        });
      }

      // Add previous balance (or credit, shown as a negative deduction) if any
      if (b.previousBalance != 0) {
        feeItems.insert(0, <String, dynamic>{
          'name': b.previousBalance > 0 ? 'Previous Balance' : 'Previous Credit',
          'amount': b.previousBalance,
        });
      }

      final paperSize = await ThermalPrinterManager.getPrinterPaperSizeEnum(
        ThermalPrinterManager.connectedPrinter!.remoteId.toString(),
      );

      await ThermalPrinterManager.printBill(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        schoolPhone: b.school?['phone']?.toString(),
        bankAccounts: b.bankAccounts,
        studentName: studentName,
        studentClass: classDisplay,
        term: '$b.term $b.session',
        feeItems: feeItems,
        total: b.grandTotal,
        totalPaid: b.totalPaid,
        outstanding: b.outstanding,
        billDate: DateFormat('yyyy-MM-dd').format(DateTime.now()),
        paperSize: paperSize,
      );
      await PrintCounterHelper.incrementBillsPrinted();

      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill printed successfully!')),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error printing: $e')),
      );
    }
  }

  static Future<void> _printBillViaUsb(BuildContext context, StudentBillSnapshot b) async {
    if (!UsbPrinterManager.isConnected) {
      if (!context.mounted) return;
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
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No USB printer connected. Printing cancelled.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    if (!context.mounted) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final schoolName = b.school?['name'] ?? 'School Name';
      final schoolAddress = b.school?['address'] ?? '';
      final studentName = '${b.surname} ${b.firstName}'.trim();
      final className = b.className ?? 'N/A';
      final armName = b.armName;
      final classDisplay = armName != null && armName.isNotEmpty
          ? '$className - $armName'
          : className;

      final List<Map<String, dynamic>> feeItems = [];
      if (b.previousBalance != 0) {
        feeItems.add({
          'name': b.previousBalance > 0 ? 'Previous Balance' : 'Previous Credit',
          'amount': b.previousBalance,
        });
      }
      for (final item in b.billItems) {
        feeItems.add({
          'name': item['feeName']?.toString() ?? 'Fee',
          'amount': (item['amount'] as num?)?.toDouble() ?? 0.0,
        });
      }

      final paperSize = await UsbPrinterManager.getPaperSize();

      await UsbPrinterManager.printBill(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        schoolPhone: b.school?['phone']?.toString(),
        bankAccounts: b.bankAccounts,
        studentName: studentName,
        studentClass: classDisplay,
        term: '$b.term $b.session',
        feeItems: feeItems,
        total: b.grandTotal,
        totalPaid: b.totalPaid,
        outstanding: b.outstanding,
        billDate: DateFormat('yyyy-MM-dd').format(DateTime.now()),
        paperSize: paperSize == 'mm58' ? PaperSize.mm58 : PaperSize.mm80,
      );
      await PrintCounterHelper.incrementBillsPrinted();

      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill printed via USB successfully!')),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('USB print error: $e')),
      );
    }
  }

  static const List<String> _comparableTerms = ['1st Term', '2nd Term', '3rd Term'];

  // Fetches the bill/payment summary for an arbitrary term+session so the
  // Term Comparison sheet's "Compare with" filter can target any period,
  // not just the one immediately before the active term.
  static Future<Map<String, dynamic>> _fetchTermBillSummary(
    StudentBillSnapshot b,
    String term,
    String session,
  ) async {
    final dbHelper = DatabaseHelperWrapper();
    final db = await dbHelper.database;

    final bill = await dbHelper.getBillForStudent(b.studentId, term, session);

    double termBill = 0;
    List<Map<String, dynamic>> billItems = [];

    if (bill != null) {
      final storedTotal = (bill['totalAmount'] as num?)?.toDouble() ?? 0.0;
      final storedPrevBal = (bill['previousBalance'] as num?)?.toDouble() ?? 0.0;
      termBill = storedTotal - storedPrevBal;

      final items = await db.rawQuery('''
        SELECT sfb.id, sfb.feeItemId, sfb.amount,
               COALESCE(NULLIF(TRIM(sfb.label), ''), fi.name, 'Fee Item') as feeName
        FROM student_fee_breakdown sfb
        LEFT JOIN fee_items fi ON sfb.feeItemId = fi.id
        WHERE sfb.billId = ?
        ORDER BY sfb.id ASC
      ''', [bill['id']]);
      billItems = items.map((e) => Map<String, dynamic>.from(e)).toList();
    }

    final paymentsSum = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) as totalPaid
      FROM payments WHERE studentId = ? AND term = ? AND session = ?
    ''', [b.studentId, term, session]);
    final totalPaid = (paymentsSum.first['totalPaid'] as num?)?.toDouble() ?? 0.0;

    final previousBalance = (await dbHelper.computeOutstandingBeforeTerm(
      b.studentId,
      term: term,
      session: session,
    )).clamp(0.0, double.infinity);
    final grandTotal = previousBalance + termBill;
    final outstanding = grandTotal - totalPaid;

    final paymentsList = await db.rawQuery('''
      SELECT id, amount, method, note, paymentDate
      FROM payments WHERE studentId = ? AND term = ? AND session = ?
      ORDER BY paymentDate DESC
    ''', [b.studentId, term, session]);
    final payments = paymentsList.map((p) => Map<String, dynamic>.from(p)).toList();

    return {
      'previousBalance': previousBalance,
      'termBill': termBill,
      'grandTotal': grandTotal,
      'totalPaid': totalPaid,
      'outstanding': outstanding,
      'billItems': billItems,
      'payments': payments,
    };
  }

  static Future<void> showTermComparison(BuildContext context, StudentBillSnapshot b) async {
    final prevTermSession = DatabaseHelperWrapper.previousTermSession(
      term: b.term,
      session: b.session,
    );

    if (prevTermSession == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No previous term data available')),
      );
      return;
    }

    final prevTerm = prevTermSession['term']!;
    final prevSession = prevTermSession['session']!;

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final dbHelper = DatabaseHelperWrapper();

      final sessions = await dbHelper.getAllSessions();
      final availableSessions = sessions
          .map((s) => s['sessionName']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      for (final s in [prevSession, b.session]) {
        if (!availableSessions.contains(s)) availableSessions.add(s);
      }

      final compareData = await _fetchTermBillSummary(b, prevTerm, prevSession);

      if (!context.mounted) return;
      Navigator.pop(context);

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => _TermComparisonSheet(
          studentName: '${b.surname} ${b.firstName}',
          currentTerm: b.term,
          currentSession: b.session,
          currentPreviousBalance: b.previousBalance,
          currentTermBill: b.currentTermBill,
          currentGrandTotal: b.grandTotal,
          currentTotalPaid: b.totalPaid,
          currentOutstanding: b.outstanding,
          initialCompareTerm: prevTerm,
          initialCompareSession: prevSession,
          initialCompareData: compareData,
          availableTerms: _comparableTerms,
          availableSessions: availableSessions,
          onFetchCompareData: (t, s) => _fetchTermBillSummary(b, t, s),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading previous term data: $e')),
      );
    }
  }

}

// ---------------------------------------------------------------------------
// Previous Term Bill Comparison Sheet
// ---------------------------------------------------------------------------

class _TermComparisonSheet extends StatefulWidget {
  final String studentName;

  final String currentTerm;
  final String currentSession;
  final double currentPreviousBalance;
  final double currentTermBill;
  final double currentGrandTotal;
  final double currentTotalPaid;
  final double currentOutstanding;

  final String initialCompareTerm;
  final String initialCompareSession;
  final Map<String, dynamic> initialCompareData;

  final List<String> availableTerms;
  final List<String> availableSessions;
  final Future<Map<String, dynamic>> Function(String term, String session) onFetchCompareData;

  const _TermComparisonSheet({
    required this.studentName,
    required this.currentTerm,
    required this.currentSession,
    required this.currentPreviousBalance,
    required this.currentTermBill,
    required this.currentGrandTotal,
    required this.currentTotalPaid,
    required this.currentOutstanding,
    required this.initialCompareTerm,
    required this.initialCompareSession,
    required this.initialCompareData,
    required this.availableTerms,
    required this.availableSessions,
    required this.onFetchCompareData,
  });

  @override
  State<_TermComparisonSheet> createState() => _TermComparisonSheetState();
}

class _TermComparisonSheetState extends State<_TermComparisonSheet> {
  late String _compareTerm = widget.initialCompareTerm;
  late String _compareSession = widget.initialCompareSession;
  late Map<String, dynamic> _compareData = widget.initialCompareData;
  bool _loading = false;
  String? _error;

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.onFetchCompareData(_compareTerm, _compareSession);
      if (!mounted) return;
      setState(() {
        _compareData = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Error loading $_compareTerm · $_compareSession: $e';
      });
    }
  }

  void _onCompareSessionChanged(String? session) {
    if (session == null || session == _compareSession) return;
    setState(() => _compareSession = session);
    _reload();
  }

  void _onCompareTermChanged(String? term) {
    if (term == null || term == _compareTerm) return;
    setState(() => _compareTerm = term);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');

    final prevTerm = _compareTerm;
    final prevSession = _compareSession;
    final prevPreviousBalance = (_compareData['previousBalance'] as num).toDouble();
    final prevCurrentTermBill = (_compareData['termBill'] as num).toDouble();
    final prevGrandTotal = (_compareData['grandTotal'] as num).toDouble();
    final prevTotalPaid = (_compareData['totalPaid'] as num).toDouble();
    final prevOutstanding = (_compareData['outstanding'] as num).toDouble();
    final prevBillItems = List<Map<String, dynamic>>.from(_compareData['billItems'] as List);
    final prevPayments = List<Map<String, dynamic>>.from(_compareData['payments'] as List);
    final currentTerm = widget.currentTerm;
    final currentSession = widget.currentSession;
    final currentPreviousBalance = widget.currentPreviousBalance;
    final currentTermBill = widget.currentTermBill;
    final currentGrandTotal = widget.currentGrandTotal;
    final currentTotalPaid = widget.currentTotalPaid;
    final currentOutstanding = widget.currentOutstanding;

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
                        widget.studentName,
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

          // Compare-with filter — defaults to the last term/session
          Container(
            color: Colors.grey.shade50,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(
              children: [
                Icon(Icons.filter_alt_outlined, size: 15, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _compareSession,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Compare Session',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                    items: widget.availableSessions
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: _loading ? null : _onCompareSessionChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _compareTerm,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Compare Term',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                    items: widget.availableTerms
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: _loading ? null : _onCompareTermChanged,
                  ),
                ),
                if (_loading) ...[
                  const SizedBox(width: 10),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ),

          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
              children: [
                if (_error != null) ...[
                  _EmptyState(message: _error!),
                  const SizedBox(height: 16),
                ],
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