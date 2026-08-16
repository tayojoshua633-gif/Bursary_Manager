// lib/screens/stock/stock_item_form_screen.dart
import 'package:flutter/material.dart';
import '../../data/database_helper_wrapper.dart';

class StockItemFormScreen extends StatefulWidget {
  final Map<String, dynamic>? item;

  const StockItemFormScreen({super.key, this.item});

  @override
  State<StockItemFormScreen> createState() => _StockItemFormScreenState();
}

class _StockItemFormScreenState extends State<StockItemFormScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final _formKey = GlobalKey<FormState>();

  final _itemNameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _supplierContactCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController();
  final _costPriceCtrl = TextEditingController();
  final _sellingPriceCtrl = TextEditingController();
  final _reorderLevelCtrl = TextEditingController();

  bool _saving = false;
  int? _selectedParentId;
  bool _isParent = false;
  List<Map<String, dynamic>> _parentItems = [];
  List<Map<String, dynamic>> _suppliers = [];
  String? _selectedSupplierName;

  @override
  void initState() {
    super.initState();
    _loadParentItems();
    _loadSuppliers();
    if (widget.item != null) {
      // Pre-fill for editing
      _itemNameCtrl.text = widget.item!['itemName'] ?? '';
      _descriptionCtrl.text = widget.item!['itemDescription'] ?? '';
      _selectedSupplierName = widget.item!['supplierName'] ?? '';
      _supplierContactCtrl.text = widget.item!['supplierContact'] ?? '';
      _costPriceCtrl.text = (widget.item!['costPrice'] ?? 0).toString();
      _sellingPriceCtrl.text = (widget.item!['sellingPrice'] ?? 0).toString();
      _reorderLevelCtrl.text = (widget.item!['reorderLevel'] ?? 0).toString();
      // Don't show current quantity in edit mode - use adjustment screen instead
    } else {
      _quantityCtrl.text = '0';
      _reorderLevelCtrl.text = '0';
    }
  }

  Future<void> _loadSuppliers() async {
    try {
      final suppliers = await _db.getSuppliers();
      setState(() {
        _suppliers = suppliers;
      });
    } catch (e) {
      print('Error loading suppliers: $e');
    }
  }

  Future<void> _loadParentItems() async {
    try {
      final parents = await _db.getParentItems();
      setState(() {
        _parentItems = parents;
        if (widget.item != null) {
          _selectedParentId = widget.item!['parentItemId'];
          _isParent = (widget.item!['isParent'] ?? 0) == 1;
        }
      });
    } catch (e) {
      print('Error loading parent items: $e');
    }
  }

  @override
  void dispose() {
    _itemNameCtrl.dispose();
    _descriptionCtrl.dispose();
    _supplierContactCtrl.dispose();
    _quantityCtrl.dispose();
    _costPriceCtrl.dispose();
    _sellingPriceCtrl.dispose();
    _reorderLevelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      // Validate parent-child relationship
      if (_selectedParentId != null && widget.item != null) {
        final canSet = await _db.canSetAsParent(widget.item!['id'], _selectedParentId);
        if (!canSet) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid parent selection. Cannot create circular references.'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => _saving = false);
          return;
        }
      }

      final payload = {
        'itemName': _itemNameCtrl.text.trim(),
        'itemDescription': _descriptionCtrl.text.trim(),
        'supplierName': _isParent ? '' : (_selectedSupplierName ?? ''),
        'supplierContact': _isParent ? '' : _supplierContactCtrl.text.trim(),
        'costPrice': _isParent ? 0.0 : double.parse(_costPriceCtrl.text.trim()),
        'sellingPrice': _isParent ? 0.0 : double.parse(_sellingPriceCtrl.text.trim()),
        'reorderLevel': _isParent ? 0 : (int.tryParse(_reorderLevelCtrl.text.trim()) ?? 0),
        'parentItemId': _selectedParentId,
        'isParent': _isParent ? 1 : 0,
      };

      if (widget.item == null) {
        // New item - include initial quantity (0 for parent items)
        payload['currentQuantity'] = _isParent ? 0 : (int.tryParse(_quantityCtrl.text.trim()) ?? 0);
        await _db.insertStockItem(payload);
      } else {
        // Edit - don't update quantity (use adjustment screen)
        await _db.updateStockItem(widget.item!['id'], payload);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.item == null
                ? 'Stock item added successfully'
                : 'Stock item updated successfully',
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.item != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Stock Item' : 'Add Stock Item'),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Item Type Section - MOVED TO TOP
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Item Type *',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<bool>(
                          title: const Text('Regular Item'),
                          subtitle: const Text('Has inventory, can be sold'),
                          value: false,
                          groupValue: _isParent,
                          onChanged: (val) {
                            setState(() {
                              _isParent = false;
                              _selectedParentId = null;
                            });
                          },
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<bool>(
                          title: const Text('Parent/Category'),
                          subtitle: const Text('Group header, no inventory'),
                          value: true,
                          groupValue: _isParent,
                          onChanged: (val) async {
                            if (widget.item != null) {
                              final hasChildren = await _db.hasChildItems(widget.item!['id']);
                              if (hasChildren) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Cannot convert to parent. Item has children.'),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                                return;
                              }
                            }
                            setState(() {
                              _isParent = true;
                              _selectedParentId = null;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Item Name
            TextFormField(
              controller: _itemNameCtrl,
              decoration: InputDecoration(
                labelText: 'Item Name *',
                prefixIcon: const Icon(Icons.inventory),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.brown.shade50,
              ),
              validator: (v) => v == null || v.isEmpty ? 'Enter item name' : null,
              textCapitalization: TextCapitalization.words,
            ),

            const SizedBox(height: 16),

            // Description
            TextFormField(
              controller: _descriptionCtrl,
              decoration: InputDecoration(
                labelText: 'Description (Optional)',
                prefixIcon: const Icon(Icons.description),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),

            const SizedBox(height: 16),

            // Supplier Dropdown - ONLY FOR REGULAR ITEMS
            if (!_isParent)
              DropdownButtonFormField<String>(
                initialValue: _selectedSupplierName,
                decoration: InputDecoration(
                  labelText: 'Supplier *',
                  prefixIcon: const Icon(Icons.business),
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.brown.shade50,
                  helperText: _suppliers.isEmpty
                      ? 'No suppliers yet. Add one from Suppliers menu.'
                      : 'Select from your suppliers',
                ),
                items: [
                  if (_suppliers.isEmpty)
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('No suppliers available'),
                    )
                  else ...[
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Select a supplier'),
                    ),
                    ..._suppliers.map((supplier) {
                      final name = supplier['supplierName'] as String;
                      return DropdownMenuItem<String>(
                        value: name,
                        child: Text(name),
                      );
                    }),
                  ],
                ],
                onChanged: (value) {
                  setState(() => _selectedSupplierName = value);
                },
                validator: (v) => v == null || v.isEmpty ? 'Select a supplier' : null,
              ),

            if (!_isParent) const SizedBox(height: 16),

            // Supplier Contact - ONLY FOR REGULAR ITEMS
            if (!_isParent)
              TextFormField(
                controller: _supplierContactCtrl,
                decoration: InputDecoration(
                  labelText: 'Supplier Contact (Optional)',
                  prefixIcon: const Icon(Icons.phone),
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                keyboardType: TextInputType.phone,
              ),

            if (!_isParent) const SizedBox(height: 16),

            // Parent Selection (only show if not a parent)
            if (!_isParent)
              DropdownButtonFormField<int?>(
                initialValue: _selectedParentId,
                decoration: InputDecoration(
                  labelText: 'Parent Category (Optional)',
                  prefixIcon: const Icon(Icons.category),
                  border: const OutlineInputBorder(),
                  helperText: 'Group this item under a category',
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('None (Top-level item)'),
                  ),
                  ..._parentItems.map((parent) {
                    return DropdownMenuItem<int?>(
                      value: parent['id'] as int,
                      child: Text(parent['itemName']),
                    );
                  }),
                ],
                onChanged: (value) {
                  setState(() => _selectedParentId = value);
                },
              ),

            if (!_isParent) const SizedBox(height: 16),

            // Info box for parent items
            if (_isParent)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Parent items are categories only. They cannot hold inventory or be sold.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            if (_isParent) const SizedBox(height: 16),

            // Initial Quantity (only for new items and non-parent items)
            if (!isEdit && !_isParent)
              TextFormField(
                controller: _quantityCtrl,
                decoration: InputDecoration(
                  labelText: 'Initial Quantity',
                  prefixIcon: const Icon(Icons.numbers),
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.blue.shade50,
                  helperText: 'Starting stock quantity',
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter quantity';
                  if (int.tryParse(v) == null) return 'Enter valid number';
                  if (int.parse(v) < 0) return 'Quantity cannot be negative';
                  return null;
                },
              ),

            if (!isEdit) const SizedBox(height: 16),

            // Cost Price
            TextFormField(
              controller: _costPriceCtrl,
              enabled: !_isParent,
              decoration: InputDecoration(
                labelText: _isParent ? 'Cost Price (Not applicable)' : 'Cost Price *',
                prefixText: '₦',
                prefixIcon: const Icon(Icons.money_off),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.orange.shade50,
                helperText: _isParent ? 'Parent items have no cost' : 'Purchase price from supplier',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                // Skip validation for parent items
                if (_isParent) return null;

                if (v == null || v.isEmpty) return 'Enter cost price';
                final price = double.tryParse(v);
                if (price == null) return 'Enter valid price';
                if (price <= 0) return 'Price must be greater than 0';
                return null;
              },
            ),

            const SizedBox(height: 16),

            // Selling Price
            TextFormField(
              controller: _sellingPriceCtrl,
              enabled: !_isParent,
              decoration: InputDecoration(
                labelText: _isParent ? 'Selling Price (Not applicable)' : 'Selling Price *',
                prefixText: '₦',
                prefixIcon: const Icon(Icons.attach_money),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.green.shade50,
                helperText: _isParent ? 'Parent items cannot be sold' : 'Price to sell to customers',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                // Skip validation for parent items
                if (_isParent) return null;

                if (v == null || v.isEmpty) return 'Enter selling price';
                final price = double.tryParse(v);
                if (price == null) return 'Enter valid price';
                if (price <= 0) return 'Price must be greater than 0';

                // Warn if selling price is less than cost price
                final costPrice = double.tryParse(_costPriceCtrl.text.trim());
                if (costPrice != null && price < costPrice) {
                  return 'Warning: Selling price is less than cost price';
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            // Reorder Level
            TextFormField(
              controller: _reorderLevelCtrl,
              enabled: !_isParent,
              decoration: InputDecoration(
                labelText: _isParent ? 'Reorder Level (Not applicable)' : 'Reorder Level',
                prefixIcon: const Icon(Icons.notifications),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey.shade50,
                helperText: _isParent ? 'Parent items have no inventory' : 'Alert when stock falls to or below this level',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (_isParent) return null;
                if (v == null || v.isEmpty) return null;
                if (int.tryParse(v) == null) return 'Enter valid number';
                if (int.parse(v) < 0) return 'Cannot be negative';
                return null;
              },
            ),

            const SizedBox(height: 24),

            // Note for edit mode
            if (isEdit)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'To adjust stock quantity, use the "Adjust Quantity" option from the stock list.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            if (isEdit) const SizedBox(height: 16),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(_saving ? 'Saving...' : 'Save Stock Item'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.brown,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
