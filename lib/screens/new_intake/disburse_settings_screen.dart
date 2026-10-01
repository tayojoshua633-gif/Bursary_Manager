// lib/screens/new_intake/disburse_settings_screen.dart
import 'package:flutter/material.dart';
import '../../data/database_helper_wrapper.dart';
import '../../utils/write_guard.dart';
import '../../widgets/quick_access_sidebar.dart';

class DisburseSettingsScreen extends StatefulWidget {
  const DisburseSettingsScreen({super.key});

  @override
  State<DisburseSettingsScreen> createState() => _DisburseSettingsScreenState();
}

class _DisburseSettingsScreenState extends State<DisburseSettingsScreen> {
  static const List<String> _terms = ['1st Term', '2nd Term', '3rd Term'];

  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _categories = []; // {id, name}
  List<Map<String, dynamic>> _standaloneItems = []; // {id, name}
  Map<int, List<Map<String, dynamic>>> _childrenByCategory = {};

  String? _activeTerm;
  String? _activeSession;
  final Set<int> _selectedItemIds = {};
  Set<int> _selectedClassIds = {};

  bool _loading = true;
  bool _loadingSelection = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WriteGuard.enforce(context);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    _activeTerm = await _db.getActiveTerm();
    _activeSession = (await _db.getActiveSession())?['sessionName'] ?? "";
    _sessions = await _db.getAllSessions();
    _classes = await _db.getClasses();

    await _loadItems();

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadItems() async {
    final categories = await _db.getSpecialFeeItemCategories(term: _activeTerm, session: _activeSession);
    final standalone = await _db.getSpecialFeeItemStandalone(term: _activeTerm, session: _activeSession);

    final childrenMap = <int, List<Map<String, dynamic>>>{};
    for (final cat in categories) {
      final catId = cat['id'] as int;
      childrenMap[catId] = await _db.getSpecialFeeItemChildren(catId, term: _activeTerm, session: _activeSession);
    }

    setState(() {
      _categories = categories;
      _standaloneItems = standalone;
      _childrenByCategory = childrenMap;
      _selectedItemIds.clear();
      _selectedClassIds = {};
    });
  }

  void _onTermChanged(String? term) {
    if (term == null) return;
    setState(() => _activeTerm = term);
    _loadItems();
  }

  void _onSessionChanged(String? session) {
    if (session == null) return;
    setState(() => _activeSession = session);
    _loadItems();
  }

  Future<void> _toggleItem(int itemId) async {
    setState(() {
      if (_selectedItemIds.contains(itemId)) {
        _selectedItemIds.remove(itemId);
      } else {
        _selectedItemIds.add(itemId);
      }
    });
    await _onItemSelectionChanged();
  }

  Future<void> _onItemSelectionChanged() async {
    if (_selectedItemIds.isEmpty) {
      setState(() => _selectedClassIds = {});
      return;
    }
    if (_selectedItemIds.length == 1) {
      await _loadSelectionForItem(_selectedItemIds.first);
    } else {
      // Bulk mode: start from a clean slate rather than guessing at a
      // merged state across items with potentially different settings.
      setState(() => _selectedClassIds = {});
    }
  }

  Future<void> _loadSelectionForItem(int itemId) async {
    setState(() => _loadingSelection = true);

    final database = await _db.database;
    final rows = await database.query(
      'disbursement_settings',
      columns: ['classId'],
      where: 'specialFeeItemId = ?',
      whereArgs: [itemId],
    );

    if (!mounted) return;
    setState(() {
      _selectedClassIds = rows.map((r) => r['classId'] as int).toSet();
      _loadingSelection = false;
    });
  }

  void _toggleClass(int classId) {
    setState(() {
      if (_selectedClassIds.contains(classId)) {
        _selectedClassIds.remove(classId);
      } else {
        _selectedClassIds.add(classId);
      }
    });
  }

  void _selectAllClasses() {
    setState(() => _selectedClassIds = _classes.map((c) => c['id'] as int).toSet());
  }

  void _clearAllClasses() {
    setState(() => _selectedClassIds = {});
  }

