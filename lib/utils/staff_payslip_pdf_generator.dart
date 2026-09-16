// lib/utils/staff_payslip_pdf_generator.dart

import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'staff_payslip_html_generator.dart';
import 'native_html_pdf_helper.dart';
import 'pdf_export_helper.dart';

/// Generates an individual payslip PDF for a single staff member for a
/// single payroll month, built from the same payroll-data map used by the
/// Staff Payroll screen's cards.
class StaffPayslipPDFGenerator {
  static final _currencyFormat = NumberFormat.currency(symbol: 'N', decimalDigits: 2);

  static Future<String> generatePayslipPDF({
    required Map<String, dynamic> staff,
    required String month,
    required Map<String, dynamic> schoolProfile,
    bool saveToDownloads = false,
  }) async {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final safeStaffId = (staff['staffId'] ?? 'staff').toString().replaceAll('/', '_');
    final baseName = 'Payslip_${safeStaffId}_${month.replaceAll(' ', '_')}_$timestamp';

    if (Platform.isAndroid) {
      final html = StaffPayslipHtmlGenerator.build(
        staff: staff,
        month: month,
        schoolProfile: schoolProfile,
      );
      return NativeHtmlPdfHelper.saveHtmlAsPdf(
        html: html,
        baseFileName: baseName,
        saveToDownloads: saveToDownloads,
      );
    }

    final pdf = pw.Document();

    final isPerPeriodPay = staff['isPerPeriodPay'] == true;
    final totalPayable = (staff['totalPayable'] as num? ?? staff['netSalary'] as num? ?? 0).toDouble();
    final arrears = (staff['arrears'] as num? ?? 0).toDouble();
    final loanArrears = (staff['loanArrears'] as num? ?? 0).toDouble();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildHeader(schoolProfile, month),
            pw.SizedBox(height: 16),
            _buildStaffInfo(staff),
            pw.SizedBox(height: 16),
            _buildSectionTable(
              'Earnings',
              PdfColors.green700,
              [
                if (isPerPeriodPay)
                  _row(
                    'Basic Pay (${_fmtNum((staff['periodsWorked'] as num? ?? 0).toDouble())} periods × ${_currencyFormat.format(staff['periodRate'])})',
                    _currencyFormat.format(staff['basicSalary']),
                  )
                else
                  _row('Basic Salary', _currencyFormat.format(staff['basicSalary'])),
                if (!isPerPeriodPay)
                  _row('Payment Basis', _basisSummary(staff['payrollBasis'] as Map<String, dynamic>?)),
                _row('Incentives/Grants', _currencyFormat.format(staff['totalIncentives'])),
                if (arrears > 0) _row('Salary Arrears (prev. months)', _currencyFormat.format(arrears)),
              ],
            ),
            pw.SizedBox(height: 12),
            _buildSectionTable(
              'Deductions',
              PdfColors.red700,
              [
                _row(
                  loanArrears > 0 ? 'Loan (this month)' : 'Loan Deduction',
                  _currencyFormat.format(staff['loanDeduction']),
                ),
                if (loanArrears > 0) _row('Loan Arrears (missed months)', _currencyFormat.format(loanArrears)),
                _row('Penalties', _currencyFormat.format(staff['totalDeductions'])),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                border: pw.Border.all(color: PdfColors.blue200),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    arrears > 0 ? 'Total Payable' : 'Net Pay',
                    style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    _currencyFormat.format(totalPayable),
                    style: pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue900,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            _buildSectionTable(
              'Bank Account Details',
              PdfColors.grey700,
              [
                _row('Bank Name', (staff['bankName'] ?? '').toString().isEmpty ? 'Not provided' : staff['bankName']),
                _row('Account Name', (staff['accountName'] ?? '').toString().isEmpty ? 'Not provided' : staff['accountName']),
                _row('Account Number', (staff['accountNumber'] ?? '').toString().isEmpty ? 'Not provided' : staff['accountNumber']),
              ],
            ),
            pw.Spacer(),
            pw.Divider(color: PdfColors.grey300),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Prepared by: _______________________', style: const pw.TextStyle(fontSize: 9)),
                pw.Text('Signature: _______________________', style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ],
        ),
      ),
    );

    final output = await PdfExportDirectoryHelper.resolve(saveToDownloads: saveToDownloads);
    final file = File('${output.path}/$baseName.pdf');
    await file.writeAsBytes(await pdf.save());

    return file.path;
  }

  static pw.Widget _buildHeader(Map<String, dynamic> schoolProfile, String month) {
    final schoolName = schoolProfile['name'] ?? 'School Name';
    final address = schoolProfile['address'] ?? '';
    final phone = schoolProfile['phone'] ?? '';

    return pw.Column(
      children: [
        pw.Text(
          schoolName.toUpperCase(),
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
        if (address.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(address, style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center),
        ],
        if (phone.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text('Tel: $phone', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center),
        ],
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: pw.BoxDecoration(color: PdfColors.blue50, borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Text(
            'PAYSLIP - $month',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildStaffInfo(Map<String, dynamic> staff) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(4)),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(staff['staffName'] ?? '', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text('Staff ID: ${staff['staffId'] ?? ''}', style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
          pw.Text(
            staff['isPerPeriodPay'] == true ? 'Per-Period Staff' : (staff['staffType'] ?? ''),
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSectionTable(String title, PdfColor color, List<pw.Widget> rows) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: color, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: color)),
          pw.SizedBox(height: 6),
          ...rows,
        ],
      ),
    );
  }

  static pw.Widget _row(String label, dynamic value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.Text(value.toString(), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  static String _fmtNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  static String _basisSummary(Map<String, dynamic>? basis) {
    if (basis == null) return 'Full Payment (100%)';
    final type = basis['basisType'] as String? ?? 'full';
    switch (type) {
      case 'percentage':
        final pct = (basis['percentageValue'] as num?)?.toDouble() ?? 100;
        return '${_fmtNum(pct)}% of Salary';
      case 'days':
      case 'weeks':
        final total = (basis['totalUnits'] as num?)?.toDouble() ?? 0;
        final worked = (basis['workedUnits'] as num?)?.toDouble() ?? 0;
        final pct = total > 0 ? (worked / total * 100) : 100;
        final unit = type == 'days' ? 'Working Days' : 'Working Weeks';
        return '${_fmtNum(worked)}/${_fmtNum(total)} $unit (${pct.toStringAsFixed(0)}%)';
      case 'full':
      default:
        return 'Full Payment (100%)';
    }
  }
}
