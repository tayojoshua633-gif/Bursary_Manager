import 'package:flutter/material.dart';
import '../../data/database_helper_wrapper.dart';

class ExpenseCategoryScreen extends StatefulWidget {
  const ExpenseCategoryScreen({super.key});

  @override
  State<ExpenseCategoryScreen> createState() => _ExpenseCategoryScreenState();
}

class _ExpenseCategoryScreenState extends State<ExpenseCategoryScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _loading = true);
    try {
      final cats = await _db.getAllExpenseCategories();
      setState(() => _categories = cats);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading categories: $e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _showCategoryDialog({Map<String, dynamic>? category}) async {
    final isEdit = category != null;
    final controller = TextEditingController(text: category?['name'] ?? '');
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Category' : 'New Category'),
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
            child: Text(isEdit ? 'Update' : 'Add'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final name = controller.text.trim();

    try {
      if (isEdit) {
        await _db.updateExpenseCategory(category['id'] as int, name);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Category updated')),
          );
        }
      } else {
        await _db.insertExpenseCategory(name);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Category added')),
          );
        }
      }
      _loadCategories();
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('UNIQUE')
            ? 'A category with that name already exists'
            : 'Error saving category: $e';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  Future<void> _deleteCategory(Map<String, dynamic> category) async {
    final isPreset = (category['isPreset'] as int?) == 1;
    if (isPreset) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preset categories cannot be deleted')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text('Delete "${category['name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _db.deleteExpenseCategory(category['id'] as int);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Category deleted')),
        );
      }
      _loadCategories();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting category: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Categories'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadCategories,
              child: _categories.isEmpty
                  ? const Center(child: Text('No categories found'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _categories.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final cat = _categories[index];
                        final isPreset = (cat['isPreset'] as int?) == 1;
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isPreset
                                  ? Colors.purple.shade100
                                  : Colors.brown.shade100,
                              child: Icon(
                                Icons.label,
                                color: isPreset
                                    ? Colors.purple.shade700
                                    : Colors.brown.shade700,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              cat['name'] as String,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              isPreset ? 'Preset' : 'Custom',
                              style: TextStyle(
                                fontSize: 12,
                                color: isPreset
                                    ? Colors.purple.shade400
                                    : Colors.brown.shade400,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  tooltip: 'Edit',
                                  onPressed: () =>
                                      _showCategoryDialog(category: cat),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete,
                                    color: isPreset
                                        ? Colors.grey.shade400
                                        : Colors.red,
                                  ),
                                  tooltip: isPreset
                                      ? 'Preset categories cannot be deleted'
                                      : 'Delete',
                                  onPressed: () => _deleteCategory(cat),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCategoryDialog(),
        backgroundColor: Colors.purple,
        icon: const Icon(Icons.add),
        label: const Text('Add Category'),
      ),
    );
  }
}
