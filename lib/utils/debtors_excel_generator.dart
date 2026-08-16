// lib/utils/debtors_excel_generator.dart

import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class DebtorsExcelGenerator {
  static Future<String> generateDebtorsExcel({
    required List<Map<String, dynamic>> debtors,
    required String className,
    required String term,
    required String session,
    required Map<String, dynamic> schoolProfile,
    required String filterType,
    required double minPercentage,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Debtors List'];

    // Remove default sheet if it exists
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // Calculate totals
    double totalBills = 0;
    double totalPaid = 0;
    double totalOutstanding = 0;

    for (var debtor in debtors) {
      totalBills += (debtor['totalBill'] as num).toDouble();
      totalPaid += (debtor['totalPaid'] as num).toDouble();
      totalOutstanding += (debtor['outstanding'] as num).toDouble();
    }

    int currentRow = 0;

    // ===============================
    // HEADER SECTION
    // ===============================
    final schoolName = schoolProfile['name'] ?? 'School Name';
    final address = schoolProfile['address'] ?? '';
    final phone = schoolProfile['phone'] ?? '';
    final email = schoolProfile['email'] ?? '';

    // School Name (Row 0)
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: currentRow),
    );
    var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
    cell.value = TextCellValue(schoolName.toUpperCase());
    cell.cellStyle = CellStyle(
      bold: true,
      fontSize: 16,
      horizontalAlign: HorizontalAlign.Center,
    );
    currentRow++;

    // Address (if available)
    if (address.isNotEmpty) {
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
        CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: currentRow),
      );
      cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
      cell.value = TextCellValue(address);
      cell.cellStyle = CellStyle(
        fontSize: 10,
        horizontalAlign: HorizontalAlign.Center,
      );
      currentRow++;
    }

    // Phone & Email (if available)
    if (phone.isNotEmpty || email.isNotEmpty) {
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
        CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: currentRow),
      );
      cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
      cell.value = TextCellValue(
        [if (phone.isNotEmpty) 'Tel: $phone', if (email.isNotEmpty) email].join(' | '),
      );
      cell.cellStyle = CellStyle(
        fontSize: 9,
        horizontalAlign: HorizontalAlign.Center,
      );
      currentRow++;
    }

    currentRow++; // Blank row

    // Report Title
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: currentRow),
    );
    cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
    cell.value = TextCellValue('DEBTORS LIST');
    cell.cellStyle = CellStyle(
      bold: true,
      fontSize: 14,
      horizontalAlign: HorizontalAlign.Center,
    );
    currentRow++;

    currentRow++; // Blank row

    // ===============================
    // PERIOD INFO
    // ===============================
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow)).value =
        TextCellValue('Class:');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: currentRow)).value =
        TextCellValue(className);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: currentRow)).value =
        TextCellValue('Term:');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: currentRow)).value =
        TextCellValue(term);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: currentRow)).value =
        TextCellValue('Session:');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: currentRow)).value =
        TextCellValue(session);
    currentRow++;

    // Generated Date
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow)).value =
        TextCellValue('Generated:');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: currentRow)).value =
        TextCellValue(DateFormat('MMM d, yyyy - h:mm a').format(DateTime.now()));
    currentRow++;

    currentRow++; // Blank row

    // ===============================
    // FILTER INFO
    // ===============================
    final filterDesc = filterType == 'all'
        ? 'All students with outstanding balances'
        : 'Students who paid less than ${minPercentage.toStringAsFixed(0)}% of their bills';

    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
      CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: currentRow),
    );
    cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
    cell.value = TextCellValue('Filter: $filterDesc');
    cell.cellStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#E3F2FD'),
    );

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: currentRow)).value =
        TextCellValue('Total Debtors:');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: currentRow)).cellStyle =
        CellStyle(bold: true);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: currentRow)).value =
        IntCellValue(debtors.length);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: currentRow)).cellStyle =
        CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#FFCDD2'),
    );
    currentRow++;

    currentRow++; // Blank row

    // ===============================
    // FINANCIAL SUMMARY
    // ===============================
    final formatter = NumberFormat('#,##0.00');

    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: currentRow),
    );
    cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
    cell.value = TextCellValue('FINANCIAL SUMMARY');
    cell.cellStyle = CellStyle(
      bold: true,
      fontSize: 12,
      horizontalAlign: HorizontalAlign.Center,
      backgroundColorHex: ExcelColor.fromHexString('#FFEBEE'),
    );
    currentRow++;

    // Summary Row
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow)).value =
        TextCellValue('Total Bills:');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: currentRow)).value =
        TextCellValue('N${formatter.format(totalBills)}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: currentRow)).cellStyle =
        CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#1976D2'),
    );

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: currentRow)).value =
        TextCellValue('Total Paid:');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: currentRow)).value =
        TextCellValue('N${formatter.format(totalPaid)}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: currentRow)).cellStyle =
        CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#388E3C'),
    );

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: currentRow)).value =
        TextCellValue('Total Outstanding:');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: currentRow)).value =
        TextCellValue('N${formatter.format(totalOutstanding)}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: currentRow)).cellStyle =
        CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#D32F2F'),
    );
    currentRow++;

    currentRow++; // Blank row

    // ===============================
    // DEBTORS TABLE
    // ===============================

    // Table Headers
    final headers = [
      'S/N',
      'Admission No',
      'Student Name',
      'Total Bill (N)',
      'Amount Paid (N)',
      'Outstanding (N)',
      '% Paid',
    ];

    for (int col = 0; col < headers.length; col++) {
      cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: currentRow));
      cell.value = TextCellValue(headers[col]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#E0E0E0'),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );
    }
    currentRow++;

    // Table Data
    for (int i = 0; i < debtors.length; i++) {
      final debtor = debtors[i];
      final totalBill = (debtor['totalBill'] as num).toDouble();
      final totalPaid = (debtor['totalPaid'] as num).toDouble();
      final outstanding = (debtor['outstanding'] as num).toDouble();
      final percentPaid = (debtor['percentPaid'] as num).toDouble();

      // Alternating row colors
      final bgColor = i % 2 == 0 ? '#FFFFFF' : '#F5F5F5';

      // S/N
      cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
      cell.value = IntCellValue(i + 1);
      cell.cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString(bgColor),
        horizontalAlign: HorizontalAlign.Center,
      );

      // Admission No
      cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: currentRow));
      cell.value = TextCellValue(debtor['admissionNo'] ?? '');
      cell.cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString(bgColor),
      );

      // Student Name
      cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: currentRow));
      cell.value = TextCellValue('${debtor['surname']} ${debtor['firstName']}');
      cell.cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString(bgColor),
      );

      // Total Bill
      cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: currentRow));
      cell.value = DoubleCellValue(totalBill);
      cell.cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString(bgColor),
      );

      // Amount Paid
      cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: currentRow));
      cell.value = DoubleCellValue(totalPaid);
      cell.cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString(bgColor),
        fontColorHex: ExcelColor.fromHexString('#388E3C'),
      );

      // Outstanding
      cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: currentRow));
      cell.value = DoubleCellValue(outstanding);
      cell.cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString(bgColor),
        fontColorHex: ExcelColor.fromHexString('#D32F2F'),
        bold: true,
      );

      // % Paid
      cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: currentRow));
      cell.value = TextCellValue('${percentPaid.toStringAsFixed(1)}%');
      
      // Color based on percentage
      String percentColor = '#D32F2F'; // Red
      if (percentPaid >= 80) {
        percentColor = '#388E3C'; // Green
      } else if (percentPaid >= 50) {
        percentColor = '#F57C00'; // Orange
      }
      
      cell.cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString(bgColor),
        fontColorHex: ExcelColor.fromHexString(percentColor),
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );

      currentRow++;
    }

    currentRow++; // Blank row

    // ===============================
    // FOOTER NOTE
    // ===============================
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: currentRow),
    );
    cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
    cell.value = TextCellValue(
      'Note: This report shows students with outstanding fee balances. Please follow up with parents/guardians for payment.',
    );
    cell.cellStyle = CellStyle(
      fontSize: 9,
      italic: true,
      fontColorHex: ExcelColor.fromHexString('#757575'),
    );

    // ===============================
    // SET COLUMN WIDTHS
    // ===============================
    sheet.setColumnWidth(0, 8);   // S/N
    sheet.setColumnWidth(1, 15);  // Admission No
    sheet.setColumnWidth(2, 30);  // Student Name
    sheet.setColumnWidth(3, 15);  // Total Bill
    sheet.setColumnWidth(4, 15);  // Amount Paid
    sheet.setColumnWidth(5, 15);  // Outstanding
    sheet.setColumnWidth(6, 12);  // % Paid

    // ===============================
    // SAVE FILE
    // ===============================
    final output = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'Debtors_${className.replaceAll(' ', '_')}_$timestamp.xlsx';
    final file = File('${output.path}/$fileName');

    final excelBytes = excel.encode();
    if (excelBytes != null) {
      await file.writeAsBytes(excelBytes);
    }

    return file.path;
  }
}