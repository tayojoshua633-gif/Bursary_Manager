// lib/screens/stock/stock_adjustment_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database_helper_wrapper.dart';

class StockAdjustmentScreen extends StatefulWidget {
  final int stockItemId;
  final String itemName;
  final int currentQuantity;

  const StockAdjustmentScreen({
    super.key,
    required this.stockItemId,
    required this.itemName,
    required this.currentQuantity,
  });

  @override
  State<StockAdjustmentScreen> createState() => _StockAdjustmentScreenState();
}

class _StockAdjustmentScreenState extends State<StockAdjustmentScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final _formKey = GlobalKey<FormState>();
  final _newQuantityCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  bool _saving = false;
  String? _currentUsername;

  @override
  void initState() {
    super.initState();
    _newQuantityCtrl.text = widget.currentQuantity.toString();
    _loadCurrentUser();
  }

  @override
  void dispose() {
    _newQuantityCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUsername = prefs.getString('username') ?? 'User';
    });
  }

  int get _difference {
    final newQty = int.tryParse(_newQuantityCtrl.text.trim()) ?? 0;
    return newQty - widget.currentQuantity;
  }

  Future<void> _saveAdjustment() async {
    if (!_formKey.currentState!.validate()) return;

    final newQty = int.parse(_newQuantityCtrl.text.trim());
    if (newQty == widget.currentQuantity) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New quantity is same as current quantity')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await _db.adjustStockQuantity(
        widget.stockItemId,
        newQty,
        _reasonCtrl.text.trim(),
        createdBy: _currentUsername,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stock quantity adjusted successfully'),
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
    final difference = _difference;
    final isIncrease = difference > 0;
    final isDecrease = difference < 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adjust Stock Quantity'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Item Info Card
            Card(
              elevation: 2,
              color: Colors.indigo.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.inventory, color: Colors.indigo.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.itemName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text(
                          'Current Quantity: ',
                          style: TextStyle(fontSize: 14),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.indigo.shade300),
                          ),
                          child: Text(
                            '${widget.currentQuantity}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // New Quantity
            TextFormField(
              controller: _newQuantityCtrl,
              decoration: InputDecoration(
                labelText: 'New Quantity *',
                prefixIcon: const Icon(Icons.numbers),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.blue.shade50,
                helperText: 'Enter the new stock quantity',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter new quantity';
                if (int.tryParse(v) == null) return 'Enter valid number';
                if (int.parse(v) < 0) return 'Quantity cannot be negative';
                return null;
              },
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 16),

            // Difference indicator
            if (difference != 0)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isIncrease ? Colors.green.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isIncrease ? Colors.green.shade300 : Colors.orange.shade300,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isIncrease ? Icons.arrow_upward : Icons.arrow_downward,
                      color: isIncrease ? Colors.green.shade700 : Colors.orange.shade700,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isIncrease
                          ? 'Increasing by ${difference.abs()} units'
                          : 'Decreasing by ${difference.abs()} units',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isIncrease ? Colors.green.shade900 : Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Reason
            TextFormField(
              controller: _reasonCtrl,
              decoration: InputDecoration(
                labelText: 'Reason for Adjustment *',
                prefixIcon: const Icon(Icons.notes),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey.shade50,
                helperText: 'E.g., "Restocking from supplier", "Damaged items removed"',
              ),
              maxLines: 3,
              validator: (v) => v == null || v.isEmpty ? 'Enter reason for adjustment' : null,
              textCapitalization: TextCapitalization.sentences,
            ),

            const SizedBox(height: 24),

            // Info note
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
                      'This adjustment will be logged in the stock movement history for audit purposes.',
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
                onPressed: _saving ? null : _saveAdjustment,
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
                label: Text(_saving ? 'Saving...' : 'Save Adjustment'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
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
