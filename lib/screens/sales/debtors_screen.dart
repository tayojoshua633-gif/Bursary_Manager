// lib/screens/sales/debtors_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';
import '../../navigation/sidebar_scaffold.dart';
import 'sale_record_screen.dart';

class DebtorsScreen extends StatefulWidget {
  final Map<String, dynamic>? currentUser;

  const DebtorsScreen({super.key, this.currentUser});

  @override
  State<DebtorsScreen> createState() => _DebtorsScreenState();
}

class _DebtorsScreenState extends State<DebtorsScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _allDebtors = [];
  List<Map<String, dynamic>> _filteredDebtors = [];
  bool _loading = true;
  double _totalOutstanding = 0.0;

  @override
  void initState() {
    super.initState();
    _loadDebtors();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDebtors() async {
    setState(() => _loading = true);

    try {
      // Get debtors from the dedicated sales_debtors table
      final debtors = await _db.getSalesDebtors();

      // For each debtor, get their individual sales for the detail view
      final List<Map<String, dynamic>> debtorsList = [];
      double totalOutstanding = 0.0;

      for (final debtor in debtors) {
        final buyerName = debtor['buyerName'] as String;
        final buyerType = debtor['buyerType'] as String;
        final term = debtor['term'] as String?;
        final session = debtor['session'] as String?;

        // Get individual sales for this debtor
        // Only show ORIGINAL sales (quantity > 0), not payment receipts (quantity = 0)
        final sales = await _db.getAllSales();
        final debtorSales = sales.where((sale) {
          final matchesBuyer = sale['buyerName'] == buyerName && sale['buyerType'] == buyerType;
          final matchesTerm = term == null || sale['term'] == term;
          final matchesSession = session == null || sale['session'] == session;
          final hasOutstanding = ((sale['outstandingBalance'] as num?)?.toDouble() ?? 0.0) > 0;
          final isOriginalSale = (sale['quantity'] as int) > 0; // Exclude payment receipts
          return matchesBuyer && matchesTerm && matchesSession && hasOutstanding && isOriginalSale;
        }).toList();

        // Add debtor with their sales
        debtorsList.add({
          'buyerName': buyerName,
          'buyerType': buyerType,
          'studentId': debtor['studentId'],
          'totalAmount': (debtor['totalAmount'] as num).toDouble(),
          'amountPaid': (debtor['amountPaid'] as num).toDouble(),
          'outstandingBalance': (debtor['outstandingBalance'] as num).toDouble(),
          'sales': debtorSales,
        });

        totalOutstanding += (debtor['outstandingBalance'] as num).toDouble();
      }

      setState(() {
        _allDebtors = debtorsList;
        _filteredDebtors = debtorsList;
        _totalOutstanding = totalOutstanding;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading debtors: $e')),
      );
    }
  }

  void _applyFilters() {
    final keyword = _searchCtrl.text.trim().toLowerCase();

    setState(() {
      if (keyword.isEmpty) {
        _filteredDebtors = _allDebtors;
      } else {
        _filteredDebtors = _allDebtors.where((debtor) {
          final buyerName = (debtor['buyerName'] ?? '').toString().toLowerCase();
          final buyerType = (debtor['buyerType'] ?? '').toString().toLowerCase();
          return buyerName.contains(keyword) || buyerType.contains(keyword);
        }).toList();
      }
    });
  }

  void _navigateToPayDebt(Map<String, dynamic> debtor) async {
    final sales = debtor['sales'] as List<Map<String, dynamic>>;

    // Prepare buyer info
    final buyerInfo = {
      'buyerType': debtor['buyerType'],
      'buyerName': debtor['buyerName'],
      'studentId': debtor['studentId'],
      'existingOutstanding': debtor['outstandingBalance'],
      'isPayingDebt': true, // Flag to indicate this is a debt payment
    };

    // Get the CURRENT total outstanding from sales_debtors table
    final currentTotalOutstanding = (debtor['outstandingBalance'] as num).toDouble();

    // Calculate total original amount from all sales
    double totalOriginalAmount = 0.0;
    for (final sale in sales) {
      totalOriginalAmount += (sale['totalAmount'] as num).toDouble();
    }

    // Prepare initial cart items from unpaid sales
    // Use CURRENT outstanding from sales_debtors, distributed proportionally
    final List<Map<String, dynamic>> initialCartItems = [];

    for (final sale in sales) {
      final saleTotal = (sale['totalAmount'] as num).toDouble();

      // Calculate this item's proportion of the current outstanding
      final proportion = totalOriginalAmount > 0 ? saleTotal / totalOriginalAmount : 0.0;
      final currentItemOutstanding = currentTotalOutstanding * proportion;

      if (currentItemOutstanding > 0) {
        final isCustomItem = sale['isCustomItem'] == 1 || sale['stockItemId'] == 0;
        initialCartItems.add({
          'saleId': sale['id'],
          'stockItemId': sale['stockItemId'],
          'itemName': sale['itemName'],
          'quantity': sale['quantity'],
          'unitPrice': (sale['unitPrice'] as num).toDouble(),
          'totalAmount': saleTotal,
          'amountPaid': saleTotal - currentItemOutstanding, // Calculated from current outstanding
          'outstandingBalance': currentItemOutstanding, // Use CURRENT outstanding, not old value
          'isCustomItem': isCustomItem,
        });
      }
    }

    if (initialCartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No outstanding items to pay for'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Navigate to sale record screen with pre-loaded cart
    final screenSize = MediaQuery.of(context).size;
    final showSidebar = screenSize.shortestSide >= 700 && widget.currentUser != null;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => showSidebar
            ? SidebarScaffold(
                currentUser: widget.currentUser!,
                currentPageId: 'stock_sales/record_sale',
                child: SaleRecordScreen(
                  buyerInfo: buyerInfo,
                  initialCartItems: initialCartItems,
                ),
              )
            : SaleRecordScreen(
                buyerInfo: buyerInfo,
                initialCartItems: initialCartItems,
              ),
      ),
    );

    // Reload debtors after returning
    _loadDebtors();
  }

  void _showDebtorDetails(Map<String, dynamic> debtor) {
    final formatter = NumberFormat('#,##0.00');
    final sales = debtor['sales'] as List<Map<String, dynamic>>;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.red.shade100,
              child: Icon(
                debtor['buyerType'] == 'Student' ? Icons.school : Icons.person,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    debtor['buyerName'],
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    debtor['buyerType'],
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  children: [
                    _buildSummaryRow('Total Amount:', '₦${formatter.format(debtor['totalAmount'])}'),
                    const Divider(height: 12),
                    _buildSummaryRow('Amount Paid:', '₦${formatter.format(debtor['amountPaid'])}'),
                    const Divider(height: 12),
                    _buildSummaryRow(
                      'Outstanding:',
                      '₦${formatter.format(debtor['outstandingBalance'])}',
                      isHighlight: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Items Purchased:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              // Items list
              ...sales.map((sale) {
                final saleDate = DateTime.parse(sale['saleDate']);
                final isCustomItem = sale['isCustomItem'] == 1 || sale['stockItemId'] == 0;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      backgroundColor: isCustomItem ? Colors.purple.shade100 : Colors.orange.shade100,
                      radius: 16,
                      child: Icon(
                        isCustomItem ? Icons.edit_note : Icons.shopping_bag,
                        size: 16,
                        color: isCustomItem ? Colors.purple.shade700 : Colors.orange.shade700,
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            sale['itemName'],
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isCustomItem ? Colors.purple.shade800 : null,
                            ),
                          ),
                        ),
                        if (isCustomItem)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Custom',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.purple.shade900,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Qty: ${sale['quantity']} × ₦${formatter.format(sale['unitPrice'])} = ₦${formatter.format(sale['totalAmount'])}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        Text(
                          'Date: ${DateFormat('MMM d, yyyy').format(saleDate)}',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          sale['paymentStatus'],
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: sale['paymentStatus'] == 'Credit'
                                ? Colors.red
                                : Colors.orange,
                          ),
                        ),
                        Text(
                          '₦${formatter.format(sale['outstandingBalance'])}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              _navigateToPayDebt(debtor);
            },
            icon: const Icon(Icons.payment, size: 20),
            label: const Text('Pay Debt'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isHighlight ? 14 : 12,
            fontWeight: FontWeight.bold,
            color: isHighlight ? Colors.red.shade900 : Colors.black87,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debtors'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDebtors,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Total Outstanding Summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.red.shade50, Colors.orange.shade50],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border(
                bottom: BorderSide(color: Colors.red.shade200),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.red.shade700, size: 24),
                    const SizedBox(width: 8),
                    const Text(
                      'Total Outstanding:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  '₦${formatter.format(_totalOutstanding)}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade900,
                  ),
                ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                labelText: 'Search debtors',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _applyFilters();
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.red.shade50,
              ),
              onChanged: (_) => _applyFilters(),
            ),
          ),

          // Debtors count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  '${_filteredDebtors.length} debtor(s)',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Debtors list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredDebtors.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 64, color: Colors.green.shade400),
                            const SizedBox(height: 16),
                            Text(
                              _searchCtrl.text.isEmpty
                                  ? 'No debtors found!\nAll payments are up to date.'
                                  : 'No debtors found',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadDebtors,
                        child: ListView.builder(
                          itemCount: _filteredDebtors.length,
                          itemBuilder: (context, index) {
                            final debtor = _filteredDebtors[index];
                            final sales = debtor['sales'] as List;

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.red.shade100,
                                  child: Icon(
                                    debtor['buyerType'] == 'Student'
                                        ? Icons.school
                                        : Icons.person,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        debtor['buyerName'],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        debtor['buyerType'],
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.red.shade900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      '${sales.length} item(s) | Paid: ₦${formatter.format(debtor['amountPaid'])}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Icon(Icons.warning_amber,
                                            size: 14, color: Colors.red.shade700),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Balance: ₦${formatter.format(debtor['outstandingBalance'])}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                isThreeLine: true,
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _showDebtorDetails(debtor),
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
}
