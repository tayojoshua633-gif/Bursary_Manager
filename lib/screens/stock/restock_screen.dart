// lib/screens/stock/restock_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';

class RestockScreen extends StatefulWidget {
  final int stockItemId;
  final String itemName;
  final int currentQuantity;
  final double currentCostPrice;
  final String currentSupplier;

  const RestockScreen({
    super.key,
    required this.stockItemId,
    required this.itemName,
    required this.currentQuantity,
    required this.currentCostPrice,
    required this.currentSupplier,
  });

  @override
  State<RestockScreen> createState() => _RestockScreenState();
}

class _RestockScreenState extends State<RestockScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final _formKey = GlobalKey<FormState>();
  final _quantityCtrl = TextEditingController();
  final _costPriceCtrl = TextEditingController();
  final _supplierCtrl = TextEditingController();
  final _invoiceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _saving = false;
  bool _updateCostPrice = false;
  String? _currentUsername;

  @override
  void initState() {
    super.initState();
    _costPriceCtrl.text = widget.currentCostPrice.toStringAsFixed(2);
    _supplierCtrl.text = widget.currentSupplier;
    _loadCurrentUser();
  }

  @override
  void dispose() {
    _quantityCtrl.dispose();
    _costPriceCtrl.dispose();
    _supplierCtrl.dispose();
    _invoiceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUsername = prefs.getString('username') ?? 'User';
    });
  }

  int get _newQuantity {
    final qty = int.tryParse(_quantityCtrl.text.trim()) ?? 0;
    return widget.currentQuantity + qty;
  }

  double get _totalCost {
    final qty = int.tryParse(_quantityCtrl.text.trim()) ?? 0;
    final cost = double.tryParse(_costPriceCtrl.text.trim()) ?? 0;
    return qty * cost;
  }

  Future<void> _saveRestock() async {
    if (!_formKey.currentState!.validate()) return;

    final qtyToAdd = int.parse(_quantityCtrl.text.trim());
    if (qtyToAdd <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantity must be greater than 0')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final newCostPrice = _updateCostPrice
          ? double.parse(_costPriceCtrl.text.trim())
          : null;

      await _db.restockItem(
        widget.stockItemId,
        quantityAdded: qtyToAdd,
        supplier: _supplierCtrl.text.trim(),
        invoiceNumber: _invoiceCtrl.text.trim(),
        newCostPrice: newCostPrice,
        notes: _notesCtrl.text.trim(),
        createdBy: _currentUsername,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully restocked $qtyToAdd units'),
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
    final formatter = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Restock Item'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Item Info Card
            Card(
              elevation: 3,
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.inventory_2, color: Colors.green.shade700, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.itemName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Current Supplier: ${widget.currentSupplier}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Text(
                              'Current Stock',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.shade300),
                              ),
                              child: Text(
                                '${widget.currentQuantity}',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Icon(Icons.arrow_forward, color: Colors.green.shade400),
                        Column(
                          children: [
                            Text(
                              'After Restock',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.shade300),
                              ),
                              child: Text(
                                '$_newQuantity',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Quantity to Add
            TextFormField(
              controller: _quantityCtrl,
              decoration: InputDecoration(
                labelText: 'Quantity to Add *',
                prefixIcon: const Icon(Icons.add_box),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.green.shade50,
                helperText: 'Number of units to restock',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter quantity';
                if (int.tryParse(v) == null) return 'Enter valid number';
                if (int.parse(v) <= 0) return 'Must be greater than 0';
                return null;
              },
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 16),

            // Supplier Name
            TextFormField(
              controller: _supplierCtrl,
              decoration: InputDecoration(
                labelText: 'Supplier Name *',
                prefixIcon: const Icon(Icons.business),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey.shade50,
                helperText: 'Who supplied this restock',
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) => v == null || v.isEmpty ? 'Enter supplier name' : null,
            ),

            const SizedBox(height: 16),

            // Invoice/Reference Number
            TextFormField(
              controller: _invoiceCtrl,
              decoration: InputDecoration(
                labelText: 'Invoice/Reference Number',
                prefixIcon: const Icon(Icons.receipt_long),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey.shade50,
                helperText: 'Optional: Invoice or receipt number',
              ),
              textCapitalization: TextCapitalization.characters,
            ),

            const SizedBox(height: 16),

            // Cost Price Section
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: _updateCostPrice,
                          onChanged: (v) => setState(() => _updateCostPrice = v ?? false),
                        ),
                        const Expanded(
                          child: Text(
                            'Update Cost Price',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    if (_updateCostPrice) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _costPriceCtrl,
                        decoration: InputDecoration(
                          labelText: 'New Cost Price per Unit *',
                          prefixIcon: const Icon(Icons.attach_money),
                          prefixText: '₦',
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.orange.shade50,
                          helperText: 'Current: ₦${formatter.format(widget.currentCostPrice)}',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (_updateCostPrice) {
                            if (v == null || v.isEmpty) return 'Enter new cost price';
                            if (double.tryParse(v) == null) return 'Enter valid amount';
                            if (double.parse(v) <= 0) return 'Must be greater than 0';
                          }
                          return null;
                        },
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Text(
                          'This will update the cost price for future sales and profit calculations.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      Text(
                        'Using current cost price: ₦${formatter.format(widget.currentCostPrice)} per unit',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Total Cost Summary
            if (_quantityCtrl.text.isNotEmpty && int.tryParse(_quantityCtrl.text) != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade300, width: 2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Purchase Cost:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '₦${formatter.format(_totalCost)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Notes
            TextFormField(
              controller: _notesCtrl,
              decoration: InputDecoration(
                labelText: 'Notes (Optional)',
                prefixIcon: const Icon(Icons.notes),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey.shade50,
                helperText: 'Additional notes about this restock',
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),

            const SizedBox(height: 24),

            // Info note
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber.shade900, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'This restock will be logged in the purchase history for inventory tracking and audit purposes.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _saveRestock,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.check_circle),
                label: Text(_saving ? 'Processing Restock...' : 'Complete Restock'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
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
