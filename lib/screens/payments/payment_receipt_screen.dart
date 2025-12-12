// lib/screens/payments/payment_receipt_screen.dart
// COMPLETE VERSION with Export Options Dialog

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
import '../../db/database_helper.dart';
import '../../utils/printer_settings_helper.dart';

class PaymentReceiptScreen extends StatefulWidget {
  final int paymentId;
  final int studentId;
  final bool showExportDialog; // NEW: Show export dialog on load

  const PaymentReceiptScreen({
    super.key,
    required this.paymentId,
    required this.studentId,
    this.showExportDialog = false, // Default false for viewing
  });

  @override
  State<PaymentReceiptScreen> createState() => _PaymentReceiptScreenState();
}

class _PaymentReceiptScreenState extends State<PaymentReceiptScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  final GlobalKey _receiptKey = GlobalKey();

  Map<String, dynamic>? _payment;
  Map<String, dynamic>? _student;
  Map<String, dynamic>? _school;

  double _grandTotal = 0.0;
  double _totalPaidThisTerm = 0.0;
  double _outstanding = 0.0;

  bool _loading = true;
  bool _exporting = false;

  String _term = "";
  String _session = "";

  @override
  void initState() {
    super.initState();
    _loadReceipt();
  }

  Future<void> _loadReceipt() async {
    setState(() => _loading = true);

    final db = await _db.database;

    final payRows = await db.query(
      "payments",
      where: "id = ?",
      whereArgs: [widget.paymentId],
      limit: 1,
    );

    _payment = payRows.isNotEmpty ? payRows.first : null;
    
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
    
    _term = _payment?['term']?.toString() ?? await _db.getActiveTerm();
    _session = _payment?['session']?.toString() ?? (await _db.getActiveSession())?['sessionName'] ?? "";

    final bill = await _db.getBillForStudent(widget.studentId, _term, _session);
    _grandTotal = bill != null ? (bill['totalAmount'] as num?)?.toDouble() ?? 0.0 : 0.0;

    final pays = await _db.getPayments(widget.studentId, term: _term, session: _session);
    _totalPaidThisTerm = pays.fold<double>(
      0.0,
      (sum, p) => sum + ((p['amount'] as num?)?.toDouble() ?? 0.0),
    );

    _outstanding = _grandTotal - _totalPaidThisTerm;

    if (mounted) {
      setState(() => _loading = false);
      
      // NEW: Show export dialog if requested (e.g., after saving payment)
      if (widget.showExportDialog) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _showExportOptionsDialog();
          }
        });
      }
    }
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
            Text('Export Receipt As'),
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
              subtitle: 'Standard format, easy to share',
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

            // Option 3: Thermal Printer
            _buildExportOption(
              icon: Icons.print,
              iconColor: Colors.orange,
              title: 'Thermal Printer',
              subtitle: 'Select size and print',
              onTap: () {
                Navigator.pop(context);
                _showThermalPrinterSizeDialog();
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
  // NEW: THERMAL PRINTER SIZE SELECTION DIALOG
  // ========================================
  void _showThermalPrinterSizeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.straighten, color: Colors.orange),
            SizedBox(width: 8),
            Text('Select Paper Size'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose your thermal printer paper size:',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // 58mm Option
            _buildSizeOption(
              size: PrinterSettingsHelper.size58mm,
              isRecommended: false,
              onTap: () {
                Navigator.pop(context);
                _exportAsThermalPrint(PrinterSettingsHelper.size58mm);
              },
            ),

            const SizedBox(height: 12),

            // 80mm Option (Recommended)
            _buildSizeOption(
              size: PrinterSettingsHelper.size80mm,
              isRecommended: true,
              onTap: () {
                Navigator.pop(context);
                _exportAsThermalPrint(PrinterSettingsHelper.size80mm);
              },
            ),

            const SizedBox(height: 12),

            // 110mm Option
            _buildSizeOption(
              size: PrinterSettingsHelper.size110mm,
              isRecommended: false,
              onTap: () {
                Navigator.pop(context);
                _exportAsThermalPrint(PrinterSettingsHelper.size110mm);
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
  // EXPORT AS PDF
  // ========================================
  Future<void> _exportAsPDF() async {
    setState(() => _exporting = true);

    try {
      final pdf = pw.Document();
      
      final amount = (_payment?['amount'] as num?)?.toDouble() ?? 0.0;
      final dateStr = _payment?['paymentDate']?.toString() ?? "";
      final parsedDate = DateTime.tryParse(dateStr) ?? DateTime.now();
      final formattedDate = DateFormat("dd/MM/yy HH:mm").format(parsedDate);
      final method = _payment?['method']?.toString() ?? "";
      final note = _payment?['note']?.toString() ?? "";
      
      final schoolName = _school?['name'] ?? "School Name";
      final schoolAddress = _school?['address'] ?? "";
      final schoolPhone = _school?['phone'] ?? "";
      final studentName = "${_student?['surname']} ${_student?['firstName']} ${_student?['otherName'] ?? ''}".trim();
      final studentClass = "${_student?['className'] ?? 'N/A'} - ${_student?['armName'] ?? 'N/A'}";
      final admissionNo = _student?['admissionNo'] ?? 'N/A';

      // Standard A4 PDF format
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
                      'PAYMENT RECEIPT',
                      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Receipt No: ${widget.paymentId}',
                      style: const pw.TextStyle(fontSize: 14),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      '$_term - $_session',
                      style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
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
                    _buildPdfRow('Student Name:', studentName),
                    pw.SizedBox(height: 8),
                    _buildPdfRow('Class:', studentClass),
                    pw.SizedBox(height: 8),
                    _buildPdfRow('Admission No:', admissionNo),
                  ],
                ),
              ),

              pw.SizedBox(height: 20),

              // Payment Details
              pw.Container(
                padding: const pw.EdgeInsets.all(15),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildPdfRow('Payment Date:', formattedDate),
                    pw.SizedBox(height: 8),
                    _buildPdfRow('Payment Method:', method),
                    if (note.isNotEmpty) ...[
                      pw.SizedBox(height: 8),
                      _buildPdfRow('Note:', note),
                    ],
                  ],
                ),
              ),

              pw.SizedBox(height: 30),

              // Amount Paid
              pw.Center(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(20),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(width: 3),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'AMOUNT PAID',
                        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 10),
                      pw.Text(
                        '₦${NumberFormat("#,##0.00").format(amount)}',
                        style: pw.TextStyle(
                          fontSize: 32,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              pw.SizedBox(height: 30),

              // Balance Summary
              pw.Container(
                padding: const pw.EdgeInsets.all(15),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey200,
                  border: pw.Border.all(),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  children: [
                    _buildPdfRow(
                      'Grand Total (Term):',
                      '₦${NumberFormat("#,##0.00").format(_grandTotal)}',
                      bold: true,
                    ),
                    pw.SizedBox(height: 8),
                    _buildPdfRow(
                      'Total Paid (Term):',
                      '₦${NumberFormat("#,##0.00").format(_totalPaidThisTerm)}',
                      bold: true,
                    ),
                    pw.Divider(thickness: 2),
                    _buildPdfRow(
                      'Outstanding Balance:',
                      '₦${NumberFormat("#,##0.00").format(_outstanding)}',
                      bold: true,
                      fontSize: 16,
                    ),
                  ],
                ),
              ),

              pw.Spacer(),

              // Footer
              pw.Divider(),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'Thank you for your payment',
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
      final fileName = 'Receipt_${widget.paymentId}_PDF.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      setState(() => _exporting = false);

      if (!mounted) return;

      // Share immediately
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Payment Receipt #${widget.paymentId}',
        text: 'Payment receipt for $studentName - $_term $_session',
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
      // Capture the receipt widget as image
      final RenderRepaintBoundary boundary = _receiptKey.currentContext!
          .findRenderObject() as RenderRepaintBoundary;
      
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      // Save as JPEG
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'Receipt_${widget.paymentId}_IMAGE.jpg';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(pngBytes);

      setState(() => _exporting = false);

      if (!mounted) return;

      // Share immediately
      final studentName = "${_student?['surname']} ${_student?['firstName']}".trim();
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Payment Receipt #${widget.paymentId}',
        text: 'Payment receipt for $studentName - $_term $_session',
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
  // EXPORT AS THERMAL PRINT (with size selection)
  // ========================================
  Future<void> _exportAsThermalPrint(PrinterSize size) async {
    setState(() => _exporting = true);

    try {
      final pdf = pw.Document();
      
      final amount = (_payment?['amount'] as num?)?.toDouble() ?? 0.0;
      final dateStr = _payment?['paymentDate']?.toString() ?? "";
      final parsedDate = DateTime.tryParse(dateStr) ?? DateTime.now();
      final formattedDate = DateFormat("dd/MM/yy HH:mm").format(parsedDate);
      final method = _payment?['method']?.toString() ?? "";
      final note = _payment?['note']?.toString() ?? "";
      
      final schoolName = _school?['name'] ?? "School Name";
      final schoolAddress = _school?['address'] ?? "";
      final schoolPhone = _school?['phone'] ?? "";
      final studentName = "${_student?['surname']} ${_student?['firstName']} ${_student?['otherName'] ?? ''}".trim();
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
                'PAYMENT RECEIPT',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: size.titleFontSize - 1,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: size.lineSpacing),
              pw.Text(
                'Receipt No: ${widget.paymentId}',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: size.fontSize - 1, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: size.lineSpacing / 2),
              pw.Text(
                '$_term - $_session',
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
                    _buildThermalRow('Student:', studentName, size),
                    pw.SizedBox(height: size.lineSpacing),
                    _buildThermalRow('Class:', studentClass, size),
                    pw.SizedBox(height: size.lineSpacing),
                    _buildThermalRow('Adm. No:', admissionNo, size),
                  ],
                ),
              ),

              pw.SizedBox(height: size.lineSpacing * 2),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: size.lineSpacing * 2),

              // Payment Details
              pw.Container(
                width: double.infinity,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildThermalRow('Date:', formattedDate, size),
                    pw.SizedBox(height: size.lineSpacing),
                    _buildThermalRow('Method:', method, size),
                    if (note.isNotEmpty) ...[
                      pw.SizedBox(height: size.lineSpacing),
                      pw.Text('Note:', style: pw.TextStyle(fontSize: size.fontSize, fontWeight: pw.FontWeight.bold)),
                      pw.Text(note, style: pw.TextStyle(fontSize: size.fontSize - 1, color: PdfColors.grey700)),
                    ],
                  ],
                ),
              ),

              pw.SizedBox(height: size.lineSpacing * 2),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: size.lineSpacing * 2),

              // Amount
              pw.Container(
                padding: pw.EdgeInsets.all(size.margin),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 2)),
                child: pw.Column(
                  children: [
                    pw.Text(
                      'AMOUNT PAID',
                      style: pw.TextStyle(fontSize: size.fontSize + 1, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: size.lineSpacing),
                    pw.Text(
                      '₦${NumberFormat("#,##0.00").format(amount)}',
                      style: pw.TextStyle(
                        fontSize: size.amountFontSize,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: size.lineSpacing * 2),

              // Balance
              pw.Container(
                width: double.infinity,
                padding: pw.EdgeInsets.all(size.margin / 2),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 1),
                  color: PdfColors.grey100,
                ),
                child: pw.Column(
                  children: [
                    _buildThermalRow(
                      'Grand Total (Term):',
                      '₦${NumberFormat("#,##0.00").format(_grandTotal)}',
                      size,
                      bold: true,
                    ),
                    pw.SizedBox(height: size.lineSpacing),
                    _buildThermalRow(
                      'Total Paid (Term):',
                      '₦${NumberFormat("#,##0.00").format(_totalPaidThisTerm)}',
                      size,
                      bold: true,
                    ),
                    pw.Divider(height: size.lineSpacing * 2, thickness: 1),
                    _buildThermalRow(
                      'Outstanding:',
                      '₦${NumberFormat("#,##0.00").format(_outstanding)}',
                      size,
                      bold: true,
                      fontSize: size.fontSize + 1,
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: size.lineSpacing * 3),

              // Footer
              pw.Divider(thickness: 1),
              pw.SizedBox(height: size.lineSpacing),
              pw.Text(
                'Thank you for your payment',
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
      final fileName = 'Receipt_${widget.paymentId}_${size.name}_THERMAL.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      setState(() => _exporting = false);

      if (!mounted) return;

      // Share to printer app
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Print Receipt #${widget.paymentId}',
        text: 'Thermal receipt (${size.name}) for $studentName - $_term $_session',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Thermal receipt (${size.name}) ready to print'),
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
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Payment Receipt'),
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Receipt'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _showExportOptionsDialog,
            tooltip: 'Export & Share',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Receipt Preview Card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: RepaintBoundary(
                  key: _receiptKey,
                  child: _buildReceiptContent(),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Export Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _exporting ? null : _showExportOptionsDialog,
                icon: _exporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.share),
                label: Text(
                  _exporting ? 'Exporting...' : 'Export & Share Receipt',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Info Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Choose PDF, JPEG, or Thermal Printer format to share',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Receipt Preview Widget
  Widget _buildReceiptContent() {
    final amount = (_payment?['amount'] as num?)?.toDouble() ?? 0.0;
    final dateStr = _payment?['paymentDate']?.toString() ?? "";
    final parsedDate = DateTime.tryParse(dateStr) ?? DateTime.now();
    final formattedDate = DateFormat("dd MMM yyyy, HH:mm").format(parsedDate);
    final method = _payment?['method']?.toString() ?? "";
    final note = _payment?['note']?.toString() ?? "";
    
    final schoolName = _school?['name'] ?? "School Name";
    final schoolAddress = _school?['address'] ?? "";
    final schoolPhone = _school?['phone'] ?? "";
    final studentName = "${_student?['surname']} ${_student?['firstName']} ${_student?['otherName'] ?? ''}".trim();
    final studentClass = "${_student?['className'] ?? 'N/A'} - ${_student?['armName'] ?? 'N/A'}";
    final admissionNo = _student?['admissionNo'] ?? 'N/A';

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // School Header
          Center(
            child: Column(
              children: [
                Text(
                  schoolName.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (schoolAddress.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    schoolAddress,
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (schoolPhone.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    schoolPhone,
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
                  'PAYMENT RECEIPT',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Receipt No: ${widget.paymentId}',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_term - $_session',
                  style: TextStyle(
                    fontSize: 12,
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
                _buildRow('Student Name:', studentName),
                const SizedBox(height: 8),
                _buildRow('Class:', studentClass),
                const SizedBox(height: 8),
                _buildRow('Admission No:', admissionNo),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Payment Details
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _buildRow('Payment Date:', formattedDate),
                const SizedBox(height: 8),
                _buildRow('Payment Method:', method),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildRow('Note:', note),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Amount Paid
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border.all(width: 3, color: Colors.green),
                borderRadius: BorderRadius.circular(8),
                color: Colors.green.shade50,
              ),
              child: Column(
                children: [
                  const Text(
                    'AMOUNT PAID',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '₦${NumberFormat("#,##0.00").format(amount)}',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Balance Summary
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _buildRow(
                  'Grand Total (Term):',
                  '₦${NumberFormat("#,##0.00").format(_grandTotal)}',
                  bold: true,
                ),
                const SizedBox(height: 8),
                _buildRow(
                  'Total Paid (Term):',
                  '₦${NumberFormat("#,##0.00").format(_totalPaidThisTerm)}',
                  bold: true,
                ),
                const Divider(),
                _buildRow(
                  'Outstanding Balance:',
                  '₦${NumberFormat("#,##0.00").format(_outstanding)}',
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
                  'Thank you for your payment',
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
        ],
      ),
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