  Future<void> _save() async {
    if (_selectedItemIds.isEmpty) return;

    setState(() => _saving = true);
    try {
      final database = await _db.database;
      final now = DateTime.now().toIso8601String();

      await database.transaction((txn) async {
        for (final itemId in _selectedItemIds) {
          await txn.delete(
            'disbursement_settings',
            where: 'specialFeeItemId = ?',
            whereArgs: [itemId],
          );
          for (final classId in _selectedClassIds) {
            await txn.insert('disbursement_settings', {
              'specialFeeItemId': itemId,
              'classId': classId,
              'createdAt': now,
            });
          }
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved: ${_selectedClassIds.length} class(es) for ${_selectedItemIds.length} item(s)',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool get _itemsEmpty => _categories.isEmpty && _standaloneItems.isEmpty;

  @override
  Widget build(BuildContext context) => QuickAccessScaffold(
        group: QuickAccessGroup.itemDisbursement,
        currentId: 'disburse_settings',
        child: _buildScreenContent(context),
      );

  Widget _buildScreenContent(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Disburse Settings'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Term/Session selector
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    border: Border(bottom: BorderSide(color: Colors.deepPurple.shade100)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _activeSession,
                          decoration: InputDecoration(
                            labelText: 'Session',
                            isDense: true,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.calendar_today, size: 18),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          items: _sessions
                              .map((s) => s['sessionName'] as String)
                              .toSet()
                              .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                              .toList(),
                          onChanged: _onSessionChanged,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _activeTerm,
                          decoration: InputDecoration(
                            labelText: 'Term',
                            isDense: true,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.event, size: 18),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          items: _terms
                              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                              .toList(),
                          onChanged: _onTermChanged,
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: _itemsEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                Text(
                                  'No special fee items found for this term/session',
                                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Create items first in New Intake Bills > Special Fee Items',
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Select item(s)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(height: 8),
                              if (_standaloneItems.isNotEmpty)
                                Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  child: Column(
                                    children: _standaloneItems
                                        .map((item) => _itemCheckbox(item))
                                        .toList(),
                                  ),
                                ),
                              ..._categories.map((cat) {
                                final catId = cat['id'] as int;
                                final children = _childrenByCategory[catId] ?? [];
                                final selectedCount =
                                    children.where((c) => _selectedItemIds.contains(c['id'] as int)).length;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  clipBehavior: Clip.antiAlias,
                                  child: ExpansionTile(
                                    title: Text(
                                      cat['name'] as String,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: selectedCount > 0
                                        ? Text(
                                            '$selectedCount of ${children.length} selected',
                                            style: TextStyle(color: Colors.deepPurple.shade700, fontSize: 12),
                                          )
                                        : null,
                                    children: children.map((item) => _itemCheckbox(item)).toList(),
                                  ),
                                );
                              }),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Classes to track for disbursement',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _loadingSelection || _selectedItemIds.isEmpty
                                        ? null
                                        : _selectAllClasses,
                                    child: const Text('Select All'),
                                  ),
                                  TextButton(
                                    onPressed: _loadingSelection || _selectedItemIds.isEmpty
                                        ? null
                                        : _clearAllClasses,
                                    child: const Text('Clear All'),
                                  ),
                                ],
                              ),
                              if (_selectedItemIds.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Text(
                                    'Select at least one item above to choose classes',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                  ),
                                )
                              else ...[
                                if (_selectedItemIds.length > 1)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                                    child: Text(
                                      'Bulk mode: saving will apply this class selection to all '
                                      '${_selectedItemIds.length} selected items, replacing their current settings.',
                                      style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                _loadingSelection
                                    ? const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(24),
                                          child: CircularProgressIndicator(),
                                        ),
                                      )
                                    : Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: _classes.map((c) {
                                          final id = c['id'] as int;
                                          final selected = _selectedClassIds.contains(id);
                                          return FilterChip(
                                            label: Text(c['name'] as String),
                                            selected: selected,
                                            selectedColor: Colors.deepPurple.shade100,
                                            checkmarkColor: Colors.deepPurple.shade700,
                                            onSelected: (_) => _toggleClass(id),
                                          );
                                        }).toList(),
                                      ),
                                const SizedBox(height: 24),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _saving || _loadingSelection ? null : _save,
                                    icon: _saving
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Icon(Icons.save),
                                    label: const Text('Save'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.deepPurple,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _itemCheckbox(Map<String, dynamic> item) {
    final id = item['id'] as int;
    return CheckboxListTile(
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(item['name'] as String? ?? 'Unknown'),
      value: _selectedItemIds.contains(id),
      activeColor: Colors.deepPurple,
      onChanged: (_) => _toggleItem(id),
    );
  }
}
