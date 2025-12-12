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
  // ADD NEW ITEM - FIXED: Include term and session
  // ----------------------------------------------------------
  Future<void> _addItem() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    // FIXED: Include term and session when creating fee item
    await _db.insertFeeItem({
      'name': name,
      'defaultAmount': 0.0,
      'description': '',
      'term': _term,        // ← Added
      'session': _session,  // ← Added
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
                  'term': item['term'],        // Preserve term
                  'session': item['session'],  // Preserve session
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
  Future<void> _deleteItem(int id, String itemName) async {
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text("Delete Fee Item"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Are you sure you want to delete this fee item?",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text("Item: $itemName"),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone!',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _db.deleteFeeItem(id);

    if (!mounted) return;
    
    await _load();

    messenger.showSnackBar(
      SnackBar(content: Text('Fee item "$itemName" deleted')),
    );
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
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.assignment),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const FeeClassAssignmentScreen(),
                ),
              );
              
              if (result == true && mounted) {
                _load();
              }
            },
            tooltip: 'Assign Fees to Class',
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.indigo,
        child: const Icon(Icons.add),
        onPressed: () {
          _nameCtrl.clear();
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text("New Fee Item"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: "Fee Item Name",
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                    onSubmitted: (_) async {
                      final navigator = Navigator.of(context);
                      if (_nameCtrl.text.trim().isNotEmpty) {
                        await _addItem();
                      }
                      if (mounted) navigator.pop();
                    },
                  ),
                  const SizedBox(height: 12),
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
                        Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 16, color: Colors.blue.shade700),
                            const SizedBox(width: 6),
                            Text(
                              'Will be created for:',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade900,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Term: $_term',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade800,
                          ),
                        ),
                        Text(
                          'Session: $_session',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    
                    if (_nameCtrl.text.trim().isNotEmpty) {
                      await _addItem();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Fee item "${_nameCtrl.text.trim()}" added'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                    
                    if (mounted) navigator.pop();
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
                  // Active Term/Session Info Card
                  Card(
                    color: Colors.indigo.shade50,
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline,
                                  color: Colors.indigo.shade700),
                              const SizedBox(width: 8),
                              const Text(
                                'Active Period',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.event, size: 18, color: Colors.indigo.shade700),
                              const SizedBox(width: 8),
                              const Text('Term: '),
                              Text(
                                _term ?? 'Not set',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.calendar_today, size: 18, color: Colors.indigo.shade700),
                              const SizedBox(width: 8),
                              const Text('Session: '),
                              Text(
                                _session ?? 'Not set',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),

                  // Fee Items Header
                  Row(
                    children: [
                      Icon(Icons.receipt_long, color: Colors.indigo.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Fee Items (${_items.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  
                  const Divider(),

                  // Empty State
                  if (_items.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(48),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.inbox,
                                  size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text(
                                'No fee items created yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tap the + button to add fee items',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Fee Items List
                  ..._items.map((i) {
                    final name = i['name'] ?? '';
                    final amount = (i['defaultAmount'] ?? 0).toStringAsFixed(2);
                    final term = i['term'] ?? '';
                    final session = i['session'] ?? '';

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.indigo.shade100,
                          child: Icon(Icons.attach_money,
                              color: Colors.indigo.shade700),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Default: ₦$amount',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '$term | $session',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () => _editItem(i),
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              tooltip: 'Edit',
                            ),
                            IconButton(
                              onPressed: () => _deleteItem(i['id'], name),
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Delete',
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