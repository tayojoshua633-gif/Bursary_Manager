// lib/screens/stock/purchase_history_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';

class PurchaseHistoryScreen extends StatefulWidget {
  const PurchaseHistoryScreen({super.key});

  @override
  State<PurchaseHistoryScreen> createState() => _PurchaseHistoryScreenState();
}

class _PurchaseHistoryScreenState extends State<PurchaseHistoryScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  List<Map<String, dynamic>> _allRestocks = [];
  List<Map<String, dynamic>> _filteredRestocks = [];
  bool _loading = true;

  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedFilter = 'all'; // all, thisMonth, lastMonth, custom

  @override
  void initState() {
    super.initState();
    _loadRestockHistory();
  }

  Future<void> _loadRestockHistory() async {
    setState(() => _loading = true);

    try {
      // Get all stock movements with type "Restock"
      final database = await _db.database;

      String query = '''
        SELECT
          sm.*,
          si.itemName,
          si.currentQuantity as currentStock
        FROM stock_movements sm
        INNER JOIN stock_items si ON sm.stockItemId = si.id
        WHERE sm.movementType = 'Restock'
      ''';

      // Add date filters if applicable
      if (_startDate != null || _endDate != null) {
        if (_startDate != null) {
          query += " AND sm.movementDate >= '${_startDate!.toIso8601String()}'";
        }
        if (_endDate != null) {
          query += " AND sm.movementDate <= '${_endDate!.toIso8601String()}'";
        }
      }

      query += ' ORDER BY sm.movementDate DESC';

      final restocks = await database.rawQuery(query);

      setState(() {
        _allRestocks = restocks;
        _filteredRestocks = restocks;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading restock history: $e')),
      );
    }
  }

  void _applyDateFilter(String filter) {
    setState(() {
      _selectedFilter = filter;
      final now = DateTime.now();

      switch (filter) {
        case 'thisMonth':
          _startDate = DateTime(now.year, now.month, 1);
          _endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
          break;
        case 'lastMonth':
          _startDate = DateTime(now.year, now.month - 1, 1);
          _endDate = DateTime(now.year, now.month, 0, 23, 59, 59);
          break;
        case 'all':
          _startDate = null;
          _endDate = null;
          break;
        default:
          break;
      }
    });

    _loadRestockHistory();
  }

  Future<void> _showCustomDatePicker() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        _selectedFilter = 'custom';
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadRestockHistory();
    }
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          FilterChip(
            label: const Text('All Time'),
            selected: _selectedFilter == 'all',
            onSelected: (_) => _applyDateFilter('all'),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('This Month'),
            selected: _selectedFilter == 'thisMonth',
            onSelected: (_) => _applyDateFilter('thisMonth'),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Last Month'),
            selected: _selectedFilter == 'lastMonth',
            onSelected: (_) => _applyDateFilter('lastMonth'),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: Text(_selectedFilter == 'custom'
                ? 'Custom: ${DateFormat('MMM d').format(_startDate!)} - ${DateFormat('MMM d').format(_endDate!)}'
                : 'Custom Range'),
            selected: _selectedFilter == 'custom',
            onSelected: (_) => _showCustomDatePicker(),
          ),
        ],
      ),
    );
  }

  double get _totalQuantityRestocked {
    return _filteredRestocks.fold(0, (sum, item) => sum + (item['quantity'] as int));
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase History'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRestockHistory,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          _buildFilterChips(),

          // Summary Card
          if (!_loading && _filteredRestocks.isNotEmpty)
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade100, Colors.green.shade50],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text(
                            '${_filteredRestocks.length}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade900,
                            ),
                          ),
                          Text(
                            'Restocks',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: Colors.green.shade300,
                      ),
                      Column(
                        children: [
                          Text(
                            formatter.format(_totalQuantityRestocked),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade900,
                            ),
                          ),
                          Text(
                            'Total Units',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // Restock List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredRestocks.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              'No restock history found',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _selectedFilter == 'all'
                                  ? 'Start restocking items to see history here'
                                  : 'No restocks in selected date range',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadRestockHistory,
                        child: ListView.builder(
                          itemCount: _filteredRestocks.length,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          itemBuilder: (context, index) {
                            final restock = _filteredRestocks[index];
                            final quantity = restock['quantity'] as int;
                            final balanceAfter = restock['balanceAfter'] as int;
                            final note = restock['note']?.toString() ?? '';
                            final date = DateTime.parse(restock['movementDate']);
                            final createdBy = restock['createdBy']?.toString() ?? 'Unknown';

                            // Parse note to extract supplier and invoice
                            String supplier = 'Unknown';
                            String? invoice;
                            String? costPrice;
                            String? additionalNotes;

                            final noteParts = note.split('|');
                            for (var part in noteParts) {
                              final trimmed = part.trim();
                              if (trimmed.startsWith('Restock from supplier:')) {
                                supplier = trimmed.replaceFirst('Restock from supplier:', '').trim();
                              } else if (trimmed.startsWith('Invoice:')) {
                                invoice = trimmed.replaceFirst('Invoice:', '').trim();
                              } else if (trimmed.startsWith('New cost price:')) {
                                costPrice = trimmed.replaceFirst('New cost price:', '').trim();
                              } else if (trimmed.startsWith('Notes:')) {
                                additionalNotes = trimmed.replaceFirst('Notes:', '').trim();
                              }
                            }

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              elevation: 2,
                              child: ExpansionTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.green.shade100,
                                  child: Icon(
                                    Icons.add_shopping_cart,
                                    color: Colors.green.shade700,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  restock['itemName'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: Colors.green.shade300),
                                          ),
                                          child: Text(
                                            '+$quantity units',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.green.shade900,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          DateFormat('MMM d, yyyy • h:mm a').format(date),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      border: Border(
                                        top: BorderSide(color: Colors.grey.shade200),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _detailRow(Icons.business, 'Supplier', supplier),
                                        if (invoice != null) ...[
                                          const SizedBox(height: 8),
                                          _detailRow(Icons.receipt_long, 'Invoice', invoice),
                                        ],
                                        const SizedBox(height: 8),
                                        _detailRow(Icons.inventory, 'Stock After Restock', '$balanceAfter units'),
                                        if (costPrice != null) ...[
                                          const SizedBox(height: 8),
                                          _detailRow(Icons.attach_money, 'Cost Price Updated', costPrice),
                                        ],
                                        const SizedBox(height: 8),
                                        _detailRow(Icons.person, 'Restocked By', createdBy),
                                        if (additionalNotes != null && additionalNotes.isNotEmpty) ...[
                                          const SizedBox(height: 12),
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade50,
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: Colors.blue.shade200),
                                            ),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Icon(Icons.notes, size: 16, color: Colors.blue.shade700),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    additionalNotes,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.blue.shade900,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade700,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
