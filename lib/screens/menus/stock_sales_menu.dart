// lib/screens/menus/stock_sales_menu.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/display_settings_helper.dart';
import '../../utils/permission_helper.dart';
import '../../navigation/sidebar_scaffold.dart';
import '../../data/database_helper_wrapper.dart';
import '../stock/stock_item_list_screen.dart';
import '../stock/supplier_list_screen.dart';
import '../stock/purchase_history_screen.dart';
import '../sales/buyer_selection_screen.dart';
import '../sales/debtors_screen.dart';
import '../reports/sales_report_screen.dart';
import '../reports/stock_record_report_screen.dart';

class StockSalesMenu extends StatefulWidget {
  final Map<String, dynamic> currentUser;

  const StockSalesMenu({super.key, required this.currentUser});

  @override
  State<StockSalesMenu> createState() => _StockSalesMenuState();
}

class _StockSalesMenuState extends State<StockSalesMenu> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  double _totalCostValue = 0;
  double _totalSellingValue = 0;
  double _stockSalesAmount = 0;
  double _stockProfit = 0;
  double _customSalesAmount = 0;
  double _customProfit = 0;
  double _totalDebts = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    setState(() => _loading = true);

    try {
      final items = await _db.getStockItems();

      // Calculate total cost and selling value of all stock
      double totalCost = 0;
      double totalSelling = 0;

      for (final item in items) {
        final qty = (item['currentQuantity'] as int);
        final costPrice = (item['costPrice'] as num).toDouble();
        final sellingPrice = (item['sellingPrice'] as num).toDouble();

        totalCost += qty * costPrice;
        totalSelling += qty * sellingPrice;
      }

      // Get all sales data to calculate total sales amount and profit
      // Note: Only count ORIGINAL sales (quantity > 0), not payment receipts (quantity = 0)
      final allSales = await _db.getAllSales();
      double stockSales = 0;
      double stockProfit = 0;
      double customSales = 0;
      double customProfit = 0;

      for (final sale in allSales) {
        final qty = (sale['quantity'] as int);

        // Skip payment receipts (quantity = 0)
        if (qty == 0) continue;

        final totalAmount = (sale['totalAmount'] as num).toDouble();
        final unitPrice = (sale['unitPrice'] as num).toDouble();
        final stockItemId = (sale['stockItemId'] as int?) ?? 0;

        // Check if this is a custom item (stockItemId = 0 or isCustomItem = 1)
        final isCustomItem = sale['isCustomItem'] == 1 || stockItemId == 0;

        if (isCustomItem) {
          // Custom items have no cost price - profit is full selling price
          customSales += totalAmount;
          customProfit += unitPrice * qty;
        } else {
          // Get cost price from stock item for regular items
          final stockItem = items.firstWhere(
            (item) => item['id'] == stockItemId,
            orElse: () => {'costPrice': 0},
          );
          final costPrice = (stockItem['costPrice'] as num?)?.toDouble() ?? 0;

          stockSales += totalAmount;
          stockProfit += (unitPrice - costPrice) * qty;
        }
      }

      // Get CURRENT total debts from sales_debtors table (not from individual sales)
      final debtors = await _db.getSalesDebtors();
      double totalDebts = 0;
      for (final debtor in debtors) {
        totalDebts += (debtor['outstandingBalance'] as num).toDouble();
      }

      setState(() {
        _totalCostValue = totalCost;
        _totalSellingValue = totalSelling;
        _stockSalesAmount = stockSales;
        _stockProfit = stockProfit;
        _customSalesAmount = customSales;
        _customProfit = customProfit;
        _totalDebts = totalDebts;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Widget _buildSummaryCard(String title, double amount, IconData icon, MaterialColor color) {
    final formatter = NumberFormat('#,##0.00');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color.shade700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '₦${formatter.format(amount)}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color.shade900,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock & Sales Management'),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStatistics,
            tooltip: 'Refresh Statistics',
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Summary Statistics
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.brown.shade50, Colors.orange.shade50],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border(
                bottom: BorderSide(color: Colors.brown.shade200),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.analytics_outlined, color: Colors.brown.shade700, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Stock & Sales Summary',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.brown.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  )
                else ...[
                  // Stock inventory row
                  Row(
                    children: [
                      Expanded(
                        child: _buildSummaryCard(
                          'Stock Cost',
                          _totalCostValue,
                          Icons.shopping_cart_outlined,
                          Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildSummaryCard(
                          'Stock Value',
                          _totalSellingValue,
                          Icons.sell_outlined,
                          Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Stock item sales
                  Row(
                    children: [
                      Expanded(
                        child: _buildSummaryCard(
                          'Stock Sales',
                          _stockSalesAmount,
                          Icons.attach_money,
                          Colors.green,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildSummaryCard(
                          'Stock Profit',
                          _stockProfit,
                          Icons.trending_up,
                          Colors.purple,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Custom item sales
                  Row(
                    children: [
                      Expanded(
                        child: _buildSummaryCard(
                          'Custom Sales',
                          _customSalesAmount,
                          Icons.edit_note,
                          Colors.deepOrange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildSummaryCard(
                          'Custom Profit',
                          _customProfit,
                          Icons.trending_up,
                          Colors.teal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Grand total row
                  Row(
                    children: [
                      Expanded(
                        child: _buildSummaryCard(
                          'Grand Total Sales',
                          _stockSalesAmount + _customSalesAmount,
                          Icons.summarize,
                          Colors.brown,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildSummaryCard(
                          'Grand Total Profit',
                          _stockProfit + _customProfit,
                          Icons.account_balance,
                          Colors.indigo,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Debts row
                  Row(
                    children: [
                      Expanded(
                        child: _buildSummaryCard(
                          'Total Debts',
                          _totalDebts,
                          Icons.warning_amber,
                          Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Menu Grid
          GridView.extent(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              maxCrossAxisExtent: context.gridMaxExtent,
              padding: EdgeInsets.all(ds.cardPadding),
              crossAxisSpacing: ds.cardPadding,
              mainAxisSpacing: ds.cardPadding,
              childAspectRatio: context.gridChildAspectRatio,
              children: [
          _permissionMenuCard(
            context,
            module: 'stock_manage',
            title: 'Stock Items',
            subtitle: 'Manage inventory',
            icon: Icons.inventory_outlined,
            color: Colors.brown,
            page: const StockItemListScreen(),
            pageId: 'stock_sales/stock_items',
          ),
          _permissionMenuCard(
            context,
            module: 'sales_record',
            title: 'Record Sale',
            subtitle: 'Sell stock items',
            icon: Icons.point_of_sale_outlined,
            color: Colors.teal,
            page: const BuyerSelectionScreen(),
            pageId: 'stock_sales/record_sale',
          ),
          _permissionMenuCard(
            context,
            module: 'stock_manage',
            title: 'Suppliers',
            subtitle: 'Manage supplier contacts',
            icon: Icons.business_outlined,
            color: Colors.indigo,
            page: const SupplierListScreen(),
            pageId: 'stock_sales/suppliers',
          ),
          _permissionMenuCard(
            context,
            module: 'stock_manage',
            title: 'Purchase History',
            subtitle: 'View restock records',
            icon: Icons.history_outlined,
            color: Colors.green,
            page: const PurchaseHistoryScreen(),
            pageId: 'stock_sales/purchase_history',
          ),
          _permissionMenuCard(
            context,
            module: 'sales_report',
            title: 'Sales Report',
            subtitle: 'Daily sales summary',
            icon: Icons.analytics_outlined,
            color: Colors.deepOrange,
            page: const SalesReportScreen(),
            pageId: 'stock_sales/sales_report',
          ),
          _permissionMenuCard(
            context,
            module: 'sales_report',
            title: 'Stock Record Report',
            subtitle: 'Stock movement details',
            icon: Icons.assessment_outlined,
            color: Colors.deepPurple,
            page: const StockRecordReportScreen(),
            pageId: 'stock_sales/stock_report',
          ),
          _permissionMenuCard(
            context,
            module: 'sales_report',
            title: 'Debtors',
            subtitle: 'Track outstanding balances',
            icon: Icons.account_balance_wallet_outlined,
            color: Colors.red,
            page: DebtorsScreen(currentUser: widget.currentUser),
            pageId: 'stock_sales/debtors',
          ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _menuCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Widget page,
    String? pageId,
  }) {
    final ds = DisplaySettingsProvider.of(context);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final screenSize = MediaQuery.of(context).size;
          final showSidebar = screenSize.shortestSide >= 700;
          // Navigate to child screen
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => showSidebar
                  ? SidebarScaffold(
                      currentUser: widget.currentUser,
                      currentPageId: pageId,
                      child: page,
                    )
                  : page,
            ),
          );
          // Auto-refresh statistics when returning from child screen
          _loadStatistics();
        },
        child: Container(
          padding: EdgeInsets.all(ds.cardPadding),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.1),
                color.withValues(alpha: 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(ds.cardPadding),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: ds.iconSize * 1.6,
                  color: color,
                ),
              ),
              SizedBox(height: ds.cardPadding * 0.75),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: ds.titleFontSize * 0.85,
                ),
              ),
              SizedBox(height: ds.cardPadding * 0.25),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: ds.subtitleFontSize,
                  color: Colors.grey[600],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _permissionMenuCard(
    BuildContext context, {
    required String module,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Widget page,
    String? pageId,
  }) {
    return FutureBuilder<bool>(
      future: PermissionHelper.hasPermission(widget.currentUser, module),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    'Error loading $title',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.data != true) {
          return const SizedBox.shrink();
        }

        return _menuCard(
          context,
          title: title,
          subtitle: subtitle,
          icon: icon,
          color: color,
          page: page,
          pageId: pageId,
        );
      },
    );
  }
}
