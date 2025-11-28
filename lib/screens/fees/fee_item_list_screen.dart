import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import 'fee_class_assignment_screen.dart';

class FeeItemListScreen extends StatefulWidget {
  const FeeItemListScreen({super.key});

  @override
  State<FeeItemListScreen> createState() => _FeeItemListScreenState();
}

class _FeeItemListScreenState extends State<FeeItemListScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  final TextEditingController _nameCtrl = TextEditingController();

  List<Map<String, dynamic>> _items = [];
  String? _term;
  String? _session;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final activeTerm = await _db.getActiveTerm();
    final activeSession =
        (await _db.getActiveSession())?['sessionName'] ?? "";

    _term = activeTerm;
    _session = activeSession;

    _items = await _db.getFeeItems(
      term: activeTerm,
      session: activeSession,
    );

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  // ----------------------------------------------------------
  // ADD NEW ITEM
  // ----------------------------------------------------------
  Future<void> _addItem() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    await _db.insertFeeItem({
      'name': name,
      'defaultAmount': 0.0,
      'description': '',
    });

    _nameCtrl.clear();

    if (!mounted) return;
    await _load();
  }

  // ----------------------------------------------------------
  // EDIT ITEM
  // ----------------------------------------------------------
  Future<void> _editItem(Map<String, dynamic> item) async {
    _nameCtrl.text = item['name'] ?? "";

    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Edit Fee Item"),
        content: TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(labelText: "Fee Item Name"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = _nameCtrl.text.trim();
              if (newName.isEmpty) return;

              await _db.updateFeeItem(
                item['id'],
                {
                  'name': newName,
                  'defaultAmount': item['defaultAmount'],
                  'description': item['description'],
                },
              );

              if (mounted) Navigator.pop(context, true);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );

    if (updated == true) {
      if (!mounted) return;
      await _load();
    }
  }

  // ----------------------------------------------------------
  // DELETE ITEM
  // ----------------------------------------------------------
  Future<void> _deleteItem(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Fee Item"),
        content: const Text("Are you sure you want to delete this item?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _db.deleteFeeItem(id);

      if (!mounted) return;
      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Fee item deleted")),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------
  // UI
  // ----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Fee Items"),
        actions: [
          IconButton(
            icon: const Icon(Icons.assignment),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const FeeClassAssignmentScreen(),
                ),
              );
            },
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          _nameCtrl.clear();
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text("New Fee Item"),
              content: TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: "Fee Item Name"),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (_nameCtrl.text.trim().isNotEmpty) {
                      await _addItem();
                    }
                    if (mounted) Navigator.pop(context);
                  },
                  child: const Text("Add"),
                ),
              ],
            ),
          );
        },
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    "Active Term: $_term\nActive Session: $_session",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Divider(),

                  ..._items.map((i) {
                    return Card(
                      child: ListTile(
                        title: Text(i['name'] ?? ''),
                        subtitle: Text(
                          "Term: ${i['term']} | Session: ${i['session']}",
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () => _editItem(i),
                              icon: const Icon(Icons.edit, color: Colors.blue),
                            ),
                            IconButton(
                              onPressed: () => _deleteItem(i['id']),
                              icon: const Icon(Icons.delete, color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
