import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/all_classes_new_intake_bills_pdf_generator.dart';

class AllClassesBillsScreen extends StatefulWidget {
  const AllClassesBillsScreen({super.key});

  @override
  State<AllClassesBillsScreen> createState() => _AllClassesBillsScreenState();
}

class _AllClassesBillsScreenState extends State<AllClassesBillsScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  String? _activeTerm;
  String? _activeSession;
  bool _loading = true;
  bool _exporting = false;

  Map<String, dynamic>? _schoolProfile;
  List<Map<String, dynamic>> _allClasses = [];
  final List<Map<String, dynamic>> _allClassArms = []; // Class-arm combinations for display
  final Map<String, Map<String, dynamic>> _classArmBills = {}; // "classId_armId" -> bill data

  List<Map<String, dynamic>> _categories = []; // Special fee categories
  List<Map<String, dynamic>> _standaloneItems = []; // Standalone special fee items
  final Map<int, List<Map<String, dynamic>>> _childItemsMap = {}; // Children by category ID

  // Grouped classes by type
  List<Map<String, dynamic>> _prePrimaryClasses = [];
  List<Map<String, dynamic>> _primaryClasses = [];
  List<Map<String, dynamic>> _juniorSecondaryClasses = [];
  List<Map<String, dynamic>> _seniorSecondaryClasses = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    _activeTerm = await _db.getActiveTerm();
    _activeSession = (await _db.getActiveSession())?['sessionName'] ?? "";
    _schoolProfile = await _db.getSchoolProfile();

    // Load all classes
    _allClasses = await _db.getClasses();

    // Load special fee items structure
    _categories = await _db.getSpecialFeeItemCategories(
      term: _activeTerm,
      session: _activeSession,
    );

    _standaloneItems = await _db.getSpecialFeeItemStandalone(
      term: _activeTerm,
      session: _activeSession,
    );

    // Load children for each category
    _childItemsMap.clear();
    for (var category in _categories) {
      final categoryId = category['id'] as int;
      final children = await _db.getSpecialFeeItemChildren(
        categoryId,
        term: _activeTerm,
        session: _activeSession,
      );
      _childItemsMap[categoryId] = children;
    }

    // Load class-arm combinations and their bills
    _allClassArms.clear();
    _classArmBills.clear();

    final db = await _db.database;
    for (var cls in _allClasses) {
      final classId = cls['id'] as int;
      final className = cls['name'] as String;

      // Get arms for this class
      final arms = await db.query(
        'arms',
        where: 'classId = ?',
        whereArgs: [classId],
        orderBy: 'name ASC',
      );

      if (arms.isEmpty) {
        // Class has no arms, add it without arm
        _allClassArms.add({
          'classId': classId,
          'className': className,
          'armId': null,
          'armName': null,
          'displayName': className,
        });

        final billData = await _db.getNewIntakeBillForClass(
          classId,
          _activeTerm ?? "",
          _activeSession ?? "",
        );
        _classArmBills['${classId}_'] = billData;
      } else {
        // Class has arms, add each arm as separate column
        for (var arm in arms) {
          final armId = arm['id'] as int;
          final armName = arm['name'] as String;

          _allClassArms.add({
            'classId': classId,
            'className': className,
            'armId': armId,
            'armName': armName,
            'displayName': '$className - $armName',
          });

          final billData = await _db.getNewIntakeBillForClass(
            classId,
            _activeTerm ?? "",
            _activeSession ?? "",
            armId: armId,
          );
          _classArmBills['${classId}_$armId'] = billData;
        }
      }
    }

    // Categorize class-arms by type (must be done after _allClassArms is populated)
    _categorizeClasses();

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _categorizeClasses() {
    _prePrimaryClasses = [];
    _primaryClasses = [];
    _juniorSecondaryClasses = [];
    _seniorSecondaryClasses = [];

    // Categorize class-arm combinations by class type
    for (var classArm in _allClassArms) {
      final className = (classArm['className'] ?? '').toString().toLowerCase();

      if (className.contains('primary') ||
          className.contains('grade') ||
          className.contains('basic 1') ||
          className.contains('basic 2') ||
          className.contains('basic 3') ||
          className.contains('basic 4') ||
          className.contains('basic 5') ||
          className.contains('basic 6')) {
        _primaryClasses.add(classArm);
      } else if (className.contains('jss') ||
          className.contains('junior') ||
          className.contains('basic 7') ||
          className.contains('basic 8') ||
          className.contains('basic 9')) {
        _juniorSecondaryClasses.add(classArm);
      } else if (className.contains('sss') ||
          className.contains('senior') ||
          className.contains('ss ')) {
        _seniorSecondaryClasses.add(classArm);
      } else {
        // Default to pre-primary for any class that doesn't match primary, junior, or senior
        _prePrimaryClasses.add(classArm);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("New Intake Bills - All Classes"),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _exportToPDF,
            tooltip: 'Export as PDF',
          ),
          IconButton(
            icon: const Icon(Icons.image),
            onPressed: _exportToJPEG,
            tooltip: 'Export as JPEG',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: Column(
                  children: [
                    // Header Info
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.deepOrange.shade50,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'New Intake Bills Summary - All Classes',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepOrange.shade900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.event, size: 18, color: Colors.deepOrange.shade700),
                              const SizedBox(width: 8),
                              Text(
                                'Term: $_activeTerm | Session: $_activeSession',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Pre-Primary Section
                    if (_prePrimaryClasses.isNotEmpty)
                      _buildClassTypeSection(
                        'PRE-PRIMARY',
                        _prePrimaryClasses,
                        Colors.purple,
                      ),

                    // Primary Section
                    if (_primaryClasses.isNotEmpty)
                      _buildClassTypeSection(
                        'PRIMARY',
                        _primaryClasses,
                        Colors.blue,
                      ),

                    // Junior Secondary Section
                    if (_juniorSecondaryClasses.isNotEmpty)
                      _buildClassTypeSection(
                        'JUNIOR SECONDARY',
                        _juniorSecondaryClasses,
                        Colors.green,
                      ),

                    // Senior Secondary Section
                    if (_seniorSecondaryClasses.isNotEmpty)
                      _buildClassTypeSection(
                        'SENIOR SECONDARY',
                        _seniorSecondaryClasses,
                        Colors.orange,
                      ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildClassTypeSection(
    String sectionTitle,
    List<Map<String, dynamic>> classes,
    MaterialColor sectionColor,
  ) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: sectionColor.shade300, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: sectionColor.shade100,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              children: [
                Icon(Icons.school, color: sectionColor.shade700, size: 24),
                const SizedBox(width: 12),
                Text(
                  'New Intake Bills for $sectionTitle Classes',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: sectionColor.shade900,
                  ),
                ),
              ],
            ),
          ),

          // Table
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _buildBillsTable(classes, sectionColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillsTable(List<Map<String, dynamic>> classes, MaterialColor sectionColor) {
    return DataTable(
      headingRowColor: WidgetStateProperty.all(sectionColor.shade100),
      border: TableBorder.all(color: Colors.grey.shade300),
      columns: [
        const DataColumn(
          label: Text(
            'Fee Category',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        ...classes.map((classArm) {
          return DataColumn(
            label: Text(
              classArm['displayName'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          );
        }),
      ],
      rows: _buildTableRows(classes, sectionColor),
    );
  }

  List<DataRow> _buildTableRows(List<Map<String, dynamic>> classes, MaterialColor sectionColor) {
    List<DataRow> rows = [];
    final currencyFormat = NumberFormat('#,##0.00', 'en_US');

    // Build map of class-arm fees and special fees
    final Map<String, double> classArmRegularTotals = {};
    final Map<String, List<Map<String, dynamic>>> classArmRegularFees = {}; // key -> regularFees list
    final Map<String, Map<int, double>> classArmStandaloneAmounts = {}; // key -> {itemId -> amount}
    final Map<String, Map<int, Map<int, double>>> classArmCategoryChildAmounts = {}; // key -> {categoryId -> {childId -> amount}}

    for (var classArm in classes) {
      final classId = classArm['classId'] as int;
      final armId = classArm['armId'] as int?;
      final key = '${classId}_${armId ?? ''}';
      final billData = _classArmBills[key] ?? {};

      // Get regular fees and total
      final regularFees = List<Map<String, dynamic>>.from(billData['regularFees'] ?? []);
      final regularTotal = (billData['regularTotal'] as num?)?.toDouble() ?? 0.0;
      classArmRegularFees[key] = regularFees;
      classArmRegularTotals[key] = regularTotal;

      // Get special fees
      final specialFees = List<Map<String, dynamic>>.from(billData['specialFees'] ?? []);

      // Map standalone items
      classArmStandaloneAmounts[key] = {};
      for (var standaloneItem in _standaloneItems) {
        final itemId = standaloneItem['id'] as int;
        final match = specialFees.firstWhere(
          (fee) => fee['specialFeeItemId'] == itemId,
          orElse: () => {},
        );
        final amount = (match['amount'] as num?)?.toDouble() ?? 0.0;
        classArmStandaloneAmounts[key]![itemId] = amount;
      }

      // Map category children
      classArmCategoryChildAmounts[key] = {};
      for (var category in _categories) {
        final categoryId = category['id'] as int;
        classArmCategoryChildAmounts[key]![categoryId] = {};

        final children = _childItemsMap[categoryId] ?? [];
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

    // Collect all unique regular fee items across all class-arms
    Map<int, String> allRegularFeeItems = {}; // feeItemId -> feeItemName
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

    // Build map of regular fee amounts by feeItemId for each class-arm
    final Map<String, Map<int, double>> classArmRegularFeeAmounts = {}; // key -> {feeItemId -> amount}
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

    // Section: Default Bill (with individual fee items as children)
    bool hasDefaultBillAmount = classArmRegularTotals.values.any((amount) => amount >= 1.0);

    if (hasDefaultBillAmount && allRegularFeeItems.isNotEmpty) {
      // Category header row for Default Bill
      rows.add(DataRow(
        color: WidgetStateProperty.all(Colors.grey.shade100),
        cells: [
          const DataCell(
            Text(
              'Default Bill',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
          ...classes.map((classArm) {
            return const DataCell(Text('')); // Empty cells for category header
          }),
        ],
      ));

      // Children rows - individual fee items
      for (var entry in allRegularFeeItems.entries) {
        final feeItemId = entry.key;
        final feeItemName = entry.value;

        // Check if at least one class-arm has this fee item with amount >= 1
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
          rows.add(DataRow(
            cells: [
              DataCell(
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    '• $feeItemName',
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  ),
                ),
              ),
              ...classes.map((classArm) {
                final classId = classArm['classId'] as int;
                final armId = classArm['armId'] as int?;
                final key = '${classId}_${armId ?? ''}';
                final amount = classArmRegularFeeAmounts[key]?[feeItemId] ?? 0.0;
                return DataCell(Text(
                  '₦${currencyFormat.format(amount)}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ));
              }),
            ],
          ));
        }
      }
    }

    // Section: Standalone Items (with header)
    bool hasStandaloneAmount = false;
    for (var standaloneItem in _standaloneItems) {
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
      // Category header row for Other Fees
      rows.add(DataRow(
        color: WidgetStateProperty.all(Colors.orange.shade50),
        cells: [
          DataCell(
            Text(
              'Other Fees',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.orange.shade900,
              ),
            ),
          ),
          ...classes.map((classArm) {
            return const DataCell(Text('')); // Empty cells for category header
          }),
        ],
      ));

      // Children rows - individual standalone items
      for (var standaloneItem in _standaloneItems) {
        final itemId = standaloneItem['id'] as int;
        final itemName = standaloneItem['name'] ?? 'Unknown';

        // Check if at least one amount is >= 1
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
          rows.add(DataRow(
            cells: [
              DataCell(
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    '• $itemName',
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  ),
                ),
              ),
              ...classes.map((classArm) {
                final classId = classArm['classId'] as int;
                final armId = classArm['armId'] as int?;
                final key = '${classId}_${armId ?? ''}';
                final amount = classArmStandaloneAmounts[key]?[itemId] ?? 0.0;
                return DataCell(Text(
                  '₦${currencyFormat.format(amount)}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ));
              }),
            ],
          ));
        }
      }
    }

    // Rows: Categories and their children
    for (var category in _categories) {
      final categoryId = category['id'] as int;
      final categoryName = category['name'] ?? 'Unknown Category';
      final children = _childItemsMap[categoryId] ?? [];

      if (children.isEmpty) continue;

      // Check if at least one child has an amount >= 1 across all class-arms
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

      // Only show category if it has at least one child with amount >= 1
      if (!categoryHasAmount) continue;

      // Category header row
      rows.add(DataRow(
        color: WidgetStateProperty.all(sectionColor.shade50),
        cells: [
          DataCell(
            Text(
              categoryName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: sectionColor.shade900,
              ),
            ),
          ),
          ...classes.map((classArm) {
            return const DataCell(Text('')); // Empty cells for category header
          }),
        ],
      ));

      // Children rows
      for (var child in children) {
        final childId = child['id'] as int;
        final childName = child['name'] ?? 'Unknown';

        // Check if this child has at least one amount >= 1
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
          rows.add(DataRow(
            cells: [
              DataCell(
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    '• $childName',
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  ),
                ),
              ),
              ...classes.map((classArm) {
                final classId = classArm['classId'] as int;
                final armId = classArm['armId'] as int?;
                final key = '${classId}_${armId ?? ''}';
                final amount = classArmCategoryChildAmounts[key]?[categoryId]?[childId] ?? 0.0;
                return DataCell(Text(
                  '₦${currencyFormat.format(amount)}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ));
              }),
            ],
          ));
        }
      }
    }

    // Grand Total Row
    rows.add(DataRow(
      color: WidgetStateProperty.all(sectionColor.shade100),
      cells: [
        DataCell(
          Text(
            'GRAND TOTAL',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: sectionColor.shade900,
            ),
          ),
        ),
        ...classes.map((classArm) {
          final classId = classArm['classId'] as int;
          final armId = classArm['armId'] as int?;
          final key = '${classId}_${armId ?? ''}';
          final billData = _classArmBills[key] ?? {};

          final regularTotal = (billData['regularTotal'] as num?)?.toDouble() ?? 0.0;
          final specialTotal = (billData['specialTotal'] as num?)?.toDouble() ?? 0.0;
          final grandTotal = regularTotal + specialTotal;

          return DataCell(Text(
            '₦${currencyFormat.format(grandTotal)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: sectionColor.shade900,
            ),
          ));
        }),
      ],
    ));

    return rows;
  }

  Future<void> _exportToPDF() async {
    if (_schoolProfile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('School profile not loaded')),
      );
      return;
    }

    setState(() => _exporting = true);

    try {
      // Organize classes by type for PDF
      final classesByType = <String, List<Map<String, dynamic>>>{
        'PRE-PRIMARY': _prePrimaryClasses,
        'PRIMARY': _primaryClasses,
        'JUNIOR SECONDARY': _juniorSecondaryClasses,
        'SENIOR SECONDARY': _seniorSecondaryClasses,
      };

      // Remove empty sections
      classesByType.removeWhere((key, value) => value.isEmpty);

      final filePath = await AllClassesNewIntakeBillsPDFGenerator.generatePDF(
        term: _activeTerm ?? '',
        session: _activeSession ?? '',
        schoolProfile: _schoolProfile!,
        classesByType: classesByType,
        classArmBills: _classArmBills,
        categories: _categories,
        standaloneItems: _standaloneItems,
        childItemsMap: _childItemsMap,
      );

      setState(() => _exporting = false);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF exported successfully to:\n$filePath'),
          duration: const Duration(seconds: 5),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    } catch (e) {
      setState(() => _exporting = false);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error exporting PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _exportToJPEG() async {
    setState(() => _exporting = true);

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('JPEG export is not yet fully implemented. Use PDF export instead.'),
          backgroundColor: Colors.orange,
        ),
      );

      setState(() => _exporting = false);
    } catch (e) {
      setState(() => _exporting = false);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error exporting JPEG: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
