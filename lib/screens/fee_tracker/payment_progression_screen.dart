import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/fee_priority_helper.dart';
import '../../utils/payment_progression_pdf_generator.dart';
import '../../utils/sibling_helper.dart';
import '../../widgets/sibling_mark.dart';

class PaymentProgressionScreen extends StatefulWidget {
  const PaymentProgressionScreen({super.key});

  @override
  State<PaymentProgressionScreen> createState() =>
      _PaymentProgressionScreenState();
}

class _PaymentProgressionScreenState extends State<PaymentProgressionScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final NumberFormat _currencyFormat =
      NumberFormat.currency(symbol: 'N', decimalDigits: 2);

  // Filter state
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _arms = [];
  int? _selectedClassId;
  int? _selectedArmId;

  // Session/term
  String _activeTerm = '';
  String _activeSession = '';

  // Data state
  bool _isLoading = false;
  bool _hasLoaded = false;
  bool _isExporting = false;
  List<_StudentProgression> _students = [];
  bool _noPrioritiesWarning = false;
  Set<String> _siblingPhones = {};

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final term = await _db.getActiveTerm();
      final session = await _db.getActiveSession();
      final classes = await _db.getClasses();

      if (!mounted) return;
      setState(() {
        _activeTerm = term;
        _activeSession = session?['sessionName'] ?? '';
        _classes = classes;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading data: $e')),
      );
    }
  }

  Future<void> _onClassChanged(int? classId) async {
    setState(() {
      _selectedClassId = classId;
      _selectedArmId = null;
      _arms = [];
    });

    if (classId != null) {
      try {
        final arms = await _db.getArmsByClass(classId);
        if (!mounted) return;
        setState(() {
          _arms = arms;
        });
      } catch (_) {}
    }
  }

  Future<void> _loadProgressionData() async {
    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a class first')),
      );
      return;
    }
    if (_arms.isNotEmpty && _selectedArmId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an arm')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _hasLoaded = false;
      _students = [];
      _noPrioritiesWarning = false;
    });

    try {
      // Fetch students with payment data
      final rawStudents = await _db.getPaymentProgressionData(
        term: _activeTerm,
        session: _activeSession,
        classId: _selectedClassId,
        armId: _selectedArmId,
      );

      // Fetch effective priorities for the selected class/arm
      final priorities = await _db.getEffectiveFeePriorities(
        classId: _selectedClassId!,
        armId: _selectedArmId,
        term: _activeTerm,
        session: _activeSession,
      );

      final bool hasPriorities = priorities.isNotEmpty;

      // Sort priorities once, ascending
      final sortedPriorities = List<Map<String, dynamic>>.from(priorities)
        ..sort((a, b) => (a['priority'] as int).compareTo(b['priority'] as int));

      // All feeItemIds explicitly named in priorities (excludes virtual -1, -2)
      final namedPriorityIds = sortedPriorities
          .map((p) => p['feeItemId'] as int)
          .where((id) => id > 0)
          .toSet();

      // Pre-load fee item names for lookup when breakdown label is missing
      final allFeeItems = await _db.getFeeItems(
        term: _activeTerm,
        session: _activeSession,
      );
      final Map<int, String> feeItemNameMap = {};
      for (final fi in allFeeItems) {
        feeItemNameMap[fi['id'] as int] = fi['name'] as String? ?? '';
      }

      final List<_StudentProgression> students = [];

      for (final raw in rawStudents) {
        // Skip students with no bill
        if (raw['billId'] == null) continue;

        final int billId = raw['billId'] as int;
        // Use fresh values: currentTermFee strips the stale baked-in carry-over;
        // freshPreviousBalance is recomputed live from prev-term bills minus payments.
        final double currentTermFee = (raw['currentTermFee'] as num?)?.toDouble() ?? 0.0;
        final double previousBalance = ((raw['freshPreviousBalance'] as num?)?.toDouble() ?? 0.0).clamp(0.0, double.infinity);
        final double billTotal = currentTermFee + previousBalance;
        final double totalPaid = (raw['totalPaid'] as num?)?.toDouble() ?? 0.0;

        // Get bill breakdown for this student
        final breakdown = await _db.getBillBreakdown(billId);

        // Build prioritized fees list respecting Set Bill Priority order,
        // including the -2 "Student-Specific Extras" virtual slot.
        final List<Map<String, dynamic>> prioritizedFees = [];
        final coveredFeeItemIds = <int>{};

        if (sortedPriorities.isNotEmpty) {
          for (final p in sortedPriorities) {
            final pFeeItemId = p['feeItemId'] as int;

            if (pFeeItemId == -2) {
              // Group all student-specific extras into one slot
              double extrasTotal = 0.0;
              for (final b in breakdown) {
                final id = b['feeItemId'] as int;
                if (!namedPriorityIds.contains(id) && id > 0 &&
                    !coveredFeeItemIds.contains(id)) {
                  extrasTotal += (b['amount'] as num).toDouble();
                  coveredFeeItemIds.add(id);
                }
              }
              if (extrasTotal > 0) {
                prioritizedFees.add({
                  'feeItemId': -2,
                  'feeName': 'Student-Specific Extras',
                  'amount': extrasTotal,
                });
                coveredFeeItemIds.add(-2);
              }
            } else if (pFeeItemId == -1) {
              if (previousBalance > 0) {
                prioritizedFees.add({
                  'feeItemId': -1,
                  'feeName': 'Previous Balance',
                  'amount': previousBalance,
                });
                coveredFeeItemIds.add(-1);
              }
            } else {
              final match = breakdown.firstWhere(
                (b) => b['feeItemId'] == pFeeItemId,
                orElse: () => <String, dynamic>{},
              );
              if (match.isNotEmpty) {
                String label = match['label'] as String? ?? '';
                if (label.isEmpty) {
                  label = feeItemNameMap[pFeeItemId] ?? 'Fee Item #$pFeeItemId';
                }
                prioritizedFees.add({
                  'feeItemId': pFeeItemId,
                  'feeName': label,
                  'amount': (match['amount'] as num).toDouble(),
                });
                coveredFeeItemIds.add(pFeeItemId);
              }
            }
          }
        }

        // Fallback: any breakdown item not yet covered (no priorities set, or new item added after priority was saved)
        for (final b in breakdown) {
          final id = b['feeItemId'] as int;
          if (!coveredFeeItemIds.contains(id) && id > 0) {
            String label = b['label'] as String? ?? '';
            if (label.isEmpty) label = feeItemNameMap[id] ?? 'Fee Item #$id';
            prioritizedFees.add({
              'feeItemId': id,
              'feeName': label,
              'amount': (b['amount'] as num).toDouble(),
            });
          }
        }
        if (previousBalance > 0 && !coveredFeeItemIds.contains(-1)) {
          prioritizedFees.add({
            'feeItemId': -1,
            'feeName': 'Previous Balance',
            'amount': previousBalance,
          });
        }

        // Total fees including previous balance
        final double currentTermFees = billTotal;

        // Compute progression using totalPaid against all fees
        final progression = FeePriorityHelper.computeProgression(
          prioritizedFees: prioritizedFees,
          totalPaid: totalPaid,
        );

        students.add(_StudentProgression(
          studentId: raw['studentId'] as int,
          admissionNo: raw['admissionNo']?.toString() ?? '',
          surname: raw['surname']?.toString() ?? '',
          firstName: raw['firstName']?.toString() ?? '',
          className: raw['className']?.toString() ?? '',
          armName: raw['armName']?.toString() ?? '',
          parentPhone: raw['parentPhone'] as String?,
          billTotal: billTotal,
          previousBalance: previousBalance,
          totalPaid: totalPaid,
          currentTermFees: currentTermFees,
          progression: progression,
        ));
      }

      final siblingPhones = computeSiblingPhones(await _db.getActiveStudents());

      if (!mounted) return;
      setState(() {
        _students = students;
        _siblingPhones = siblingPhones;
        _hasLoaded = true;
        _isLoading = false;
        _noPrioritiesWarning = !hasPriorities;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasLoaded = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading progression data: $e')),
      );
    }
  }

  double _computeCoverage(_StudentProgression student) {
    if (student.currentTermFees <= 0) return 1.0;
    return (student.totalPaid / student.currentTermFees).clamp(0.0, 1.0);
  }

  Color _coverageColor(double coverage) {
    if (coverage > 0.8) return Colors.green;
    if (coverage >= 0.4) return Colors.orange;
    return Colors.red;
  }

  Future<void> _exportPdf() async {
    if (_students.isEmpty) return;

    setState(() => _isExporting = true);

    try {
      final schoolProfile = await _db.getSchoolProfile() ?? {};

      final className = _students.isNotEmpty ? _students.first.className : '';
      final armName = _students.isNotEmpty ? _students.first.armName : '';

      // Build student maps with progression for the PDF generator
      final studentMaps = _students.map((s) => {
        'surname': s.surname,
        'firstName': s.firstName,
        'admissionNo': s.admissionNo,
        'className': s.className,
        'armName': s.armName,
        'billTotal': s.billTotal,
        'totalPaid': s.totalPaid,
        'progression': s.progression,
      }).toList();

      final path = await PaymentProgressionPdfGenerator.generate(
        students: studentMaps,
        term: _activeTerm,
        session: _activeSession,
        className: className,
        armName: armName,
        schoolProfile: schoolProfile,
      );

      if (!mounted) return;
      await Share.shareXFiles([XFile(path)], subject: 'Payment Progression Report');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Progression'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          if (_hasLoaded && _students.isNotEmpty)
            _isExporting
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.picture_as_pdf),
                    tooltip: 'Export PDF',
                    onPressed: _exportPdf,
                  ),
        ],
      ),
      body: _buildPageBody(),
    );
  }

  Widget _buildFilterSection() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _selectedClassId,
              decoration: const InputDecoration(
                labelText: 'Class',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              hint: const Text('Select a class'),
              items: _classes.map((c) {
                return DropdownMenuItem<int>(
                  value: c['id'] as int,
                  child: Text(c['name'] as String? ?? 'Unknown'),
                );
              }).toList(),
              onChanged: _onClassChanged,
            ),
            if (_arms.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _selectedArmId,
                decoration: const InputDecoration(
                  labelText: 'Arm',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                hint: const Text('Select an arm'),
                items: _arms.map((a) {
                  return DropdownMenuItem<int>(
                    value: a['id'] as int,
                    child: Text(a['name'] as String? ?? 'Unknown'),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedArmId = value;
                  });
                },
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _isLoading ? null : _loadProgressionData,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Load'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryItem({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.green, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildPageBody() {
    // Before load or when loading, keep filter fixed with centered message below
    if (_isLoading) {
      return Column(
        children: [
          _buildFilterSection(),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    if (!_hasLoaded) {
      return Column(
        children: [
          _buildFilterSection(),
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.filter_list, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Select a class and press Load',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (_students.isEmpty) {
      return Column(
        children: [
          _buildFilterSection(),
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_off, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No students found',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // With results: scroll the whole page
    final int totalStudents = _students.length;
    final double avgCoverage = totalStudents > 0
        ? _students.map(_computeCoverage).reduce((a, b) => a + b) /
            totalStudents
        : 0.0;
    final int fullyPaid =
        _students.where((s) => _computeCoverage(s) >= 1.0).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFilterSection(),

          // No priorities warning
          if (_noPrioritiesWarning)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: MaterialBanner(
                backgroundColor: Colors.amber.shade50,
                leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                content: const Text(
                  'No fee priorities set. Items shown in default order. '
                  'Go to Set Bill Priority to configure.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {},
                    child: const Text('DISMISS'),
                  ),
                ],
              ),
            ),

          // Summary card
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _summaryItem(
                    label: 'Students',
                    value: totalStudents.toString(),
                    icon: Icons.people,
                  ),
                  _summaryItem(
                    label: 'Avg Coverage',
                    value: '${(avgCoverage * 100).toStringAsFixed(1)}%',
                    icon: Icons.pie_chart,
                  ),
                  _summaryItem(
                    label: 'Fully Paid',
                    value: fullyPaid.toString(),
                    icon: Icons.check_circle,
                  ),
                ],
              ),
            ),
          ),

          // Student cards inline
          ...List.generate(_students.length, (index) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: _StudentProgressionCard(
                student: _students[index],
                currencyFormat: _currencyFormat,
                coverageColor: _coverageColor,
                computeCoverage: _computeCoverage,
                isSibling: isSiblingPhone(_students[index].parentPhone, _siblingPhones),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class _StudentProgression {
  final int studentId;
  final String admissionNo;
  final String surname;
  final String firstName;
  final String className;
  final String armName;
  final String? parentPhone;
  final double billTotal;
  final double previousBalance;
  final double totalPaid;
  final double currentTermFees;
  final List<Map<String, dynamic>> progression;

  _StudentProgression({
    required this.studentId,
    required this.admissionNo,
    required this.surname,
    required this.firstName,
    required this.className,
    required this.armName,
    this.parentPhone,
    required this.billTotal,
    required this.previousBalance,
    required this.totalPaid,
    required this.currentTermFees,
    required this.progression,
  });
}

// ---------------------------------------------------------------------------
// Student card with expansion
// ---------------------------------------------------------------------------

class _StudentProgressionCard extends StatefulWidget {
  final _StudentProgression student;
  final NumberFormat currencyFormat;
  final Color Function(double) coverageColor;
  final double Function(_StudentProgression) computeCoverage;
  final bool isSibling;

  const _StudentProgressionCard({
    required this.student,
    required this.currencyFormat,
    required this.coverageColor,
    required this.computeCoverage,
    this.isSibling = false,
  });

  @override
  State<_StudentProgressionCard> createState() =>
      _StudentProgressionCardState();
}

class _StudentProgressionCardState extends State<_StudentProgressionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final student = widget.student;
    final coverage = widget.computeCoverage(student);
    final avatarColor = widget.coverageColor(coverage);
    final firstLetter =
        student.surname.isNotEmpty ? student.surname[0].toUpperCase() : '?';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: avatarColor,
                    foregroundColor: Colors.white,
                    child: Text(firstLetter),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '${student.surname}, ${student.firstName}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SiblingMark(show: widget.isSibling),
                          ],
                        ),
                        Text(
                          'Adm: ${student.admissionNo}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${widget.currencyFormat.format(student.totalPaid)} / '
                    '${widget.currencyFormat.format(student.billTotal)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Progression bar
              _buildProgressionBar(student),
              // Expanded detail
              if (_expanded) ...[
                const Divider(height: 24),
                _buildExpandedDetail(student),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressionBar(_StudentProgression student) {
    final progression = student.progression;
    if (progression.isEmpty) {
      return Container(
        height: 24,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: const Text('No fee items', style: TextStyle(fontSize: 11)),
      );
    }

    final double totalAmount = progression.fold<double>(
      0.0,
      (sum, item) => sum + (item['amount'] as num).toDouble(),
    );

    if (totalAmount <= 0) {
      return Container(
        height: 24,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 24,
        child: Row(
          children: progression.map((item) {
            final double amount = (item['amount'] as num).toDouble();
            final String status = item['status'] as String;
            final String feeName = item['feeName'] as String;
            final int flex = (amount / totalAmount * 1000).round().clamp(1, 1000);

            Color color;
            switch (status) {
              case 'Paid':
                color = Colors.green;
                break;
              case 'Partly Paid':
                color = Colors.orange;
                break;
              default:
                color = Colors.grey.shade300;
            }

            final tooltipText =
                '$feeName: ${widget.currencyFormat.format(amount)} - $status';

            return Expanded(
              flex: flex,
              child: Tooltip(
                message: tooltipText,
                child: Container(
                  height: 24,
                  decoration: BoxDecoration(
                    color: color,
                    border: Border(
                      right: BorderSide(color: Colors.white, width: 0.5),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: status == 'Partly Paid' && flex > 80
                      ? const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 2),
                            child: Text(
                              'Partly Paid',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildExpandedDetail(_StudentProgression student) {
    final progression = student.progression;
    final outstanding = student.billTotal - student.totalPaid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fee items table
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 16,
            headingRowHeight: 36,
            dataRowMinHeight: 36,
            dataRowMaxHeight: 44,
            columns: const [
              DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Fee Item', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Amount', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
              DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Covered', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            ],
            rows: List.generate(progression.length, (index) {
              final item = progression[index];
              final String status = item['status'] as String;
              final double amount = (item['amount'] as num).toDouble();
              final double covered = (item['covered'] as num).toDouble();
              final String feeName = item['feeName'] as String;

              Color chipColor;
              switch (status) {
                case 'Paid':
                  chipColor = Colors.green;
                  break;
                case 'Partly Paid':
                  chipColor = Colors.orange;
                  break;
                default:
                  chipColor = Colors.grey;
              }

              return DataRow(cells: [
                DataCell(Text('${index + 1}')),
                DataCell(Text(feeName)),
                DataCell(Text(widget.currencyFormat.format(amount))),
                DataCell(
                  Chip(
                    label: Text(
                      status,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                    backgroundColor: chipColor,
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                DataCell(Text(widget.currencyFormat.format(covered))),
              ]);
            }),
          ),
        ),
        const Divider(),
        // Summary row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            children: [
              _detailSummaryRow(
                  'Total Bill', widget.currencyFormat.format(student.billTotal)),
              _detailSummaryRow(
                  'Total Paid', widget.currencyFormat.format(student.totalPaid)),
              _detailSummaryRow(
                'Outstanding',
                widget.currencyFormat.format(outstanding.clamp(0, double.infinity)),
                valueColor: outstanding > 0 ? Colors.red : Colors.green,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailSummaryRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
