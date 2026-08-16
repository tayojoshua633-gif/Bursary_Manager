// lib/screens/sales/sale_record_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database_helper_wrapper.dart';
import '../../navigation/sidebar_scaffold.dart';
import '../../utils/backup_reminder_helper.dart';
import 'sale_receipt_screen.dart';

class SaleRecordScreen extends StatefulWidget {
  final Map<String, dynamic> buyerInfo;
  final List<Map<String, dynamic>>? initialCartItems;

  const SaleRecordScreen({
    super.key,
    required this.buyerInfo,
    this.initialCartItems,
  });

  @override
  State<SaleRecordScreen> createState() => _SaleRecordScreenState();
}

class _SaleRecordScreenState extends State<SaleRecordScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final _quantityCtrl = TextEditingController();
  final _unitPriceCtrl = TextEditingController();
  final _amountPaidCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _customItemNameCtrl = TextEditingController();

  List<Map<String, dynamic>> _stockItems = [];
  List<Map<String, dynamic>> _filteredStockItems = [];
  List<Map<String, dynamic>> _parentItems = [];
  int? _selectedParentFilter;
  int? _selectedStockItemId;
  Map<String, dynamic>? _selectedStockItem;
  String? _selectedMethod;
  String _selectedPaymentStatus = 'Paid';
  final DateTime _selectedDate = DateTime.now();
  double _totalAmount = 0.0;
  bool _loading = true;
  String? _term;
  String? _session;
  String? _currentUsername;

  // Toggle between stock item and custom item
  bool _isCustomItem = false;

  // Cart for multi-item sales
  final List<Map<String, dynamic>> _cartItems = [];
  double _cartTotalAmount = 0.0;

  final List<String> _paymentMethods = ['Cash', 'Transfer', 'POS'];
  final List<String> _paymentStatuses = ['Paid', 'Credit', 'Part Payment'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _quantityCtrl.dispose();
    _unitPriceCtrl.dispose();
    _amountPaidCtrl.dispose();
    _noteCtrl.dispose();
    _customItemNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      final stockItems = await _db.getStockItems();
      final parentItems = await _db.getParentItems();
      final activeTerm = await _db.getActiveTerm();
      final activeSession = await _db.getActiveSession();
      final prefs = await SharedPreferences.getInstance();

      setState(() {
        _stockItems = stockItems.where((item) {
          final qty = item['currentQuantity'] as int;
          final isParent = (item['isParent'] ?? 0) == 1;
          return qty > 0 && !isParent; // Only items with stock, not parents
        }).toList();
        _filteredStockItems = _stockItems;
        _parentItems = parentItems;
        _term = activeTerm;
        _session = activeSession?['sessionName'];
        _currentUsername = prefs.getString('username') ?? 'User';
        _loading = false;
      });

      // Pre-load cart items for debt payment
      if (widget.initialCartItems != null && widget.initialCartItems!.isNotEmpty) {
        setState(() {
          _cartItems.clear();
          _cartItems.addAll(widget.initialCartItems!);
          _calculateCartTotal();
        });

        // Set payment status to Part Payment for debt repayment
        if (widget.buyerInfo['isPayingDebt'] == true) {
          setState(() {
            _selectedPaymentStatus = 'Part Payment';
          });
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_cartItems.length} outstanding item(s) loaded for payment'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading data: $e')),
      );
    }
  }

  void _applyStockFilter() {
    setState(() {
      if (_selectedParentFilter == null) {
        // Show all items when no category is selected
        _filteredStockItems = _stockItems;
      } else {
        // Show ONLY children of the selected parent category
        _filteredStockItems = _stockItems.where((item) {
          return item['parentItemId'] == _selectedParentFilter;
        }).toList();
      }

      // Reset item selection when filter changes
      _selectedStockItemId = null;
      _selectedStockItem = null;
      _unitPriceCtrl.clear();
      _totalAmount = 0.0;
    });
  }

  void _onStockItemChanged(int? stockItemId) {
    if (stockItemId == null) return;

    final item = _stockItems.firstWhere((s) => s['id'] == stockItemId);

    setState(() {
      _selectedStockItemId = stockItemId;
      _selectedStockItem = item;
      _unitPriceCtrl.text = item['sellingPrice'].toString();
      _calculateTotal();
    });
  }

  void _calculateTotal() {
    final qty = int.tryParse(_quantityCtrl.text.trim()) ?? 0;
    final unitPrice = double.tryParse(_unitPriceCtrl.text.trim()) ?? 0.0;
    final totalAmount = qty * unitPrice;

    setState(() {
      _totalAmount = totalAmount;
    });
  }

  void _addToCart() {
    // Common validation
    final qty = int.tryParse(_quantityCtrl.text.trim()) ?? 0;
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid quantity')),
      );
      return;
    }

    final unitPrice = double.tryParse(_unitPriceCtrl.text.trim()) ?? 0.0;
    if (unitPrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid unit price')),
      );
      return;
    }

    if (_isCustomItem) {
      // CUSTOM ITEM: No stock validation needed
      final customItemName = _customItemNameCtrl.text.trim();
      if (customItemName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter item name')),
        );
        return;
      }

      // Check if same custom item already in cart
      final existingIndex = _cartItems.indexWhere(
        (item) => item['isCustomItem'] == true && item['itemName'] == customItemName,
      );

      if (existingIndex != -1) {
        // Update existing cart item
        final existingQty = _cartItems[existingIndex]['quantity'] as int;
        final newQty = existingQty + qty;

        setState(() {
          _cartItems[existingIndex]['quantity'] = newQty;
          _cartItems[existingIndex]['totalAmount'] = newQty * (_cartItems[existingIndex]['unitPrice'] as double);
          _calculateCartTotal();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Updated $customItemName quantity to $newQty'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // Add new custom item to cart
        final cartItem = {
          'stockItemId': 0, // Use 0 as sentinel value for custom items (DB NOT NULL constraint)
          'itemName': customItemName,
          'quantity': qty,
          'unitPrice': unitPrice,
          'totalAmount': _totalAmount,
          'isCustomItem': true, // Mark as custom item
        };

        setState(() {
          _cartItems.add(cartItem);
          _calculateCartTotal();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added $customItemName to cart'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Reset form
      setState(() {
        _customItemNameCtrl.clear();
        _quantityCtrl.clear();
        _unitPriceCtrl.clear();
        _totalAmount = 0.0;
      });
    } else {
      // STOCK ITEM: With stock validation
      if (_selectedStockItemId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select a stock item')),
        );
        return;
      }

      final available = _selectedStockItem!['currentQuantity'] as int;
      if (qty > available) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Insufficient stock. Available: $available'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Check if item already in cart
      final existingIndex = _cartItems.indexWhere(
        (item) => item['stockItemId'] == _selectedStockItemId && item['isCustomItem'] != true,
      );

      if (existingIndex != -1) {
        // Update existing cart item
        final existingQty = _cartItems[existingIndex]['quantity'] as int;
        final newQty = existingQty + qty;

        if (newQty > available) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Total quantity ($newQty) exceeds available stock ($available)'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        setState(() {
          _cartItems[existingIndex]['quantity'] = newQty;
          _cartItems[existingIndex]['totalAmount'] = newQty * (_cartItems[existingIndex]['unitPrice'] as double);
          _calculateCartTotal();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Updated ${_selectedStockItem!['itemName']} quantity to $newQty'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // Add new item to cart
        final cartItem = {
          'stockItemId': _selectedStockItemId,
          'itemName': _selectedStockItem!['itemName'],
          'quantity': qty,
          'unitPrice': unitPrice,
          'totalAmount': _totalAmount,
          'availableStock': available,
          'isCustomItem': false,
        };

        setState(() {
          _cartItems.add(cartItem);
          _calculateCartTotal();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${_selectedStockItem!['itemName']} to cart'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Reset form
      setState(() {
        _selectedStockItemId = null;
        _selectedStockItem = null;
        _quantityCtrl.clear();
        _unitPriceCtrl.clear();
        _totalAmount = 0.0;
      });
    }
  }

  void _removeFromCart(int index) {
    final item = _cartItems[index];
    setState(() {
      _cartItems.removeAt(index);
      _calculateCartTotal();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed ${item['itemName']} from cart'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _calculateCartTotal() {
    double total = 0.0;
    final bool isDebtPayment = widget.buyerInfo['isPayingDebt'] == true;

    for (final item in _cartItems) {
      // For debt payment, use outstanding balance; for new sales, use total amount
      if (isDebtPayment && item.containsKey('outstandingBalance')) {
        total += (item['outstandingBalance'] as num).toDouble();
      } else {
        total += (item['totalAmount'] as num).toDouble();
      }
    }

    setState(() {
      _cartTotalAmount = total;
    });
  }

  Future<void> _saveSale() async {
    // Validation - cart must have items
    if (_cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cart is empty. Add items to cart first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Skip payment method validation for Credit purchases
    if (_selectedPaymentStatus != 'Credit' && _selectedMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select payment method')),
      );
      return;
    }

    // Validate part payment
    if (_selectedPaymentStatus == 'Part Payment') {
      final amountPaid = double.tryParse(_amountPaidCtrl.text.trim()) ?? 0.0;
      if (amountPaid <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter valid amount paid')),
        );
        return;
      }
      if (amountPaid > _cartTotalAmount) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Amount paid cannot exceed total amount'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Validate cart total
      if (_cartTotalAmount <= 0) {
        if (!mounted) return;
        Navigator.pop(context); // Dismiss loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid cart total. Please check items and try again.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Calculate amount paid and outstanding balance for the entire cart
      double totalAmountPaid;
      double totalOutstanding;

      if (_selectedPaymentStatus == 'Credit') {
        totalAmountPaid = 0.0;
        totalOutstanding = _cartTotalAmount;
      } else if (_selectedPaymentStatus == 'Part Payment') {
        totalAmountPaid = double.parse(_amountPaidCtrl.text.trim());
        totalOutstanding = _cartTotalAmount - totalAmountPaid;
      } else {
        // Paid status - amount paid equals cart total
        totalAmountPaid = _cartTotalAmount;
        totalOutstanding = 0.0;
      }

      // Debug output
      print('=== SALE DEBUG ===');
      print('Payment Status: $_selectedPaymentStatus');
      print('Cart Total: ₦$_cartTotalAmount');
      print('Total Amount Paid: ₦$totalAmountPaid');
      print('Total Outstanding: ₦$totalOutstanding');
      print('Number of items: ${_cartItems.length}');

      // Check if this is a debt payment (updating existing sales) or new sale
      final bool isDebtPayment = widget.buyerInfo['isPayingDebt'] == true;
      final List<int> saleIds = [];

      // Generate a single timestamp for all payment receipts in this transaction
      // This ensures they all group together in the sales report
      final paymentTimestamp = DateTime.now().toIso8601String();

      for (final cartItem in _cartItems) {
        final itemTotal = (cartItem['totalAmount'] as num).toDouble();

        if (isDebtPayment) {
          // DEBT PAYMENT: Update existing sale with additional payment
          final saleId = cartItem['saleId'] as int;
          final previousAmountPaid = (cartItem['amountPaid'] as num?)?.toDouble() ?? 0.0;
          final itemOutstanding = (cartItem['outstandingBalance'] as num?)?.toDouble() ?? 0.0;

          // Calculate proportional payment for this item based on outstanding balance
          final itemProportion = _cartTotalAmount > 0 ? itemOutstanding / _cartTotalAmount : 0;
          final additionalPayment = totalAmountPaid * itemProportion;
          final newAmountPaid = previousAmountPaid + additionalPayment;
          final newOutstanding = itemTotal - newAmountPaid;

          // Determine new payment status
          String newPaymentStatus;
          if (newAmountPaid == 0) {
            newPaymentStatus = 'Credit';
          } else if (newAmountPaid > 0 && newAmountPaid < itemTotal) {
            newPaymentStatus = 'Part Payment';
          } else {
            newPaymentStatus = 'Paid';
          }

          print('DEBT PAYMENT - Item: ${cartItem['itemName']}, Previous Paid: ₦$previousAmountPaid, Additional: ₦$additionalPayment, New Total Paid: ₦$newAmountPaid, Outstanding: ₦$newOutstanding');

          // Update the existing sale and get the payment receipt ID
          final paymentReceiptId = await _db.updateSalePayment(
            saleId,
            amountPaid: newAmountPaid,
            outstandingBalance: newOutstanding,
            paymentStatus: newPaymentStatus,
            additionalPayment: additionalPayment,
            paymentMethod: _selectedMethod,
            note: _noteCtrl.text.trim(),
            term: _term,
            session: _session,
            createdBy: _currentUsername,
            paymentTimestamp: paymentTimestamp,
          );

          // Add the payment receipt ID to show on the receipt, not the original sale ID
          if (paymentReceiptId > 0) {
            saleIds.add(paymentReceiptId);
            print('Payment receipt ID: $paymentReceiptId created for ₦$additionalPayment');
          } else {
            print('No payment receipt created (additionalPayment was 0)');
          }

        } else {
          // NEW SALE: Create new sale record
          final itemProportion = _cartTotalAmount > 0 ? itemTotal / _cartTotalAmount : 0;
          final itemAmountPaid = totalAmountPaid * itemProportion;
          final itemOutstanding = itemTotal - itemAmountPaid;
          final isCustomItem = cartItem['isCustomItem'] == true;

          print('NEW SALE - Item: ${cartItem['itemName']}, Total: ₦$itemTotal, Paid: ₦$itemAmountPaid, Outstanding: ₦$itemOutstanding, Custom: $isCustomItem');

          // Build note - include custom item indicator if applicable
          String saleNote = _noteCtrl.text.trim();
          if (isCustomItem && saleNote.isEmpty) {
            saleNote = 'Custom item (not in stock)';
          } else if (isCustomItem) {
            saleNote = '$saleNote [Custom item]';
          }

          final sale = {
            'studentId': widget.buyerInfo['studentId'],
            'buyerName': widget.buyerInfo['buyerName'],
            'buyerType': widget.buyerInfo['buyerType'],
            'stockItemId': cartItem['stockItemId'], // 0 for custom items
            'itemName': cartItem['itemName'], // Store item name directly for custom items
            'quantity': cartItem['quantity'],
            'unitPrice': (cartItem['unitPrice'] as num).toDouble(),
            'totalAmount': itemTotal,
            'paymentMethod': _selectedPaymentStatus == 'Credit' ? 'N/A' : _selectedMethod,
            'paymentStatus': _selectedPaymentStatus,
            'amountPaid': itemAmountPaid,
            'outstandingBalance': itemOutstanding,
            'note': saleNote,
            'saleDate': _selectedDate.toIso8601String(),
            'term': _term,
            'session': _session,
            'isCustomItem': isCustomItem ? 1 : 0, // Flag for custom items
          };

          final saleId = await _db.insertSale(sale, createdBy: _currentUsername);
          saleIds.add(saleId);
          print('Saved sale ID: $saleId with amountPaid: ₦${sale['amountPaid']}');
        }
      }
      print('=== END SALE DEBUG ===');

      // Track backup reminder
      await BackupReminderHelper.incrementTransactionCount();

      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_cartItems.length} item(s) recorded successfully'),
          backgroundColor: Colors.green,
        ),
      );

      // Capture route reference before await to detect sidebar navigation
      final currentRoute = ModalRoute.of(context);

      // Navigate to multi-item receipt screen
      if (saleIds.isNotEmpty) {
        // Get current user for sidebar
        final prefs = await SharedPreferences.getInstance();
        final currentUser = {
          'id': prefs.getInt('userId') ?? 0,
          'userType': prefs.getString('userType') ?? 'bursar',
          'username': _currentUsername ?? 'User',
        };

        // Check if we should show sidebar
        if (!mounted) return;
        final screenSize = MediaQuery.of(context).size;
        final showSidebar = screenSize.shortestSide >= 700;

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => showSidebar
                ? SidebarScaffold(
                    currentUser: currentUser,
                    currentPageId: 'stock_sales/record_sale',
                    child: SaleReceiptScreen(saleIds: saleIds),
                  )
                : SaleReceiptScreen(saleIds: saleIds),
          ),
        );
      }

      // Close this screen and buyer selection
      // Skip if our route was already popped (e.g. sidebar navigated home)
      if (mounted && currentRoute?.isActive == true) {
        Navigator.pop(context);
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Sale'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Buyer Info Card
                  Card(
                    elevation: 2,
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Colors.blue.shade700,
                                child: Icon(
                                  widget.buyerInfo['buyerType'] == 'Student'
                                      ? Icons.school
                                      : Icons.person,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.buyerInfo['buyerName'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    if (widget.buyerInfo['className'] != null)
                                      Text(
                                        '${widget.buyerInfo['className']} ${widget.buyerInfo['armName']}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade700,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  widget.buyerInfo['buyerType'],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Existing Outstanding Balance Alert (if any)
                  if (widget.buyerInfo['existingOutstanding'] != null &&
                      (widget.buyerInfo['existingOutstanding'] as double) > 0)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade300, width: 2),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Existing Outstanding Balance',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '₦${formatter.format(widget.buyerInfo['existingOutstanding'])}',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'This buyer has previous unpaid balance',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 20),

                  // Term/Session Info
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.indigo.shade200),
                        ),
                        child: Text(
                          _term ?? 'No Term',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.indigo.shade200),
                        ),
                        child: Text(
                          _session ?? 'No Session',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Item Type Toggle (Stock Item vs Custom Item) - PROMINENT SELECTION
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.indigo.shade50, Colors.purple.shade50],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.indigo.shade200, width: 2),
                    ),
                    child: Column(
                      children: [
                        // Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shopping_bag, color: Colors.indigo.shade700, size: 24),
                            const SizedBox(width: 8),
                            Text(
                              'SELECT ITEM TYPE',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.indigo.shade900,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Two prominent selection cards
                        Row(
                          children: [
                            // Stock Item Card
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  if (_isCustomItem) {
                                    setState(() {
                                      _isCustomItem = false;
                                      _customItemNameCtrl.clear();
                                      _quantityCtrl.clear();
                                      _unitPriceCtrl.clear();
                                      _totalAmount = 0.0;
                                    });
                                  }
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: !_isCustomItem ? Colors.teal.shade500 : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: !_isCustomItem ? Colors.teal.shade700 : Colors.grey.shade300,
                                      width: !_isCustomItem ? 3 : 1,
                                    ),
                                    boxShadow: !_isCustomItem
                                        ? [
                                            BoxShadow(
                                              color: Colors.teal.withValues(alpha: 0.4),
                                              blurRadius: 8,
                                              offset: const Offset(0, 4),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.inventory_2,
                                        size: 40,
                                        color: !_isCustomItem ? Colors.white : Colors.grey.shade600,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        'STOCK ITEM',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: !_isCustomItem ? Colors.white : Colors.grey.shade700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'From inventory',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: !_isCustomItem ? Colors.white70 : Colors.grey.shade500,
                                        ),
                                      ),
                                      if (!_isCustomItem) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.3),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.check_circle, size: 14, color: Colors.white),
                                              SizedBox(width: 4),
                                              Text(
                                                'Selected',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(width: 12),

                            // Custom Item Card
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  if (!_isCustomItem) {
                                    setState(() {
                                      _isCustomItem = true;
                                      _selectedStockItemId = null;
                                      _selectedStockItem = null;
                                      _quantityCtrl.clear();
                                      _unitPriceCtrl.clear();
                                      _totalAmount = 0.0;
                                    });
                                  }
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: _isCustomItem ? Colors.purple.shade500 : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _isCustomItem ? Colors.purple.shade700 : Colors.grey.shade300,
                                      width: _isCustomItem ? 3 : 1,
                                    ),
                                    boxShadow: _isCustomItem
                                        ? [
                                            BoxShadow(
                                              color: Colors.purple.withValues(alpha: 0.4),
                                              blurRadius: 8,
                                              offset: const Offset(0, 4),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.edit_note,
                                        size: 40,
                                        color: _isCustomItem ? Colors.white : Colors.grey.shade600,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        'CUSTOM ITEM',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: _isCustomItem ? Colors.white : Colors.grey.shade700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Not in stock',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _isCustomItem ? Colors.white70 : Colors.grey.shade500,
                                        ),
                                      ),
                                      if (_isCustomItem) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.3),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.check_circle, size: 14, color: Colors.white),
                                              SizedBox(width: 4),
                                              Text(
                                                'Selected',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Helper text for custom items
                        if (_isCustomItem)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.info_outline, size: 16, color: Colors.purple.shade700),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Custom items are not tracked in inventory',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.purple.shade900,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // STOCK ITEM MODE: Category Filter and Stock Item Selection
                  if (!_isCustomItem) ...[
                    // Category Filter
                    if (_parentItems.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: DropdownButtonFormField<int?>(
                          key: ValueKey('category_$_selectedParentFilter'),
                          initialValue: _selectedParentFilter,
                          decoration: InputDecoration(
                            labelText: 'Filter by Category',
                            prefixIcon: const Icon(Icons.filter_list),
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.blue.shade50,
                          ),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('All Items'),
                            ),
                            ..._parentItems.map((parent) {
                              return DropdownMenuItem<int?>(
                                value: parent['id'] as int,
                                child: Text(parent['itemName']),
                              );
                            }),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedParentFilter = value);
                            _applyStockFilter();
                          },
                        ),
                      ),

                    // Stock Item Selection Dropdown
                    DropdownButtonFormField<int>(
                      key: ValueKey('stock_$_selectedStockItemId'),
                      initialValue: _selectedStockItemId,
                      decoration: InputDecoration(
                        labelText: _selectedParentFilter == null
                            ? 'Select Item * (Select category first)'
                            : 'Select Item *',
                        prefixIcon: const Icon(Icons.inventory),
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.green.shade50,
                        helperText: _filteredStockItems.isEmpty
                            ? (_selectedParentFilter == null
                                ? 'Select a category to see items'
                                : 'No items in this category')
                            : '${_filteredStockItems.length} items available',
                      ),
                      items: _filteredStockItems.isEmpty
                          ? [
                              const DropdownMenuItem<int>(
                                value: null,
                                enabled: false,
                                child: Text('No items available'),
                              )
                            ]
                          : _filteredStockItems.map((item) {
                              final itemId = item['id'] as int;
                              final itemName = item['itemName'] as String;
                              final qty = item['currentQuantity'] as int;
                              final price = (item['sellingPrice'] as num).toDouble();

                              return DropdownMenuItem<int>(
                                value: itemId,
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '$qty',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade900,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '$itemName - ₦${NumberFormat('#,##0.00').format(price)}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                      onChanged: (value) {
                        _onStockItemChanged(value);
                      },
                      validator: (value) => value == null ? 'Select an item' : null,
                    ),

                    const SizedBox(height: 16),
                  ],

                  // CUSTOM ITEM MODE: Item Name Text Field
                  if (_isCustomItem) ...[
                    TextFormField(
                      controller: _customItemNameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Item Name *',
                        hintText: 'Enter item name (e.g., School Bag)',
                        prefixIcon: const Icon(Icons.edit),
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.purple.shade50,
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),

                    const SizedBox(height: 16),
                  ],

                  // Quantity and Unit Price
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _quantityCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Quantity *',
                            prefixIcon: const Icon(Icons.numbers),
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          onChanged: (_) {
                            _calculateTotal();
                            // Validate quantity only for stock items (not custom items)
                            if (!_isCustomItem && _selectedStockItem != null) {
                              final qty = int.tryParse(_quantityCtrl.text) ?? 0;
                              final available = _selectedStockItem?['currentQuantity'] ?? 0;
                              if (qty > available) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Insufficient stock. Available: $available'),
                                    backgroundColor: Colors.red,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _unitPriceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Unit Price *',
                            prefixText: '₦',
                            prefixIcon: const Icon(Icons.money),
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          onChanged: (_) => _calculateTotal(),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Total Amount Display
                  Card(
                    elevation: 2,
                    color: Colors.green.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Amount:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '₦${formatter.format(_totalAmount)}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Add to Cart Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const Text(
                        'Add to Cart',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: _addToCart,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Cart Items Display
                  if (_cartItems.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200, width: 2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.shopping_cart, color: Colors.blue.shade700),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Cart Items',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade700,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${_cartItems.length} item(s)',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ..._cartItems.asMap().entries.map((entry) {
                            final index = entry.key;
                            final item = entry.value;
                            final isCustom = item['isCustomItem'] == true;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  backgroundColor: isCustom ? Colors.purple.shade100 : Colors.blue.shade100,
                                  radius: 16,
                                  child: Text(
                                    '${item['quantity']}',
                                    style: TextStyle(
                                      color: isCustom ? Colors.purple.shade900 : Colors.blue.shade900,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item['itemName'],
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (isCustom)
                                      Container(
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
                                subtitle: Text(
                                  '${item['quantity']} × ₦${formatter.format(item['unitPrice'])}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '₦${formatter.format(item['totalAmount'])}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, size: 18),
                                      color: Colors.red,
                                      onPressed: () => _removeFromCart(index),
                                      tooltip: 'Remove',
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Cart Total:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '₦${formatter.format(_cartTotalAmount)}',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Payment Status
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: 'Payment Status *',
                      prefixIcon: const Icon(Icons.account_balance_wallet),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.orange.shade50,
                    ),
                    initialValue: _selectedPaymentStatus,
                    items: _paymentStatuses
                        .map((s) => DropdownMenuItem<String>(
                              value: s,
                              child: Text(s),
                            ))
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedPaymentStatus = v!;
                        // Auto-fill amount paid for 'Paid' status
                        if (_selectedPaymentStatus == 'Paid') {
                          _amountPaidCtrl.text = _totalAmount.toString();
                        } else if (_selectedPaymentStatus == 'Credit') {
                          _amountPaidCtrl.clear();
                        }
                        _calculateTotal();
                      });
                    },
                  ),

                  const SizedBox(height: 16),

                  // Amount Paid (conditional - only for Part Payment)
                  if (_selectedPaymentStatus == 'Part Payment')
                    Column(
                      children: [
                        TextField(
                          controller: _amountPaidCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Amount Paid *',
                            prefixText: '₦',
                            prefixIcon: const Icon(Icons.money),
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.blue.shade50,
                            hintText: 'Enter amount paid',
                          ),
                          onChanged: (_) => _calculateTotal(),
                        ),
                        const SizedBox(height: 12),
                        // Outstanding Balance Display (Cart Total - Amount Paid)
                        if (_cartTotalAmount > 0)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade300),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Outstanding Balance:',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '₦${formatter.format(_cartTotalAmount - (double.tryParse(_amountPaidCtrl.text.trim()) ?? 0.0))}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 16),
                      ],
                    ),

                  // Outstanding Balance Display for Credit
                  if (_selectedPaymentStatus == 'Credit' && _cartTotalAmount > 0)
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.warning_amber, color: Colors.red.shade700, size: 20),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Outstanding Balance:',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '₦${formatter.format(_cartTotalAmount)}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),

                  // Payment Method (hidden for Credit)
                  if (_selectedPaymentStatus != 'Credit')
                    Column(
                      children: [
                        DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            labelText: 'Payment Method *',
                            prefixIcon: const Icon(Icons.payment),
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          initialValue: _selectedMethod,
                          items: _paymentMethods
                              .map((m) => DropdownMenuItem<String>(
                                    value: m,
                                    child: Text(m),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedMethod = v),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),

                  // Note
                  TextField(
                    controller: _noteCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Note (Optional)',
                      prefixIcon: const Icon(Icons.note),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),

                  const SizedBox(height: 24),

                  // Complete Sale Button (only when cart has items)
                  if (_cartItems.isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check_circle, size: 28),
                        label: Text(
                          'Complete Sale (${_cartItems.length} item${_cartItems.length > 1 ? "s" : ""})',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _saveSale,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          elevation: 6,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
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
