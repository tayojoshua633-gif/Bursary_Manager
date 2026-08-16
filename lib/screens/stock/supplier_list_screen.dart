// lib/screens/stock/supplier_list_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database_helper_wrapper.dart';
import '../../navigation/sidebar_scaffold.dart';
import 'supplier_form_screen.dart';

class SupplierListScreen extends StatefulWidget {
  const SupplierListScreen({super.key});

  @override
  State<SupplierListScreen> createState() => _SupplierListScreenState();
}

class _SupplierListScreenState extends State<SupplierListScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _allSuppliers = [];
  List<Map<String, dynamic>> _filteredSuppliers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    setState(() => _loading = true);

    try {
      final suppliers = await _db.getSuppliers();

      setState(() {
        _allSuppliers = suppliers;
        _filteredSuppliers = suppliers;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading suppliers: $e')),
      );
    }
  }

  void _applyFilters() {
    final keyword = _searchCtrl.text.trim().toLowerCase();

    setState(() {
      if (keyword.isEmpty) {
        _filteredSuppliers = _allSuppliers;
      } else {
        _filteredSuppliers = _allSuppliers.where((supplier) {
          final name = (supplier['supplierName'] ?? '').toString().toLowerCase();
          final contact = (supplier['contactPerson'] ?? '').toString().toLowerCase();
          final phone = (supplier['phoneNumber'] ?? '').toString().toLowerCase();
          return name.contains(keyword) ||
                 contact.contains(keyword) ||
                 phone.contains(keyword);
        }).toList();
      }
    });
  }

  Future<void> _navigateToForm([Map<String, dynamic>? supplier]) async {
    // Get current user for sidebar
    final prefs = await SharedPreferences.getInstance();
    final currentUser = {
      'id': prefs.getInt('userId') ?? 0,
      'userType': prefs.getString('userType') ?? 'bursar',
      'username': prefs.getString('username') ?? 'User',
    };

    // Check if we should show sidebar
    if (!mounted) return;
    final screenSize = MediaQuery.of(context).size;
    final showSidebar = screenSize.shortestSide >= 700;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => showSidebar
            ? SidebarScaffold(
                currentUser: currentUser,
                currentPageId: 'stock_sales/suppliers',
                child: SupplierFormScreen(supplier: supplier),
              )
            : SupplierFormScreen(supplier: supplier),
      ),
    );

    if (result == true) {
      _loadSuppliers();
    }
  }

  Future<void> _deleteSupplier(Map<String, dynamic> supplier) async {
    final supplierName = supplier['supplierName'];

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Supplier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to delete this supplier?'),
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
                    supplierName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (supplier['contactPerson'] != null &&
                      supplier['contactPerson'].toString().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Contact: ${supplier['contactPerson']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Note: This action cannot be undone. If this supplier is used in any stock items, deletion will be prevented.',
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
      await _db.deleteSupplier(supplier['id']);

      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Supplier deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );

      _loadSuppliers(); // Reload the list
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suppliers'),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSuppliers,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Prominent Add Button at the top
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.brown.shade50,
              border: Border(
                bottom: BorderSide(color: Colors.brown.shade200),
              ),
            ),
            child: ElevatedButton.icon(
              onPressed: () => _navigateToForm(),
              icon: const Icon(Icons.add, size: 24),
              label: const Text(
                'Add New Supplier',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.brown,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 2,
              ),
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                labelText: 'Search suppliers',
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

          // Suppliers count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  '${_filteredSuppliers.length} ${_filteredSuppliers.length == 1 ? "supplier" : "suppliers"}',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Suppliers list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSuppliers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.business_outlined,
                                size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              _searchCtrl.text.isEmpty
                                  ? 'No suppliers yet'
                                  : 'No suppliers found',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 16,
                              ),
                            ),
                            if (_searchCtrl.text.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: ElevatedButton.icon(
                                  onPressed: () => _navigateToForm(),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add First Supplier'),
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
                        onRefresh: _loadSuppliers,
                        child: ListView.builder(
                          itemCount: _filteredSuppliers.length,
                          itemBuilder: (context, index) {
                            final supplier = _filteredSuppliers[index];

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.brown.shade100,
                                  child: Icon(
                                    Icons.business,
                                    color: Colors.brown.shade700,
                                  ),
                                ),
                                title: Text(
                                  supplier['supplierName'],
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    if (supplier['contactPerson'] != null &&
                                        supplier['contactPerson'].toString().isNotEmpty)
                                      Text(
                                        'Contact: ${supplier['contactPerson']}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    if (supplier['phoneNumber'] != null &&
                                        supplier['phoneNumber'].toString().isNotEmpty)
                                      Text(
                                        'Phone: ${supplier['phoneNumber']}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    if (supplier['email'] != null &&
                                        supplier['email'].toString().isNotEmpty)
                                      Text(
                                        'Email: ${supplier['email']}',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                  ],
                                ),
                                isThreeLine: true,
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _navigateToForm(supplier);
                                    } else if (value == 'delete') {
                                      _deleteSupplier(supplier);
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
