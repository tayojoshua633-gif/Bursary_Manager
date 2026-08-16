import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class AllClassesNewIntakeBillsPDFGenerator {
  static Future<String> generatePDF({
    required String term,
    required String session,
    required Map<String, dynamic> schoolProfile,
    required Map<String, List<Map<String, dynamic>>> classesByType, // e.g., {'PRE-PRIMARY': [...], 'PRIMARY': [...]}
    required Map<String, Map<String, dynamic>> classArmBills, // "classId_armId" -> bill data
    required List<Map<String, dynamic>> categories,
    required List<Map<String, dynamic>> standaloneItems,
    required Map<int, List<Map<String, dynamic>>> childItemsMap,
  }) async {
    final pdf = pw.Document();
    final currencyFormat = NumberFormat('#,##0.00', 'en_US');

    // Add pages for each class type section
    for (var entry in classesByType.entries) {
      final sectionTitle = entry.key;
      final classes = entry.value;

      if (classes.isEmpty) continue;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            // Header
            _buildHeader(schoolProfile, term, session),
            pw.SizedBox(height: 10),

            // Section Title
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey300,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                'New Intake Bills for $sectionTitle Classes',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 10),

            // Bills Table
            _buildBillsTable(
              classes,
              classArmBills,
              categories,
              standaloneItems,
              childItemsMap,
              currencyFormat,
            ),
            pw.SizedBox(height: 10),

            // Bank Details
            _buildBankDetails(schoolProfile),
          ],
          footer: (context) => _buildPageFooter(context),
        ),
      );
    }

    // Save to file in Download folder
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'New_Intake_Bills_All_Classes_$timestamp.pdf';

    String filePath;
    if (Platform.isAndroid) {
      // For Android, save to Download folder
      filePath = '/storage/emulated/0/Download/$fileName';
    } else if (Platform.isIOS) {
      // For iOS, use documents directory as download folder is not directly accessible
      final output = await getApplicationDocumentsDirectory();
      filePath = '${output.path}/$fileName';
    } else {
      // Fallback for other platforms
      final output = await getApplicationDocumentsDirectory();
      filePath = '${output.path}/$fileName';
    }

    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());

    return file.path;
  }

  static pw.Widget _buildHeader(
    Map<String, dynamic> schoolProfile,
    String term,
    String session,
  ) {
    final schoolName = schoolProfile['name'] ?? 'School Name';
    final address = schoolProfile['address'] ?? '';
    final phone = schoolProfile['phone'] ?? '';
    final email = schoolProfile['email'] ?? '';

    return pw.Column(
      children: [
        pw.Text(
          schoolName.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
        if (address.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            address,
            style: const pw.TextStyle(fontSize: 9),
            textAlign: pw.TextAlign.center,
          ),
        ],
        if (phone.isNotEmpty || email.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            [if (phone.isNotEmpty) 'Tel: $phone', if (email.isNotEmpty) email]
                .join(' | '),
            style: const pw.TextStyle(fontSize: 9),
            textAlign: pw.TextAlign.center,
          ),
        ],
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 2),
        pw.SizedBox(height: 4),
        pw.Text(
          'NEW INTAKE BILLS SUMMARY - ALL CLASSES',
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Term: $term | Session: $session',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
      ],
    );
  }

  static pw.Widget _buildBillsTable(
    List<Map<String, dynamic>> classes,
    Map<String, Map<String, dynamic>> classArmBills,
    List<Map<String, dynamic>> categories,
    List<Map<String, dynamic>> standaloneItems,
    Map<int, List<Map<String, dynamic>>> childItemsMap,
    NumberFormat currencyFormat,
  ) {
    // Build table rows
    List<pw.TableRow> rows = [];

    // Header row
    rows.add(pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text(
            'Fee Category',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          ),
        ),
        ...classes.map((classArm) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(
              classArm['displayName'] ?? '',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
            ),
          );
        }),
      ],
    ));

    // Build map of class-arm fees
    final Map<String, double> classArmRegularTotals = {};
    final Map<String, List<Map<String, dynamic>>> classArmRegularFees = {};
    final Map<String, Map<int, double>> classArmStandaloneAmounts = {};
    final Map<String, Map<int, Map<int, double>>> classArmCategoryChildAmounts = {};

    for (var classArm in classes) {
      final classId = classArm['classId'] as int;
      final armId = classArm['armId'] as int?;
      final key = '${classId}_${armId ?? ''}';
      final billData = classArmBills[key] ?? {};

      final regularFees = List<Map<String, dynamic>>.from(billData['regularFees'] ?? []);
      final regularTotal = (billData['regularTotal'] as num?)?.toDouble() ?? 0.0;
      classArmRegularFees[key] = regularFees;
      classArmRegularTotals[key] = regularTotal;

      final specialFees = List<Map<String, dynamic>>.from(billData['specialFees'] ?? []);

      classArmStandaloneAmounts[key] = {};
      for (var standaloneItem in standaloneItems) {
        final itemId = standaloneItem['id'] as int;
        final match = specialFees.firstWhere(
          (fee) => fee['specialFeeItemId'] == itemId,
          orElse: () => {},
        );
        final amount = (match['amount'] as num?)?.toDouble() ?? 0.0;
        classArmStandaloneAmounts[key]![itemId] = amount;
      }

      classArmCategoryChildAmounts[key] = {};
      for (var category in categories) {
        final categoryId = category['id'] as int;
        classArmCategoryChildAmounts[key]![categoryId] = {};

        final children = childItemsMap[categoryId] ?? [];
        for (var child in children) {
          final childId = child['id'] as int;
          final match = specialFees.firstWhere(
            (fee) => fee['specialFeeItemId'] == childId,
            orElse: () => {},
          );
          final amount = (match['amount'] as num?)?.toDouble() ?? 0.0;
          classArmCategoryChildAmounts[key]![categoryId]![childId] = amount;
        }
      }
    }

    // Collect all unique regular fee items
    Map<int, String> allRegularFeeItems = {};
    for (var classArm in classes) {
      final classId = classArm['classId'] as int;
      final armId = classArm['armId'] as int?;
      final key = '${classId}_${armId ?? ''}';
      final regularFees = classArmRegularFees[key] ?? [];
      for (var fee in regularFees) {
        final feeItemId = fee['feeItemId'] as int;
        final feeItemName = fee['feeItemName'] ?? 'Unknown';
        if (!allRegularFeeItems.containsKey(feeItemId)) {
          allRegularFeeItems[feeItemId] = feeItemName;
        }
      }
    }

    // Build map of regular fee amounts
    final Map<String, Map<int, double>> classArmRegularFeeAmounts = {};
    for (var classArm in classes) {
      final classId = classArm['classId'] as int;
      final armId = classArm['armId'] as int?;
      final key = '${classId}_${armId ?? ''}';
      classArmRegularFeeAmounts[key] = {};
      final regularFees = classArmRegularFees[key] ?? [];
      for (var fee in regularFees) {
        final feeItemId = fee['feeItemId'] as int;
        final amount = (fee['amount'] as num?)?.toDouble() ?? 0.0;
        classArmRegularFeeAmounts[key]![feeItemId] = amount;
      }
    }

    // Default Bill section (with header and children)
    bool hasDefaultBillAmount = classArmRegularTotals.values.any((amount) => amount >= 1.0);
    if (hasDefaultBillAmount && allRegularFeeItems.isNotEmpty) {
      // Header row
      rows.add(pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey100),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text('Default Bill', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
          ),
          ...classes.map((classArm) {
            return pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(''),
            );
          }),
        ],
      ));

      // Individual fee items
      for (var entry in allRegularFeeItems.entries) {
        final feeItemId = entry.key;
        final feeItemName = entry.value;

        bool hasFeeAmount = false;
        for (var classArm in classes) {
          final classId = classArm['classId'] as int;
          final armId = classArm['armId'] as int?;
          final key = '${classId}_${armId ?? ''}';
          final amount = classArmRegularFeeAmounts[key]?[feeItemId] ?? 0.0;
          if (amount >= 1.0) {
            hasFeeAmount = true;
            break;
          }
        }

        if (hasFeeAmount) {
          rows.add(pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 12, top: 4, bottom: 4, right: 4),
                child: pw.Text('-$feeItemName', style: const pw.TextStyle(fontSize: 8)),
              ),
              ...classes.map((classArm) {
                final classId = classArm['classId'] as int;
                final armId = classArm['armId'] as int?;
                final key = '${classId}_${armId ?? ''}';
                final amount = classArmRegularFeeAmounts[key]?[feeItemId] ?? 0.0;
                return pw.Padding(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('N${currencyFormat.format(amount)}', style: const pw.TextStyle(fontSize: 8)),
                );
              }),
            ],
          ));
        }
      }
    }

    // Other Fees section (standalone items with header)
    bool hasStandaloneAmount = false;
    for (var standaloneItem in standaloneItems) {
      final itemId = standaloneItem['id'] as int;
      for (var classArm in classes) {
        final classId = classArm['classId'] as int;
        final armId = classArm['armId'] as int?;
        final key = '${classId}_${armId ?? ''}';
        final amount = classArmStandaloneAmounts[key]?[itemId] ?? 0.0;
        if (amount >= 1.0) {
          hasStandaloneAmount = true;
          break;
        }
      }
      if (hasStandaloneAmount) break;
    }

    if (hasStandaloneAmount) {
      // Header row
      rows.add(pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.orange50),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text('Other Fees', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
          ),
          ...classes.map((classArm) {
            return pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(''),
            );
          }),
        ],
      ));

      // Individual standalone items
      for (var standaloneItem in standaloneItems) {
        final itemId = standaloneItem['id'] as int;
        final itemName = standaloneItem['name'] ?? 'Unknown';

        bool hasAmount = false;
        for (var classArm in classes) {
          final classId = classArm['classId'] as int;
          final armId = classArm['armId'] as int?;
          final key = '${classId}_${armId ?? ''}';
          final amount = classArmStandaloneAmounts[key]?[itemId] ?? 0.0;
          if (amount >= 1.0) {
            hasAmount = true;
            break;
          }
        }

        if (hasAmount) {
          rows.add(pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 12, top: 4, bottom: 4, right: 4),
                child: pw.Text('-$itemName', style: const pw.TextStyle(fontSize: 8)),
              ),
              ...classes.map((classArm) {
                final classId = classArm['classId'] as int;
                final armId = classArm['armId'] as int?;
                final key = '${classId}_${armId ?? ''}';
                final amount = classArmStandaloneAmounts[key]?[itemId] ?? 0.0;
                return pw.Padding(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('N${currencyFormat.format(amount)}', style: const pw.TextStyle(fontSize: 8)),
                );
              }),
            ],
          ));
        }
      }
    }

    // Categories and children rows
    for (var category in categories) {
      final categoryId = category['id'] as int;
      final categoryName = category['name'] ?? 'Unknown Category';
      final children = childItemsMap[categoryId] ?? [];

      if (children.isEmpty) continue;

      bool categoryHasAmount = false;
      for (var child in children) {
        final childId = child['id'] as int;
        for (var classArm in classes) {
          final classId = classArm['classId'] as int;
          final armId = classArm['armId'] as int?;
          final key = '${classId}_${armId ?? ''}';
          final amount = classArmCategoryChildAmounts[key]?[categoryId]?[childId] ?? 0.0;
          if (amount >= 1.0) {
            categoryHasAmount = true;
            break;
          }
        }
        if (categoryHasAmount) break;
      }

      if (!categoryHasAmount) continue;

      // Category header row
      rows.add(pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(
              categoryName,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
            ),
          ),
          ...classes.map((classArm) {
            return pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(''),
            );
          }),
        ],
      ));

      // Children rows
      for (var child in children) {
        final childId = child['id'] as int;
        final childName = child['name'] ?? 'Unknown';

        bool childHasAmount = false;
        for (var classArm in classes) {
          final classId = classArm['classId'] as int;
          final armId = classArm['armId'] as int?;
          final key = '${classId}_${armId ?? ''}';
          final amount = classArmCategoryChildAmounts[key]?[categoryId]?[childId] ?? 0.0;
          if (amount >= 1.0) {
            childHasAmount = true;
            break;
          }
        }

        if (childHasAmount) {
          rows.add(pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 12, top: 4, bottom: 4, right: 4),
                child: pw.Text('-$childName', style: const pw.TextStyle(fontSize: 8)),
              ),
              ...classes.map((classArm) {
                final classId = classArm['classId'] as int;
                final armId = classArm['armId'] as int?;
                final key = '${classId}_${armId ?? ''}';
                final amount = classArmCategoryChildAmounts[key]?[categoryId]?[childId] ?? 0.0;
                return pw.Padding(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text('N${currencyFormat.format(amount)}', style: const pw.TextStyle(fontSize: 8)),
                );
              }),
            ],
          ));
        }
      }
    }

    // Grand Total row
    rows.add(pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Text(
            'GRAND TOTAL',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          ),
        ),
        ...classes.map((classArm) {
          final classId = classArm['classId'] as int;
          final armId = classArm['armId'] as int?;
          final key = '${classId}_${armId ?? ''}';
          final billData = classArmBills[key] ?? {};

          final regularTotal = (billData['regularTotal'] as num?)?.toDouble() ?? 0.0;
          final specialTotal = (billData['specialTotal'] as num?)?.toDouble() ?? 0.0;
          final grandTotal = regularTotal + specialTotal;

          return pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(
              'N${currencyFormat.format(grandTotal)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            ),
          );
        }),
      ],
    ));

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey),
      children: rows,
    );
  }

  static pw.Widget _buildBankDetails(Map<String, dynamic> schoolProfile) {
    final accounts = <String>[];
    for (int i = 1; i <= 3; i++) {
      final bankName = schoolProfile['bankName$i']?.toString() ?? '';
      final accNum = schoolProfile['accountNumber$i']?.toString() ?? '';
      final accName = schoolProfile['accountName$i']?.toString() ?? '';
      if (bankName.isNotEmpty && accNum.isNotEmpty) {
        accounts.add('$bankName - $accNum - $accName');
      }
    }
    if (accounts.isEmpty) return pw.SizedBox();

    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: PdfColors.blue200),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Bank Account Details:',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
          pw.SizedBox(height: 4),
          ...accounts.map((acc) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Text(acc, style: const pw.TextStyle(fontSize: 9, color: PdfColors.blue800)),
          )),
        ],
      ),
    );
  }

  static pw.Widget _buildPageFooter(pw.Context context) {
    final now = DateTime.now();
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated: ${dateFormat.format(now)}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }
}
