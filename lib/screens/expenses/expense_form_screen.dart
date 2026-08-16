import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database_helper_wrapper.dart';

class ExpenseFormScreen extends StatefulWidget {
  final Map<String, dynamic> currentUser;
  final Map<String, dynamic>? expense;
  /// Pre-fills the Amount, Category and Description fields for a new expense
  /// (ignored when [expense] is set, since that puts the form in edit mode).
  /// Used e.g. when posting a month's total paid salary from the Salary
  /// Payment Record screen.
  final double? initialAmount;
  final String? initialCategory;
  final String? initialDescription;

  const ExpenseFormScreen({
    super.key,
    required this.currentUser,
    this.expense,
    this.initialAmount,
    this.initialCategory,
    this.initialDescription,
  });

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final _formKey = GlobalKey<FormState>();

  // Controllers
  late TextEditingController _amountCtrl;
  late TextEditingController _descriptionCtrl;
  late TextEditingController _recipientCtrl;

  // Form state
  String? _selectedCategory;
  String? _selectedPaymentMethod;
  DateTime _selectedDate = DateTime.now();

  // Categories loaded from DB
  List<String> _categories = [];
  bool _loadingCategories = true;
  Key _categoryDropdownKey = UniqueKey();

  // Context
  String? _activeTerm;
  String? _activeSession;

  static const _addNewOption = '+ Add New Category';

  final List<String> _paymentMethods = ['Cash', 'Transfer', 'POS'];

  @override
  void initState() {
    super.initState();

    final expense = widget.expense;
    _amountCtrl = TextEditingController(
      text: expense != null
          ? (expense['amount'] as num).toString()
          : (widget.initialAmount != null ? widget.initialAmount!.toStringAsFixed(2) : ''),
    );
    _descriptionCtrl = TextEditingController(
      text: expense != null
          ? (expense['description']?.toString() ?? '')
          : (widget.initialDescription ?? ''),
    );
    _recipientCtrl = TextEditingController(
      text: expense?['recipient']?.toString() ?? '',
    );

    if (expense != null) {
      _selectedPaymentMethod = expense['paymentMethod']?.toString();
      final dateStr = expense['expenseDate']?.toString();
      if (dateStr != null) {
        try {
          _selectedDate = DateTime.parse(dateStr);
        } catch (_) {}
      }
    }

    _loadData(
      initialCategory: expense != null
          ? expense['category']?.toString()
          : widget.initialCategory,
    );
  }

  Future<void> _loadData({String? initialCategory}) async {
    _activeTerm = await _db.getActiveTerm();
    final sessionData = await _db.getActiveSession();
    _activeSession = sessionData?['sessionName'];

    final cats = await _db.getAllExpenseCategories();
    final names = cats.map((c) => c['name'] as String).toList();

    if (mounted) {
      setState(() {
        _categories = names;
        _loadingCategories = false;
        if (initialCategory != null && names.contains(initialCategory)) {
          _selectedCategory = initialCategory;
        }
        _categoryDropdownKey = UniqueKey();
      });
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descriptionCtrl.dispose();
    _recipientCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  /// Prompt user to type a new category name, save it, and select it.
  Future<void> _addNewCategoryInline() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add New Category'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Category Name',
              prefixIcon: Icon(Icons.label_outline),
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Enter a category name';
              if (v.trim().length < 2) return 'Name too short';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.brown),
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      // User cancelled — reset dropdown to no selection
      setState(() => _selectedCategory = null);
      return;
    }

    final name = controller.text.trim();
    try {
      await _db.insertExpenseCategory(name);
      final cats = await _db.getAllExpenseCategories();
      final names = cats.map((c) => c['name'] as String).toList();
      if (mounted) {
        setState(() {
          _categories = names;
          _selectedCategory = name;
          _categoryDropdownKey = UniqueKey();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$name" added and selected')),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('UNIQUE')
            ? 'That category already exists'
            : 'Error adding category: $e';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        setState(() => _selectedCategory = null);
      }
    }
  }

  Future<void> _saveExpense() async {
    if (!_formKey.currentState!.validate()) return;

    final expense = {
      'amount': double.parse(_amountCtrl.text.trim()),
      'category': _selectedCategory!,
      'customCategory': null,
      'description': _descriptionCtrl.text.trim(),
      'expenseDate': _selectedDate.toIso8601String(),
      'paymentMethod': _selectedPaymentMethod!,
      'recipient': _recipientCtrl.text.trim(),
      'term': _activeTerm,
      'session': _activeSession,
      'createdAt': DateTime.now().toIso8601String(),
      'createdBy': widget.currentUser['username'],
    };

    try {
      if (widget.expense == null) {
        await _db.insertExpense(expense);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Expense added successfully')),
          );
        }
      } else {
        await _db.updateExpense(widget.expense!['id'] as int, expense);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Expense updated successfully')),
          );
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving expense: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.expense != null;
    final dropdownItems = [
      ..._categories,
      _addNewOption,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Expense' : 'Add Expense'),
        backgroundColor: Colors.brown,
        foregroundColor: Colors.white,
      ),
      body: _loadingCategories
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Amount
                  TextFormField(
                    controller: _amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixText: 'N ',
                      prefixIcon: Icon(Icons.money),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final amount = double.tryParse(v ?? '');
                      if (amount == null || amount <= 0) {
                        return 'Enter valid amount';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // Category
                  DropdownButtonFormField<String>(
                    key: _categoryDropdownKey,
                    initialValue: _selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category),
                      border: OutlineInputBorder(),
                    ),
                    items: dropdownItems.map((cat) {
                      final isAction = cat == _addNewOption;
                      return DropdownMenuItem(
                        value: cat,
                        child: Text(
                          cat,
                          style: isAction
                              ? const TextStyle(
                                  color: Colors.brown,
                                  fontWeight: FontWeight.w600,
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v == _addNewOption) {
                        _addNewCategoryInline();
                      } else {
                        setState(() => _selectedCategory = v);
                      }
                    },
                    validator: (v) =>
                        (v == null || v == _addNewOption)
                            ? 'Select a category'
                            : null,
                  ),

                  const SizedBox(height: 16),

                  // Description
                  TextFormField(
                    controller: _descriptionCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      prefixIcon: Icon(Icons.description),
                      border: OutlineInputBorder(),
                      hintText: 'Enter expense details...',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().length < 3) {
                        return 'Enter description (min 3 characters)';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // Date Picker
                  TextFormField(
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Expense Date',
                      prefixIcon: const Icon(Icons.calendar_today),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.edit_calendar),
                        onPressed: _pickDate,
                      ),
                    ),
                    controller: TextEditingController(
                      text: DateFormat('EEEE, MMM dd, yyyy').format(_selectedDate),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Payment Method
                  DropdownButtonFormField<String>(
                    initialValue: _selectedPaymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'Payment Method',
                      prefixIcon: Icon(Icons.payment),
                      border: OutlineInputBorder(),
                    ),
                    items: _paymentMethods
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedPaymentMethod = v),
                    validator: (v) => v == null ? 'Select payment method' : null,
                  ),

                  const SizedBox(height: 16),

                  // Recipient/Vendor
                  TextFormField(
                    controller: _recipientCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Recipient/Vendor',
                      prefixIcon: Icon(Icons.store),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Enter recipient name';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 24),

                  // Save Button
                  ElevatedButton.icon(
                    onPressed: _saveExpense,
                    icon: const Icon(Icons.save),
                    label: Text(isEdit ? 'Update Expense' : 'Add Expense'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.brown,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
