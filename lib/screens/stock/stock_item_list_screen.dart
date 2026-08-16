// lib/screens/stock/stock_item_list_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database_helper_wrapper.dart';
import '../../navigation/sidebar_scaffold.dart';
import '../../utils/permission_helper.dart';
import 'stock_item_form_screen.dart';
import 'stock_adjustment_screen.dart';
import 'restock_screen.dart';

class StockItemListScreen extends StatefulWidget {
  const StockItemListScreen({super.key});

  @override
  State<StockItemListScreen> createState() => _StockItemListScreenState();
}

class _StockItemListScreenState extends State<StockItemListScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _allItems = [];
  List<Map<String, dynamic>> _filteredItems = [];
  bool _loading = true;
  Map<String, dynamic>? _currentUser;
  bool _canManageStock = false;
  int? _selectedParentFilter;
  List<Map<String, dynamic>> _parentItems = [];
  final Set<int> _expandedParents = {}; // Track which parent cards are expanded

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadParentItems();
    _loadItems();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userType = prefs.getString('userType') ?? 'bursar';
    final userId = prefs.getInt('userId') ?? 0;
    final username = prefs.getString('username') ?? 'User';

    final user = {
      'id': userId,
      'userType': userType,
      'username': username,
    };

    final canManage = await PermissionHelper.hasPermission(user, 'stock_manage');

    setState(() {
      _currentUser = user;
      _canManageStock = canManage;
    });
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);

    try {
      final items = await _db.getStockItems();

      setState(() {
        _allItems = items;
        _loading = false;
      });

      // Apply filters to exclude child items from top-level display
      _applyFilters();
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading stock items: $e')),
      );
    }
  }

  Future<void> _loadParentItems() async {
    try {
      final parents = await _db.getParentItems();
      setState(() => _parentItems = parents);
    } catch (e) {
      print('Error loading parents: $e');
    }
  }

  void _applyFilters() {
    final keyword = _searchCtrl.text.trim().toLowerCase();

    setState(() {
      List<Map<String, dynamic>> filtered = _allItems;

      // Apply keyword search first
      if (keyword.isNotEmpty) {
        filtered = filtered.where((item) {
          final itemName = (item['itemName'] ?? '').toString().toLowerCase();
          final supplier = (item['supplierName'] ?? '').toString().toLowerCase();
          return itemName.contains(keyword) || supplier.contains(keyword);
        }).toList();
      }

      // IMPORTANT: Always exclude children from top-level list
      // Children are ONLY shown inside their parent cards via _buildParentCard
      if (_selectedParentFilter == null) {
        // Show all parent items and ungrouped items (NEVER show children at top level)
        filtered = filtered.where((item) {
          final isParent = (item['isParent'] ?? 0) == 1;
          final hasNoParent = item['parentItemId'] == null;
          // Item must be either a parent OR have no parent (ungrouped)
          // This excludes all children items from the top-level list
          return isParent || hasNoParent;
        }).toList();
      } else if (_selectedParentFilter == 0) {
        // Ungrouped only (no parent and not a parent itself)
        filtered = filtered.where((item) {
          return item['parentItemId'] == null && (item['isParent'] ?? 0) != 1;
        }).toList();
      } else {
        // Specific parent filter: show ONLY the parent item itself
        // Its children will be shown inside the parent card when expanded
        filtered = filtered.where((item) {
          return item['id'] == _selectedParentFilter;
        }).toList();
      }

      _filteredItems = filtered;
    });
  }

  List<Map<String, dynamic>> _getChildrenOf(int parentId) {
    return _allItems.where((item) => item['parentItemId'] == parentId).toList();
  }

  Future<void> _navigateToForm([Map<String, dynamic>? item]) async {
    // Check if we should show sidebar
    final screenSize = MediaQuery.of(context).size;
    final showSidebar = screenSize.shortestSide >= 700;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => showSidebar && _currentUser != null
            ? SidebarScaffold(
                currentUser: _currentUser!,
                currentPageId: 'stock_sales/stock_items',
                child: StockItemFormScreen(item: item),
              )
            : StockItemFormScreen(item: item),
      ),
    );

    if (result == true) {
      _loadItems();
    }
  }

  Future<void> _navigateToAdjustment(Map<String, dynamic> item) async {
    // Check if we should show sidebar
    final screenSize = MediaQuery.of(context).size;
    final showSidebar = screenSize.shortestSide >= 700;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => showSidebar && _currentUser != null
            ? SidebarScaffold(
                currentUser: _currentUser!,
                currentPageId: 'stock_sales/stock_items',
                child: StockAdjustmentScreen(
                  stockItemId: item['id'],
                  itemName: item['itemName'],
                  currentQuantity: item['currentQuantity'],
                ),
              )
            : StockAdjustmentScreen(
                stockItemId: item['id'],
                itemName: item['itemName'],
                currentQuantity: item['currentQuantity'],
              ),
      ),
    );

    if (result == true) {
      _loadItems();
    }
  }

  Future<void> _navigateToRestock(Map<String, dynamic> item) async {
    // Check if we should show sidebar
    final screenSize = MediaQuery.of(context).size;
    final showSidebar = screenSize.shortestSide >= 700;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => showSidebar && _currentUser != null
            ? SidebarScaffold(
                currentUser: _currentUser!,
                currentPageId: 'stock_sales/stock_items',
                child: RestockScreen(
                  stockItemId: item['id'],
                  itemName: item['itemName'],
                  currentQuantity: item['currentQuantity'],
                  currentCostPrice: (item['costPrice'] as num).toDouble(),
                  currentSupplier: item['supplierName'],
                ),
              )
            : RestockScreen(
                stockItemId: item['id'],
                itemName: item['itemName'],
                currentQuantity: item['currentQuantity'],
                currentCostPrice: (item['costPrice'] as num).toDouble(),
                currentSupplier: item['supplierName'],
              ),
      ),
    );

    if (result == true) {
      _loadItems();
    }
  }

  Future<void> _deleteStockItem(Map<String, dynamic> item) async {
    final itemName = item['itemName'];
    final currentQty = item['currentQuantity'] as int;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Stock Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to delete this stock item?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    itemName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Supplier: ${item['supplierName']}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Current Quantity: $currentQty',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Note: This action cannot be undone. If this item has been used in any sales, deletion will be prevented.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.red,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await _db.deleteStockItem(item['id']);

      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stock item deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );

      _loadItems(); // Reload the list
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Widget _buildLowStockBadge(Map<String, dynamic> item) {
    final currentQty = item['currentQuantity'] as int;
    final reorderLevel = item['reorderLevel'] as int;

    if (currentQty <= reorderLevel) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning, size: 14, color: Colors.red.shade900),
            const SizedBox(width: 4),
            Text(
              'Low Stock',
              style: TextStyle(
                fontSize: 11,
                color: Colors.red.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildParentCard(Map<String, dynamic> parentItem, NumberFormat formatter) {
    final parentId = parentItem['id'] as int;
    final children = _getChildrenOf(parentId);
    final isExpanded = _expandedParents.contains(parentId);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      child: Column(
        children: [
          // Parent header
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.amber.shade100,
              child: Icon(Icons.folder, color: Colors.amber.shade700),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    parentItem['itemName'],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                if (children.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${children.length} ${children.length == 1 ? "item" : "items"}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Text(
              'Category/Parent Item',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (children.isNotEmpty)
                  IconButton(
                    icon: Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.amber.shade700,
                    ),
                    onPressed: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedParents.remove(parentId);
                        } else {
                          _expandedParents.add(parentId);
                        }
                      });
                    },
                  ),
                if (_canManageStock)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _navigateToForm(parentItem);
                      } else if (value == 'delete') {
                        _deleteStockItem(parentItem);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18),
                            SizedBox(width: 8),
                            Text('Edit Details'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Children items (when expanded)
          if (isExpanded && children.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 16, right: 8, bottom: 8),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: Colors.amber.shade300, width: 3),
                ),
              ),
              child: Column(
                children: children.map((child) {
                  return _buildChildItemCard(child, formatter);
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChildItemCard(Map<String, dynamic> item, NumberFormat formatter) {
    final currentQty = item['currentQuantity'] as int;
    final costPrice = (item['costPrice'] as num).toDouble();
    final sellingPrice = (item['sellingPrice'] as num).toDouble();

    return Card(
      margin: const EdgeInsets.only(left: 8, right: 0, top: 4, bottom: 4),
      elevation: 1,
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: Colors.brown.shade100,
          radius: 18,
          child: Icon(Icons.inventory, color: Colors.brown.shade700, size: 18),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item['itemName'],
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              ),
            ),
            _buildLowStockBadge(item),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Supplier: ${item['supplierName']}',
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: currentQty > 0 ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Qty: $currentQty',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: currentQty > 0 ? Colors.green.shade900 : Colors.red.shade900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Cost: ₦${formatter.format(costPrice)}',
                  style: const TextStyle(fontSize: 10),
                ),
                const SizedBox(width: 8),
                Text(
                  'Sell: ₦${formatter.format(sellingPrice)}',
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ],
        ),
        trailing: _canManageStock
            ? PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    _navigateToForm(item);
                  } else if (value == 'restock') {
                    _navigateToRestock(item);
                  } else if (value == 'adjust') {
                    _navigateToAdjustment(item);
                  } else if (value == 'delete') {
                    _deleteStockItem(item);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 18),
                        SizedBox(width: 8),
                        Text('Edit'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'restock',
                    child: Row(
                      children: [
                        Icon(Icons.add_shopping_cart, size: 18, color: Colors.green),
                        SizedBox(width: 8),
                        Text('Restock', style: TextStyle(color: Colors.green)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'adjust',
                    child: Row(
                      children: [
                        Icon(Icons.sync_alt, size: 18),
                        SizedBox(width: 8),
                        Text('Adjust Qty'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _buildRegularItemCard(Map<String, dynamic> item, NumberFormat formatter) {
    final currentQty = item['currentQuantity'] as int;
    final costPrice = (item['costPrice'] as num).toDouble();
    final sellingPrice = (item['sellingPrice'] as num).toDouble();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.brown.shade100,
          child: Icon(Icons.inventory, color: Colors.brown.shade700),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item['itemName'],
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            _buildLowStockBadge(item),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Supplier: ${item['supplierName']}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: currentQty > 0 ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Qty: $currentQty',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: currentQty > 0 ? Colors.green.shade900 : Colors.red.shade900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Cost: ₦${formatter.format(costPrice)}',
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(width: 8),
                Text(
                  'Sell: ₦${formatter.format(sellingPrice)}',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        trailing: _canManageStock
            ? PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    _navigateToForm(item);
                  } else if (value == 'restock') {
                    _navigateToRestock(item);
                  } else if (value == 'adjust') {
                    _navigateToAdjustment(item);
                  } else if (value == 'delete') {
                    _deleteStockItem(item);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 18),
                        SizedBox(width: 8),
                        Text('Edit Details'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'restock',
                    child: Row(
                      children: [
                        Icon(Icons.add_shopping_cart, size: 18, color: Colors.green),
                        SizedBox(width: 8),
                        Text('Restock Item', style: TextStyle(color: Colors.green)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'adjust',
                    child: Row(
                      children: [
                        Icon(Icons.sync_alt, size: 18),
                        SizedBox(width: 8),
                        Text('Adjust Quantity'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Items'),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadItems,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                labelText: 'Search items or suppliers',
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
                fillColor: Colors.brown.shade50,
              ),
              onChanged: (_) => _applyFilters(),
            ),
          ),

          // Filter chips
          if (_parentItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('All Items'),
                      selected: _selectedParentFilter == null,
                      onSelected: (selected) {
                        setState(() => _selectedParentFilter = null);
                        _applyFilters();
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Ungrouped'),
                      selected: _selectedParentFilter == 0,
                      onSelected: (selected) {
                        setState(() => _selectedParentFilter = selected ? 0 : null);
                        _applyFilters();
                      },
                    ),
                    ..._parentItems.map((parent) {
                      final parentId = parent['id'] as int;
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: FilterChip(
                          label: Text(parent['itemName']),
                          selected: _selectedParentFilter == parentId,
                          onSelected: (selected) {
                            setState(() => _selectedParentFilter = selected ? parentId : null);
                            _applyFilters();
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),

          // Items count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  '${_filteredItems.length} items',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Items list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredItems.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined,
                                size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              _searchCtrl.text.isEmpty
                                  ? 'No stock items yet'
                                  : 'No items found',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 16,
                              ),
                            ),
                            if (_searchCtrl.text.isEmpty && _canManageStock)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: ElevatedButton.icon(
                                  onPressed: () => _navigateToForm(),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add First Item'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.brown,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadItems,
                        child: ListView.builder(
                          itemCount: _filteredItems.length,
                          itemBuilder: (context, index) {
                            final item = _filteredItems[index];
                            final isParent = (item['isParent'] ?? 0) == 1;

                            // For parent items, build expandable card with children
                            if (isParent) {
                              return _buildParentCard(item, formatter);
                            }

                            // For regular items, build normal card
                            return _buildRegularItemCard(item, formatter);
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: _canManageStock
          ? FloatingActionButton.extended(
              onPressed: () => _navigateToForm(),
              icon: const Icon(Icons.add),
              label: const Text('Add Stock Item'),
              backgroundColor: Colors.brown,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }
}
