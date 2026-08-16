// lib/screens/billing/bill_print_screen.dart
// UPDATED VERSION with 3 Export Options (PDF, JPEG, Thermal)

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../data/database_helper_wrapper.dart';
import '../../utils/printer_settings_helper.dart';  // NEW IMPORT
import '../../utils/thermal_printer_manager.dart';
import '../../utils/print_counter_helper.dart';
import '../../screens/settings/thermal_printer_screen.dart';
import '../../screens/settings/usb_printer_screen.dart';
import '../../utils/usb_printer_manager.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

class BillPrintScreen extends StatefulWidget {
  final int billId;
  final int studentId;
  final String studentName;
  final String term;
  final String session;

  const BillPrintScreen({
    super.key,
    required this.billId,
    required this.studentId,
    required this.studentName,
    required this.term,
    required this.session,
  });

  @override
  State<BillPrintScreen> createState() => _BillPrintScreenState();
}

class _BillPrintScreenState extends State<BillPrintScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final GlobalKey _billKey = GlobalKey();

  bool _loading = true;
  bool _exporting = false;

  Map<String, dynamic>? _student;
  Map<String, dynamic>? _school;
  Map<String, dynamic>? _bill;
  List<Map<String, dynamic>> _breakdown = [];

  double _previousBalance = 0.0;
  double _subtotal = 0.0;
  double _grandTotal = 0.0;
  double _totalPaid = 0.0;
  double _outstanding = 0.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    // Load student WITH class and arm names using JOIN
    final db = await _db.database;
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

    _school = await _db.getSchoolProfile();
    
    _bill = await _db.getBillForStudent(
      widget.studentId,
      widget.term,
      widget.session,
    );

    if (_bill != null) {
      // Load bill breakdown
      final rawBreakdown = await db.rawQuery('''
        SELECT 
          bi.feeItemId,
          bi.amount,
          bi.label as savedLabel,
          fi.name as feeItemName
        FROM student_fee_breakdown bi
        LEFT JOIN fee_items fi ON bi.feeItemId = fi.id
        WHERE bi.billId = ?
        ORDER BY bi.id ASC
      ''', [widget.billId]);

      _breakdown = rawBreakdown.map((row) {
        final feeName = row['feeItemName']?.toString() ?? 
                       row['savedLabel']?.toString() ?? 
                       'Fee';
        return {
          'feeItemId': row['feeItemId'],
          'amount': row['amount'],
          'label': feeName,
        };
      }).toList();

      // Calculate fresh previous balance
      _previousBalance = await _db.computeOutstandingBeforeTerm(
        widget.studentId,
        term: widget.term,
        session: widget.session,
      );

      _subtotal = _breakdown.fold(
        0.0,
        (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0.0),
      );

      // Grand total = fresh previous balance + current term fee subtotal
      _grandTotal = _previousBalance + _subtotal;
    }

    // Calculate total paid for this term
    final payments = await _db.getPayments(
      widget.studentId,
      term: widget.term,
      session: widget.session,
    );
    _totalPaid = payments.fold<double>(
      0.0,
      (sum, p) => sum + ((p['amount'] as num?)?.toDouble() ?? 0.0),
    );

    _outstanding = _grandTotal - _totalPaid;

    if (mounted) setState(() => _loading = false);
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
            Text('Export Fee Bill'),
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

            // Option 1: PDF
            _buildExportOption(
              icon: Icons.picture_as_pdf,
              iconColor: Colors.red,
              title: 'PDF Document',
              subtitle: 'Professional A4 format',
              onTap: () {
                Navigator.pop(context);
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
                Navigator.pop(context);
                _exportAsJPEG();
              },
            ),

            const SizedBox(height: 12),

            // Option 3: Thermal Printer (Bluetooth)
            _buildExportOption(
              icon: Icons.print,
              iconColor: Colors.orange,
              title: 'Thermal Printer',
              subtitle: 'Bluetooth — select size and print',
              onTap: () {
                Navigator.pop(context);
                _showThermalPrinterSizeDialog();
              },
            ),

            const SizedBox(height: 12),

            // Option 4: USB Printer
            _buildExportOption(
              icon: Icons.usb,
              iconColor: Colors.deepPurple,
              title: 'USB Printer',
              subtitle: 'OTG cable — direct USB print',
              onTap: () {
                Navigator.pop(context);
                _showUsbPrinterSizeDialog();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
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
            content: Text('Printer not connected. Bill printing cancelled.'),
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
            const Text('Print to Thermal Printer'),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connected to: ${ThermalPrinterManager.connectedPrinter?.platformName ?? "Unknown"}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select paper size:',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // 58mm Option
            _buildBluetoothSizeOption(
              title: '58mm Paper',
              subtitle: 'Standard thermal receipt size',
              paperSize: PaperSize.mm58,
              onTap: () {
                Navigator.pop(context);
                _printViaBluetooth(PaperSize.mm58);
              },
            ),

            const SizedBox(height: 12),

            // 80mm Option (Recommended)
            _buildBluetoothSizeOption(
              title: '80mm Paper',
              subtitle: 'Wider format (Recommended)',
              paperSize: PaperSize.mm80,
              isRecommended: true,
              onTap: () {
                Navigator.pop(context);
                _printViaBluetooth(PaperSize.mm80);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildBluetoothSizeOption({
    required String title,
    required String subtitle,
    required PaperSize paperSize,
    bool isRecommended = false,
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
              color: isRecommended ? Colors.orange : Colors.grey.shade600,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: isRecommended ? FontWeight.bold : FontWeight.normal,
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
                            'RECOMMENDED',
                            style: TextStyle(fontSize: 9, color: Colors.white),
                          ),
                        ),
                      ],
                    ],
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

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // School Header - CENTERED
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      schoolName.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
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

              // Bill Title - CENTERED
              pw.Center(
                child: pw.Text(
                  'FEE BILL',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
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
                    _buildPdfRow('Admission No:', _student?['admissionNo'] ?? 'N/A'),
                    pw.SizedBox(height: 8),
                    _buildPdfRow('Class:', studentClass),
                    pw.SizedBox(height: 8),
                    _buildPdfRow('Term:', widget.term),
                    pw.SizedBox(height: 8),
                    _buildPdfRow('Session:', widget.session),
                  ],
                ),
              ),

              pw.SizedBox(height: 20),

              // Fee Breakdown Table
              pw.Text(
                'Fee Breakdown',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 10),

              pw.Table(
                border: pw.TableBorder.all(),
                children: [
                  // Header
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(10),
                        child: pw.Text(
                          'Fee Item',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(10),
                        child: pw.Text(
                          'Amount (N)',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  // Data rows
                  ..._breakdown.map((item) => pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(10),
                            child: pw.Text(item['label']?.toString() ?? 'Fee'),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(10),
                            child: pw.Text(
                              NumberFormat("#,##0.00").format((item['amount'] as num?)?.toDouble() ?? 0.0),
                              textAlign: pw.TextAlign.right,
                            ),
                          ),
                        ],
                      )),
                ],
              ),

              pw.SizedBox(height: 20),

              // Subtotal, Previous Balance, and Total Amount Due
              pw.Container(
                padding: const pw.EdgeInsets.all(15),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 1.5, color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  children: [
                    // Subtotal row
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Subtotal (Current Term Fees):',
                          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          'N ${NumberFormat("#,##0.00").format(_subtotal)}',
                          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),

                    // Previous Balance/Credit row (if any)
                    if (_previousBalance != 0) ...[
                      pw.SizedBox(height: 10),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            _previousBalance > 0 ? 'Previous Outstanding Balance:' : 'Previous Credit:',
                            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _previousBalance > 0 ? PdfColors.orange700 : PdfColors.green700),
                          ),
                          pw.Text(
                            'N ${NumberFormat("#,##0.00").format(_previousBalance.abs())}',
                            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _previousBalance > 0 ? PdfColors.orange700 : PdfColors.green700),
                          ),
                        ],
                      ),
                    ],

                    pw.SizedBox(height: 10),
                    pw.Divider(thickness: 2, color: PdfColors.indigo),
                    pw.SizedBox(height: 10),

                    // Total Amount Due row
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'TOTAL AMOUNT DUE:',
                          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                        ),
                        pw.Text(
                          'N ${NumberFormat("#,##0.00").format(_grandTotal)}',
                          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                        ),
                      ],
                    ),
                  ],
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
                      'Please ensure timely payment of fees',
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
      final fileName = 'Bill_${widget.studentName}_${widget.term}_PDF.pdf'
          .replaceAll(' ', '_')
          .replaceAll('/', '-');
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      setState(() => _exporting = false);

      if (!mounted) return;

      // Share immediately
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Fee Bill - ${widget.studentName}',
        text: 'Fee bill for ${widget.term} ${widget.session}',
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

  pw.Widget _buildBankDetailsThermal(PrinterSize size) {
    final accounts = _getBankAccounts();
    if (accounts.isEmpty) return pw.SizedBox();

    return pw.Column(
      children: [
        pw.SizedBox(height: size.lineSpacing * 2),
        pw.Text('BANK DETAILS', style: pw.TextStyle(fontSize: size.fontSize, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: size.lineSpacing),
        ...accounts.map((acc) => pw.Padding(
          padding: pw.EdgeInsets.only(bottom: size.lineSpacing),
          child: pw.Column(
            children: [
              pw.Text(acc['bankName'], textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: size.fontSize, fontWeight: pw.FontWeight.bold)),
              pw.Text('${acc['accountNumber']} - ${acc['accountName']}', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: size.fontSize - 1)),
            ],
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
      // Capture the bill widget as image
      final RenderRepaintBoundary boundary = _billKey.currentContext!
          .findRenderObject() as RenderRepaintBoundary;
      
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      // Save as JPEG
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'Bill_${widget.studentName}_${widget.term}_IMAGE.jpg'
          .replaceAll(' ', '_')
          .replaceAll('/', '-');
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(pngBytes);

      setState(() => _exporting = false);

      if (!mounted) return;

      // Share immediately
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Fee Bill - ${widget.studentName}',
        text: 'Fee bill for ${widget.term} ${widget.session}',
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
  // DIRECT BLUETOOTH THERMAL PRINTING
  // ========================================
  Future<void> _printViaBluetooth(PaperSize paperSize) async {
    setState(() => _exporting = true);

    try {
      final schoolName = _school?['name'] ?? "School Name";
      final schoolAddress = _school?['address'] ?? "";
      final studentClass = "${_student?['className'] ?? 'N/A'} - ${_student?['armName'] ?? 'N/A'}";

      // Prepare fee items for thermal printer
      final feeItems = <Map<String, dynamic>>[];

      // Add previous balance as first item if it exists
      if (_previousBalance > 0) {
        feeItems.add({
          'name': 'Previous Balance',
          'amount': _previousBalance,
        });
      }

      // Add all fee breakdown items
      feeItems.addAll(_breakdown.map((item) {
        final label = item['label']?.toString() ?? 'Fee';
        final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
        return {
          'name': label,
          'amount': amount,
        };
      }).toList());

      // Print via Bluetooth
      await ThermalPrinterManager.printBill(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        studentName: widget.studentName,
        studentClass: studentClass,
        term: widget.term,
        feeItems: feeItems,
        total: _grandTotal,
        billDate: DateFormat('dd/MM/yyyy').format(DateTime.now()),
        schoolPhone: _school?['phone']?.toString(),
        bankAccounts: _getBankAccounts(),
        paperSize: paperSize,
      );

      // Increment print counter
      await PrintCounterHelper.incrementBillsPrinted();

      setState(() => _exporting = false);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bill printed successfully on ${paperSize == PaperSize.mm58 ? "58mm" : "80mm"} paper!'),
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
  // USB THERMAL PRINTING
  // ========================================
  Future<void> _showUsbPrinterSizeDialog() async {
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
            content: Text('No USB printer connected. Print cancelled.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    final deviceName =
        UsbPrinterManager.connectedDevice?['productName']?.toString() ?? 'USB Printer';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.usb, color: Colors.deepPurple),
            const SizedBox(width: 8),
            const Text('Print via USB'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('CONNECTED',
                  style: TextStyle(fontSize: 10, color: Colors.white)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connected to: $deviceName',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Select paper size:',
                style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 16),
            _buildBluetoothSizeOption(
              title: '58mm Paper',
              subtitle: 'Standard thermal receipt size',
              paperSize: PaperSize.mm58,
              onTap: () {
                Navigator.pop(context);
                _printViaUsb(PaperSize.mm58);
              },
            ),
            const SizedBox(height: 12),
            _buildBluetoothSizeOption(
              title: '80mm Paper',
              subtitle: 'Wider format (Recommended)',
              paperSize: PaperSize.mm80,
              isRecommended: true,
              onTap: () {
                Navigator.pop(context);
                _printViaUsb(PaperSize.mm80);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _printViaUsb(PaperSize paperSize) async {
    setState(() => _exporting = true);
    try {
      final schoolName = _school?['name'] ?? 'School Name';
      final schoolAddress = _school?['address'] ?? '';
      final studentClass =
          '${_student?['className'] ?? 'N/A'} - ${_student?['armName'] ?? 'N/A'}';

      final feeItems = <Map<String, dynamic>>[];
      if (_previousBalance > 0) {
        feeItems.add({'name': 'Previous Balance', 'amount': _previousBalance});
      }
      feeItems.addAll(_breakdown.map((item) => {
            'name': item['label']?.toString() ?? 'Fee',
            'amount': (item['amount'] as num?)?.toDouble() ?? 0.0,
          }));

      await UsbPrinterManager.printBill(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        studentName: widget.studentName,
        studentClass: studentClass,
        term: widget.term,
        feeItems: feeItems,
        total: _grandTotal,
        billDate: DateFormat('dd/MM/yyyy').format(DateTime.now()),
        schoolPhone: _school?['phone']?.toString(),
        bankAccounts: _getBankAccounts(),
        paperSize: paperSize,
      );

      await PrintCounterHelper.incrementBillsPrinted();
      setState(() => _exporting = false);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Bill printed via USB on ${paperSize == PaperSize.mm58 ? "58mm" : "80mm"} paper!'),
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

  // ========================================
  // EXPORT AS THERMAL PRINT (PDF - Legacy, kept for compatibility)
  // ========================================
  Future<void> _exportAsThermalPrint(PrinterSize size) async {
    setState(() => _exporting = true);

    try {
      final pdf = pw.Document();
      
      final schoolName = _school?['name'] ?? "School Name";
      final schoolAddress = _school?['address'] ?? "";
      final schoolPhone = _school?['phone'] ?? "";
      final studentClass = "${_student?['className'] ?? 'N/A'} - ${_student?['armName'] ?? 'N/A'}";
      final admissionNo = _student?['admissionNo'] ?? 'N/A';

      // THERMAL FORMAT with selected size
      final thermalFormat = PdfPageFormat(size.widthPoints, double.infinity);

      pdf.addPage(
        pw.Page(
          pageFormat: thermalFormat,
          margin: pw.EdgeInsets.all(size.margin),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // School Header
              pw.Text(
                schoolName.toUpperCase(),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: size.titleFontSize,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (schoolAddress.isNotEmpty) ...[
                pw.SizedBox(height: size.lineSpacing),
                pw.Text(
                  schoolAddress,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: size.fontSize - 1),
                ),
              ],
              if (schoolPhone.isNotEmpty) ...[
                pw.SizedBox(height: size.lineSpacing / 2),
                pw.Text(
                  schoolPhone,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: size.fontSize - 1),
                ),
              ],

              pw.SizedBox(height: size.lineSpacing * 2),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: size.lineSpacing),

              // Title
              pw.Text(
                'FEE BILL',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: size.titleFontSize - 1,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: size.lineSpacing),
              pw.Text(
                '${widget.term} - ${widget.session}',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: size.fontSize - 1, color: PdfColors.grey700),
              ),

              pw.SizedBox(height: size.lineSpacing * 2),

              // Student Info
              pw.Container(
                width: double.infinity,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildThermalRow('Student:', widget.studentName, size),
                    pw.SizedBox(height: size.lineSpacing),
                    _buildThermalRow('Class:', studentClass, size),
                    pw.SizedBox(height: size.lineSpacing),
                    _buildThermalRow('Adm. No:', admissionNo, size),
                  ],
                ),
              ),

              pw.SizedBox(height: size.lineSpacing * 2),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: size.lineSpacing),

              // Fee Breakdown
              pw.Container(
                width: double.infinity,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Fee Breakdown:',
                      style: pw.TextStyle(
                        fontSize: size.fontSize,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: size.lineSpacing),
                    ..._breakdown.map((item) {
                      final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
                      final label = item['label']?.toString() ?? 'Fee';

                      return pw.Container(
                        margin: pw.EdgeInsets.only(bottom: size.lineSpacing),
                        child: _buildThermalRow(
                          label,
                          'N ${NumberFormat("#,##0.00").format(amount)}',
                          size,
                        ),
                      );
                    }),
                  ],
                ),
              ),

              pw.SizedBox(height: size.lineSpacing * 2),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: size.lineSpacing),

              // Totals
              pw.Container(
                width: double.infinity,
                padding: pw.EdgeInsets.all(size.margin / 2),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
                child: pw.Column(
                  children: [
                    _buildThermalRow(
                      'Subtotal:',
                      'N ${NumberFormat("#,##0.00").format(_subtotal)}',
                      size,
                      bold: true,
                    ),
                    if (_previousBalance != 0) ...[
                      pw.SizedBox(height: size.lineSpacing),
                      _buildThermalRow(
                        _previousBalance > 0 ? 'Previous:' : 'Credit:',
                        'N ${NumberFormat("#,##0.00").format(_previousBalance.abs())}',
                        size,
                        bold: true,
                      ),
                    ],
                    pw.Divider(height: size.lineSpacing * 2, thickness: 1),
                    _buildThermalRow(
                      'TOTAL DUE:',
                      'N ${NumberFormat("#,##0.00").format(_grandTotal)}',
                      size,
                      bold: true,
                      fontSize: size.fontSize + 1,
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: size.lineSpacing * 3),

              // Bank details
              _buildBankDetailsThermal(size),

              // Footer
              pw.Divider(thickness: 1),
              pw.SizedBox(height: size.lineSpacing),
              pw.Text(
                'Please ensure timely payment',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: size.fontSize, fontStyle: pw.FontStyle.italic),
              ),
              pw.SizedBox(height: size.lineSpacing),
              pw.Text(
                'Printed: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: size.fontSize - 1, color: PdfColors.grey600),
              ),
              pw.SizedBox(height: size.lineSpacing / 2),
              pw.Text(
                'Paper: ${size.name}',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: size.fontSize - 2, color: PdfColors.grey500),
              ),
            ],
          ),
        ),
      );

      // Save thermal print PDF
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'Bill_${widget.studentName}_${widget.term}_${size.name}_THERMAL.pdf'
          .replaceAll(' ', '_')
          .replaceAll('/', '-');
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      setState(() => _exporting = false);

      if (!mounted) return;

      // Share to printer app
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Print Fee Bill - ${widget.studentName}',
        text: 'Fee bill (${size.name}) for ${widget.term} ${widget.session}',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Thermal bill (${size.name}) ready to print'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'Share Again',
            textColor: Colors.white,
            onPressed: () async {
              await Share.shareXFiles([XFile(file.path)]);
            },
          ),
        ),
      );
    } catch (e) {
      setState(() => _exporting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Thermal print failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  pw.Widget _buildThermalRow(String label, String value, PrinterSize size, {bool bold = false, double? fontSize}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: fontSize ?? size.fontSize,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: fontSize ?? size.fontSize,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
            maxLines: 2,
          ),
        ),
      ],
    );
  }

  // ========================================
  // UI BUILD
  // ========================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Bill Preview"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
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
                  key: _billKey,
                  child: Container(
                    color: Colors.white,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSchoolHeader(),
                          const SizedBox(height: 24),
                          const Text(
                            'FEE BILL',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildStudentInfo(),
                          const SizedBox(height: 16),
                          _buildFeeBreakdown(),
                          const SizedBox(height: 24),
                          _buildTotals(),
                          const SizedBox(height: 32),
                          const Divider(),
                          const SizedBox(height: 16),
                          Center(
                            child: Column(
                              children: [
                                const Text(
                                  'Please ensure timely payment of fees',
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
                                _exporting ? 'Exporting...' : 'Export & Share Bill',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigo,
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
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildSchoolHeader() {
    return Column(
      children: [
        Text(
          (_school?['name'] ?? "School Name").toUpperCase(),
          style: const TextStyle(
            fontSize: 18,
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
    );
  }

  Widget _buildStudentInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildInfoRow('Student Name:', widget.studentName),
          const SizedBox(height: 8),
          _buildInfoRow('Admission No:', _student?['admissionNo'] ?? 'N/A'),
          const SizedBox(height: 8),
          _buildInfoRow('Class:', "${_student?['className'] ?? 'N/A'} - ${_student?['armName'] ?? 'N/A'}"),
          const SizedBox(height: 8),
          _buildInfoRow('Term:', widget.term),
          const SizedBox(height: 8),
          _buildInfoRow('Session:', widget.session),
        ],
      ),
    );
  }

  Widget _buildFeeBreakdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Fee Breakdown',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Table(
          border: TableBorder.all(color: Colors.grey.shade300),
          children: [
            // Header
            TableRow(
              decoration: BoxDecoration(color: Colors.grey.shade200),
              children: const [
                Padding(
                  padding: EdgeInsets.all(10),
                  child: Text(
                    'Fee Item',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(10),
                  child: Text(
                    'Amount (N)',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            // Data rows
            ..._breakdown.map((item) {
              final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
              final label = item['label']?.toString() ?? 'Fee';

              return TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(label),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      NumberFormat("#,##0.00").format(amount),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildTotals() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            'Subtotal:',
            'N${NumberFormat("#,##0.00").format(_subtotal)}',
            bold: true,
          ),
          if (_previousBalance != 0) ...[
            const SizedBox(height: 8),
            _buildInfoRow(
              _previousBalance > 0 ? 'Previous Balance:' : 'Previous Credit:',
              'N${NumberFormat("#,##0.00").format(_previousBalance.abs())}',
              bold: true,
              color: _previousBalance > 0 ? Colors.orange.shade700 : Colors.green.shade700,
            ),
          ],
          const Divider(),
          _buildInfoRow(
            'TOTAL AMOUNT DUE:',
            'N${NumberFormat("#,##0.00").format(_grandTotal)}',
            bold: true,
            color: Colors.indigo,
            fontSize: 16,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool bold = false, Color? color, double fontSize = 14}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }
}