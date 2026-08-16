import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/fee_priority_helper.dart';
import '../../utils/sibling_helper.dart';
import '../../widgets/sibling_mark.dart';

class TrackFeeItemScreen extends StatefulWidget {
  const TrackFeeItemScreen({super.key});

  @override
  State<TrackFeeItemScreen> createState() => _TrackFeeItemScreenState();
}

class _TrackFeeItemScreenState extends State<TrackFeeItemScreen>
    with SingleTickerProviderStateMixin {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final NumberFormat _currencyFormat =
      NumberFormat.currency(symbol: 'N', decimalDigits: 2);
  late final TabController _tabController;

  // Active term/session
  String _term = '';
  String _session = '';

  // Fee type toggle: 'regular' or 'special'
  String _feeType = 'regular';

  // Fee items lists
  List<Map<String, dynamic>> _regularFeeItems = [];
  List<Map<String, dynamic>> _specialFeeItems = [];
  int? _selectedFeeItemId;

  // Student filter: 'all', 'class', 'class_arm'
  String _studentFilter = 'all';
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _arms = [];
  int? _selectedClassId;
  int? _selectedArmId;

  // Results
  List<Map<String, dynamic>> _students = [];
  Map<int, String> _studentStatuses = {};
  Map<int, List<Map<String, dynamic>>> _studentProgressions = {};
  bool _loading = false;
  bool _initialising = true;
  bool _hasSearched = false;
  Set<String> _siblingPhones = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initialise();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _initialise() async {
    try {
      _term = await _db.getActiveTerm();
      final activeSession = await _db.getActiveSession();
      _session = activeSession?['sessionName'] ?? '';

      _regularFeeItems = await _db.getFeeItems(
        term: _term,
        session: _session,
      );
      _specialFeeItems = await _db.getSpecialFeeItems(
        term: _term,
        session: _session,
      );
      _classes = await _db.getClasses();
    } catch (e) {
      debugPrint('Error initialising TrackFeeItemScreen: $e');
    }

    if (mounted) {
      setState(() => _initialising = false);
    }
  }

  List<Map<String, dynamic>> get _activeFeeItems {
    if (_feeType == 'regular') {
      return _regularFeeItems
          .where((item) =>
              item['id'] != null &&
              item['name'] != null &&
              (item['name'] as String).isNotEmpty)
          .toList();
    } else {
      return _specialFeeItems
          .where((item) =>
              item['id'] != null &&
              item['name'] != null &&
              (item['name'] as String).isNotEmpty &&
              item['isCategory'] != 1)
          .toList();
    }
  }

  Future<void> _loadArms(int classId) async {
    final arms = await _db.getArmsByClass(classId);
    if (mounted) {
      setState(() {
        _arms = arms;
        _selectedArmId = null;
      });
    }
  }

  Future<void> _search() async {
    if (_selectedFeeItemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a fee item')),
      );
      return;
    }

    setState(() {
      _loading = true;
      _hasSearched = true;
    });

    try {
      final students = await _db.getStudentsWithFeeItem(
        feeItemId: _selectedFeeItemId!,
        term: _term,
        session: _session,
        classId: _studentFilter == 'class_arm' ? _selectedClassId : null,
        armId: _studentFilter == 'class_arm' ? _selectedArmId : null,
      );

      // Build fee name lookup from loaded fee items (regular + special)
      final Map<int, String> feeNameLookup = {};
      for (final item in _regularFeeItems) {
        final id = item['id'] as int?;
        final name = item['name']?.toString() ?? '';
        if (id != null && name.isNotEmpty) feeNameLookup[id] = name;
      }
      for (final item in _specialFeeItems) {
        final id = item['id'] as int?;
        final name = item['name']?.toString() ?? '';
        if (id != null && name.isNotEmpty) feeNameLookup[id] = name;
      }

      // Compute eligibility status for each student
      final Map<int, String> statuses = {};
      for (final student in students) {
        final studentId = student['studentId'] as int;
        final classId = student['classId'] as int;
        final armId = student['armId'] as int?;
        final billId = student['billId'] as int;
        final totalPaid = (student['totalPaid'] as num?)?.toDouble() ?? 0.0;
        // Fresh carry-over (same logic as Class Bills screen)
        final previousBalance = ((student['freshPreviousBalance'] as num?)?.toDouble() ?? 0.0).clamp(0.0, double.infinity);

        try {
          final priorities = await _db.getEffectiveFeePriorities(
            classId: classId,
            armId: armId,
            term: _term,
            session: _session,
          );

          final breakdown = await _db.getBillBreakdown(billId);

          // Also fetch fee names via JOIN for breakdown items not in lookup
          final db = await _db.database;
          final breakdownWithNames = await db.rawQuery('''
            SELECT
              sfb.feeItemId,
              sfb.amount,
              sfb.label,
              fi.name as feeItemName
            FROM student_fee_breakdown sfb
            LEFT JOIN fee_items fi ON sfb.feeItemId = fi.id
            WHERE sfb.billId = ?
            ORDER BY sfb.id ASC
          ''', [billId]);

          // Build a per-breakdown name map: feeItemId -> resolved name
          final Map<int, String> breakdownNames = {};
          for (final row in breakdownWithNames) {
            final feeItemId = row['feeItemId'] as int? ?? 0;
            final feeItemName = row['feeItemName']?.toString() ?? '';
            final label = row['label']?.toString() ?? '';
            // Priority: fee_items table name > label > lookup > 'Fee'
            final resolvedName = feeItemName.isNotEmpty
                ? feeItemName
                : label.isNotEmpty
                    ? label
                    : feeNameLookup[feeItemId] ?? 'Fee';
            breakdownNames[feeItemId] = resolvedName;
          }

          List<Map<String, dynamic>> prioritizedFees;

          if (priorities.isNotEmpty) {
            // Build prioritized list sorted by priority
            prioritizedFees = [];
            final sortedPriorities = List<Map<String, dynamic>>.from(priorities)
              ..sort((a, b) =>
                  (a['priority'] as int).compareTo(b['priority'] as int));

            // Collect all feeItemIds explicitly named in the priority list
            // (excluding the virtual -2 placeholder) to identify extras later.
            final namedPriorityIds = sortedPriorities
                .map((p) => p['feeItemId'] as int? ?? 0)
                .where((id) => id > 0)
                .toSet();

            final coveredFeeItemIds = <int>{};

            for (final p in sortedPriorities) {
              final pFeeItemId = p['feeItemId'] as int? ?? 0;

              if (pFeeItemId == -2) {
                // Virtual "Student-Specific Extras" slot:
                // sum all breakdown items not named in the priority list
                double extrasTotal = 0.0;
                for (final b in breakdown) {
                  final id = b['feeItemId'] as int? ?? 0;
                  if (!namedPriorityIds.contains(id) && id > 0 && !coveredFeeItemIds.contains(id)) {
                    extrasTotal += (b['amount'] as num?)?.toDouble() ?? 0.0;
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
                // Previous Balance slot — use fresh carry-over value
                if (previousBalance > 0) {
                  prioritizedFees.add({
                    'feeItemId': -1,
                    'feeName': 'Previous Balance',
                    'amount': previousBalance,
                  });
                  coveredFeeItemIds.add(-1);
                }
              } else {
                final matchingBreakdown = breakdown.firstWhere(
                  (b) => b['feeItemId'] == pFeeItemId,
                  orElse: () => <String, dynamic>{},
                );
                if (matchingBreakdown.isNotEmpty) {
                  prioritizedFees.add({
                    'feeItemId': pFeeItemId,
                    'feeName': breakdownNames[pFeeItemId] ?? feeNameLookup[pFeeItemId] ?? 'Fee',
                    'amount': (matchingBreakdown['amount'] as num?)?.toDouble() ?? 0.0,
                  });
                  coveredFeeItemIds.add(pFeeItemId);
                }
              }
            }

            // Fallback: any breakdown item still not covered
            for (final b in breakdown) {
              final feeItemId = b['feeItemId'] as int? ?? 0;
              if (!coveredFeeItemIds.contains(feeItemId) && feeItemId > 0) {
                prioritizedFees.add({
                  'feeItemId': feeItemId,
                  'feeName': breakdownNames[feeItemId] ?? feeNameLookup[feeItemId] ?? 'Fee',
                  'amount': (b['amount'] as num?)?.toDouble() ?? 0.0,
                });
              }
            }
            // Fallback: previous balance if not yet placed by the priority list
            if (previousBalance > 0 && !coveredFeeItemIds.contains(-1)) {
              prioritizedFees.add({
                'feeItemId': -1,
                'feeName': 'Previous Balance',
                'amount': previousBalance,
              });
            }
          } else {
            // No priorities defined — use breakdown order, then append previous balance
            prioritizedFees = breakdown.map((b) {
              final feeItemId = b['feeItemId'] as int? ?? 0;
              return <String, dynamic>{
                'feeItemId': feeItemId,
                'feeName': breakdownNames[feeItemId] ?? feeNameLookup[feeItemId] ?? 'Fee',
                'amount': (b['amount'] as num?)?.toDouble() ?? 0.0,
              };
            }).toList();
            if (previousBalance > 0) {
              prioritizedFees.add({
                'feeItemId': -1,
                'feeName': 'Previous Balance',
                'amount': previousBalance,
              });
            }
          }

          final progression = FeePriorityHelper.computeProgression(
            prioritizedFees: prioritizedFees,
            totalPaid: totalPaid,
          );

          statuses[studentId] = FeePriorityHelper.getItemStatus(
            progression,
            _selectedFeeItemId!,
          );
          _studentProgressions[studentId] = progression;
        } catch (e) {
          debugPrint('Error computing status for student $studentId: $e');
          statuses[studentId] = 'Not Paid';
        }
      }

      final siblingPhones = computeSiblingPhones(await _db.getActiveStudents());

      if (mounted) {
        setState(() {
          _students = students;
          _studentStatuses = statuses;
          _siblingPhones = siblingPhones;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error searching students: $e');
      if (mounted) {
        setState(() {
          _students = [];
          _studentStatuses = {};
          _studentProgressions = {};
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading students: $e')),
        );
      }
    }
  }

  int get _eligibleCount => _studentStatuses.values
      .where((s) => s == 'Paid')
      .length;

  int get _partlyPaidCount => _studentStatuses.values
      .where((s) => s == 'Partly Paid')
      .length;

  int get _notEligibleCount => _studentStatuses.values
      .where((s) => s == 'Not Paid')
      .length;

  List<Map<String, dynamic>> _studentsForStatus(String status) {
    return _students.where((student) {
      final studentId = student['studentId'] as int;
      return (_studentStatuses[studentId] ?? 'Not Paid') == status;
    }).toList();
  }

  Widget _buildStatusChip(String status) {
    Color color;
    IconData icon;
    String label;

    switch (status) {
      case 'Paid':
        color = Colors.green;
        icon = Icons.check_circle;
        label = 'Eligible';
        break;
      case 'Partly Paid':
        color = Colors.orange;
        icon = Icons.timelapse;
        label = 'Partly Paid';
        break;
      default:
        color = Colors.red;
        icon = Icons.cancel;
        label = 'Not Eligible';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressionBar(List<Map<String, dynamic>> progression, double totalPaid) {
    final double totalAmount = progression.fold<double>(
      0.0,
      (sum, item) => sum + (item['amount'] as num).toDouble(),
    );

    if (totalAmount <= 0) {
      return const SizedBox.shrink();
    }

    final double paymentFraction = (totalPaid / totalAmount).clamp(0.0, 1.0);

    return SizedBox(
      height: 52,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final barWidth = constraints.maxWidth;
          final paymentLineX = paymentFraction * barWidth;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Fee item segments bar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 44,
                  child: Row(
                    children: List.generate(progression.length, (i) {
                      final item = progression[i];
                      final double amount = (item['amount'] as num).toDouble();
                      final String status = item['status'] as String;
                      final int feeItemId = item['feeItemId'] as int;
                      final String feeName = item['feeName'] as String? ?? '';
                      final int flex =
                          (amount / totalAmount * 1000).round().clamp(1, 1000);
                      final bool isTracked = feeItemId == _selectedFeeItemId;

                      Color bgColor;
                      Color textColor;
                      switch (status) {
                        case 'Paid':
                          bgColor = isTracked ? Colors.green.shade700 : Colors.green.shade400;
                          textColor = Colors.white;
                          break;
                        case 'Partly Paid':
                          bgColor = isTracked ? Colors.orange.shade700 : Colors.orange.shade400;
                          textColor = Colors.white;
                          break;
                        default:
                          bgColor = isTracked ? Colors.blueGrey.shade300 : Colors.grey.shade200;
                          textColor = isTracked ? Colors.white : Colors.grey.shade700;
                      }

                      return Expanded(
                        flex: flex,
                        child: Tooltip(
                          message: '$feeName: ${_currencyFormat.format(amount)} – $status',
                          child: Container(
                            decoration: BoxDecoration(
                              color: bgColor,
                              border: isTracked
                                  ? Border.all(color: Colors.black54, width: 2)
                                  : i < progression.length - 1
                                      ? const Border(right: BorderSide(color: Colors.white, width: 1))
                                      : null,
                            ),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                feeName.length > 14
                                    ? '${feeName.substring(0, 12)}..'
                                    : feeName,
                                style: TextStyle(
                                  fontSize: isTracked ? 9 : 8,
                                  color: textColor,
                                  fontWeight: isTracked ? FontWeight.bold : FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),

              // Payment line marker (vertical line showing where payment reached)
              if (paymentFraction > 0 && paymentFraction < 1)
                Positioned(
                  left: paymentLineX - 1.5,
                  top: -4,
                  bottom: 0,
                  child: Column(
                    children: [
                      // Triangle pointer
                      CustomPaint(
                        size: const Size(10, 6),
                        painter: _TrianglePainter(),
                      ),
                      // Vertical line
                      Expanded(
                        child: Container(
                          width: 3,
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.8),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryBadge(IconData icon, Color color, String count, String label) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 2),
        Text(
          count,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Fee Item'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: _initialising
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    // Before search or when loading, show controls + centered message
    if (_loading) {
      return Column(
        children: [
          _buildControls(),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    if (!_hasSearched) {
      return Column(
        children: [
          _buildControls(),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'Select a fee item and press Search',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
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
          _buildControls(),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No students found',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // When results exist, show a fixed header (controls + summary + legend)
    // above a pinned TabBar, with each tab scrolling its own filtered list.
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          SliverToBoxAdapter(child: _buildControls()),

          // Summary card
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(
                        '${_students.length} Students Found',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _summaryBadge(Icons.check_circle, Colors.green, '$_eligibleCount', 'Eligible'),
                          _summaryBadge(Icons.timelapse, Colors.orange, '$_partlyPaidCount', 'Partly Paid'),
                          _summaryBadge(Icons.cancel, Colors.red, '$_notEligibleCount', 'Not Eligible'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Legend row
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _legendDot(Colors.green.shade400, 'Eligible'),
                  const SizedBox(width: 12),
                  _legendDot(Colors.orange.shade400, 'Partly Paid'),
                  const SizedBox(width: 12),
                  _legendDot(Colors.grey.shade300, 'Not Eligible'),
                  const SizedBox(width: 12),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade300,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: Colors.black54, width: 1.5),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('Tracked Item', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                  const SizedBox(width: 12),
                  Container(width: 10, height: 3, color: Colors.black87),
                  const SizedBox(width: 4),
                  Text('Payment Line', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                ],
              ),
            ),
          ),

          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              TabBar(
                controller: _tabController,
                labelColor: Colors.orange.shade800,
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: Colors.orange,
                tabs: [
                  Tab(text: 'Eligible ($_eligibleCount)'),
                  Tab(text: 'Partly Paid ($_partlyPaidCount)'),
                  Tab(text: 'Not Eligible ($_notEligibleCount)'),
                ],
              ),
            ),
          ),
        ];
      },
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStudentList(_studentsForStatus('Paid')),
          _buildStudentList(_studentsForStatus('Partly Paid')),
          _buildStudentList(_studentsForStatus('Not Paid')),
        ],
      ),
    );
  }

  Widget _buildStudentList(List<Map<String, dynamic>> students) {
    if (students.isEmpty) {
      return Center(
        child: Text(
          'No students in this category',
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: students.length,
      itemBuilder: (context, index) => _buildStudentCard(students[index]),
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> student) {
    final studentId = student['studentId'] as int;
    final surname = student['surname'] ?? '';
    final firstName = student['firstName'] ?? '';
    final parentPhone = student['parentPhone'] as String?;
    final admissionNo = student['admissionNo'] ?? '';
    final className = student['className'] ?? '';
    final armName = student['armName'];
    final feeAmount = (student['feeAmount'] as num?)?.toDouble() ?? 0.0;
    final totalPaid = (student['totalPaid'] as num?)?.toDouble() ?? 0.0;
    final status = _studentStatuses[studentId] ?? 'Not Paid';
    final progression = _studentProgressions[studentId] ?? [];

    final trackedItem = progression.firstWhere(
      (item) => item['feeItemId'] == _selectedFeeItemId,
      orElse: () => <String, dynamic>{},
    );
    final itemAmount = (trackedItem['amount'] as num?)?.toDouble() ?? feeAmount;
    final itemCovered = (trackedItem['covered'] as num?)?.toDouble() ?? 0.0;
    final itemBalance = (itemAmount - itemCovered).clamp(0.0, double.infinity);

    Color coveredColor;
    switch (status) {
      case 'Paid':
        coveredColor = Colors.green.shade700;
        break;
      case 'Partly Paid':
        coveredColor = Colors.orange.shade700;
        break;
      default:
        coveredColor = Colors.grey.shade600;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '$surname, $firstName',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SiblingMark(show: isSiblingPhone(parentPhone, _siblingPhones)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Adm: $admissionNo | '
                          '$className${armName != null ? ' - $armName' : ''}',
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Fee Item Amount: ${_currencyFormat.format(itemAmount)}',
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Covered: ${_currencyFormat.format(itemCovered)}'
                          '${itemBalance > 0 ? ' (Balance: ${_currencyFormat.format(itemBalance)})' : ''}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: coveredColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusChip(status),
                ],
              ),
              if (progression.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildProgressionBar(progression, totalPaid),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Fee type toggle
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'regular',
                label: Text('Regular Fees'),
              ),
              ButtonSegment(
                value: 'special',
                label: Text('New Intake Fees'),
              ),
            ],
            selected: {_feeType},
            onSelectionChanged: (selected) {
              setState(() {
                _feeType = selected.first;
                _selectedFeeItemId = null;
              });
            },
          ),
          const SizedBox(height: 12),

          // Fee item dropdown
          DropdownButtonFormField<int>(
            initialValue: _selectedFeeItemId,
            decoration: const InputDecoration(
              labelText: 'Fee Item',
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            isExpanded: true,
            items: _activeFeeItems.map((item) {
              return DropdownMenuItem<int>(
                value: item['id'] as int,
                child: Text(item['name'] as String),
              );
            }).toList(),
            onChanged: (value) {
              setState(() => _selectedFeeItemId = value);
            },
            hint: const Text('Select a fee item'),
          ),
          const SizedBox(height: 12),

          // Student filter toggle
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'all',
                label: Text('All Students'),
              ),
              ButtonSegment(
                value: 'class_arm',
                label: Text('By Class'),
              ),
            ],
            selected: {_studentFilter},
            onSelectionChanged: (selected) {
              setState(() {
                _studentFilter = selected.first;
                if (_studentFilter == 'all') {
                  _selectedClassId = null;
                  _selectedArmId = null;
                  _arms = [];
                }
              });
            },
          ),
          const SizedBox(height: 12),

          // Class dropdown (when filter is class_arm)
          if (_studentFilter == 'class_arm')
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<int>(
                initialValue: _selectedClassId,
                decoration: const InputDecoration(
                  labelText: 'Class *',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
                isExpanded: true,
                items: _classes.map((cls) {
                  return DropdownMenuItem<int>(
                    value: cls['id'] as int,
                    child: Text(cls['name'] as String),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedClassId = value;
                    _selectedArmId = null;
                    _arms = [];
                  });
                  if (value != null) {
                    _loadArms(value);
                  }
                },
                hint: const Text('Select a class'),
              ),
            ),

          // Arm dropdown (when filter is class_arm and arms loaded)
          if (_studentFilter == 'class_arm' && _arms.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<int>(
                initialValue: _selectedArmId,
                decoration: const InputDecoration(
                  labelText: 'Arm (optional)',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
                isExpanded: true,
                items: _arms.map((arm) {
                  return DropdownMenuItem<int>(
                    value: arm['id'] as int,
                    child: Text(arm['name'] as String),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedArmId = value);
                },
                hint: const Text('Select an arm'),
              ),
            ),

          // Search button
          ElevatedButton(
            onPressed: _loading ? null : _search,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }
}

/// Pins the status TabBar to the top of the NestedScrollView header.
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) {
    return oldDelegate.tabBar != tabBar;
  }
}

/// Triangle pointer for the payment line marker
class _TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
