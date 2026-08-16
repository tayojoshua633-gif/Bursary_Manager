// lib/screens/sessions/session_term_management_screen.dart

import 'package:flutter/material.dart';
import 'package:bursary_manager/data/database_helper_wrapper.dart';
import 'package:sqflite/sqflite.dart';

class SessionTermManagementScreen extends StatefulWidget {
  const SessionTermManagementScreen({super.key});

  @override
  State<SessionTermManagementScreen> createState() =>
      _SessionTermManagementScreenState();
}

class _SessionTermManagementScreenState
    extends State<SessionTermManagementScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  final TextEditingController _sessionCtrl = TextEditingController();
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;

  final List<String> _terms = ["1st Term", "2nd Term", "3rd Term"];
  
  // Current active values (from database)
  String? _activeTerm;
  int? _activeSessionId;
  
  // Selected values (pending save)
  String? _selectedTerm;
  int? _selectedSessionId;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _sessionCtrl.dispose();
    super.dispose();
  }

  /// Convert old term formats automatically
  String normalizeTerm(String? t) {
    if (t == null || t.trim().isEmpty) return "1st Term";

    switch (t.toLowerCase().trim()) {
      case "first term":
        return "1st Term";
      case "second term":
        return "2nd Term";
      case "third term":
        return "3rd Term";
    }
    return t;
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);

    _sessions = await _db.getSessions();

    final db = await _db.database;

    // Load active term
    final rows = await db.rawQuery(
      "SELECT value FROM settings WHERE key = 'activeTerm' LIMIT 1",
    );

    if (rows.isNotEmpty) {
      String dbTerm = rows.first['value']?.toString() ?? "1st Term";
      String norm = normalizeTerm(dbTerm);

      _activeTerm = norm;
      _selectedTerm = norm; // Initialize selected with current

      // Auto-fix old formats
      if (dbTerm != norm) {
        await db.update(
          'settings',
          {'value': norm},
          where: 'key = ?',
          whereArgs: ['activeTerm'],
        );
      }
    } else {
      _activeTerm = "1st Term";
      _selectedTerm = "1st Term";
      await db.insert('settings', {
        'key': 'activeTerm',
        'value': "1st Term",
      });
    }

    // Find active session
    final activeSession = _sessions.firstWhere(
      (s) => s['isActive'] == 1,
      orElse: () => {},
    );
    
    if (activeSession.isNotEmpty) {
      _activeSessionId = activeSession['id'];
      _selectedSessionId = activeSession['id']; // Initialize selected with current
    }

    setState(() => _loading = false);
  }

  // ----------------------
  // SESSION MANAGEMENT
  // ----------------------

  Future<void> _addSession() async {
    final name = _sessionCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a session name')),
      );
      return;
    }

    final db = await _db.database;

    await db.insert('sessions', {
      'sessionName': name,
      'isActive': 0,
    });

    _sessionCtrl.clear();
    await _loadAll();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Session "$name" added successfully')),
      );
    }
  }

  /// Groups of tables that store records tagged with a session name.
  /// Each entry is a human-readable label mapped to the tables that
  /// belong under it, so usage can be reported to the user in a way
  /// they understand (rather than raw table names).
  static const Map<String, List<String>> _sessionDataGroups = {
    'Student bills': ['student_bills'],
    'Payments received': ['payments'],
    'Expenses recorded': ['expenses'],
    'Fee structure (fee items & class fee assignments)': [
      'fee_items',
      'class_fees',
      'special_fee_items',
      'special_class_fees',
      'excluded_default_fees',
      'fee_priority',
    ],
    'Examination registrations': ['examination_registrations'],
    'Academic results & exams': [
      'exams',
      'grading_definitions',
      'student_scores',
      'student_psychomotor_scores',
      'student_affective_scores',
      'result_computations',
    ],
    'Store sales & debtors': ['sales', 'sales_debtors'],
    'Transport allocations': ['student_transport_allocations'],
    'Staff teaching allocations': [
      'class_teacher_allocations',
      'subject_teacher_allocations',
    ],
  };

  /// Returns the human-readable labels (with record counts) of every
  /// data group that has at least one record tagged with [sessionName].
  Future<Map<String, int>> _getSessionUsage(String sessionName) async {
    final db = await _db.database;
    final Map<String, int> usage = {};

    for (final entry in _sessionDataGroups.entries) {
      int total = 0;
      for (final table in entry.value) {
        final result = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM $table WHERE session = ?',
          [sessionName],
        );
        total += (result.first['c'] as int?) ?? 0;
      }
      if (total > 0) {
        usage[entry.key] = total;
      }
    }

    return usage;
  }

  Future<void> _deleteSession(int id, String sessionName) async {
    // Check if trying to delete active session
    if (id == _activeSessionId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot delete the active session!'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Check if the session has any records tied to it. If it does, block
    // deletion outright — removing the session would orphan those
    // financial/academic records and break reports that look them up by
    // session name.
    final usage = await _getSessionUsage(sessionName);
    if (usage.isNotEmpty) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.block, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Cannot Delete Session'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '"$sessionName" cannot be deleted because it contains the following records:',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ...usage.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.fiber_manual_record, size: 8),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('${e.key} (${e.value})'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Deleting a session that still has records would '
                    'permanently disconnect those bills, payments, results '
                    'and reports from any session, corrupting your '
                    'historical data. Only sessions with no records can be '
                    'deleted.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      }
      return;
    }

    if (!mounted) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.orange),
              SizedBox(width: 8),
              Text('Confirm Delete'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Are you sure you want to delete this session?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Session: $sessionName'),
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
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                        ),
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
        );
      },
    );

    if (confirmed == true) {
      final db = await _db.database;
      await db.delete('sessions', where: 'id = ?', whereArgs: [id]);

      await _loadAll();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Session "$sessionName" deleted')),
        );
      }
    }
  }

  // ----------------------
  // SAVE CHANGES
  // ----------------------
  Future<void> _saveChanges() async {
    if (_selectedSessionId == null || _selectedTerm == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select both session and term'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final db = await _db.database;

      // Update active session
      if (_selectedSessionId != _activeSessionId) {
        // Set all inactive
        await db.update('sessions', {'isActive': 0});

        // Set selected active
        await db.update(
          'sessions',
          {'isActive': 1},
          where: 'id = ?',
          whereArgs: [_selectedSessionId],
        );
      }

      // Update active term
      if (_selectedTerm != _activeTerm) {
        await db.insert(
          'settings',
          {'key': 'activeTerm', 'value': _selectedTerm},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await _loadAll();

      if (mounted) {
        final sessionName = _sessions.firstWhere(
          (s) => s['id'] == _selectedSessionId,
          orElse: () => {'sessionName': 'Unknown'},
        )['sessionName'];

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved: $sessionName - $_selectedTerm',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  // Check if there are unsaved changes
  bool get _hasUnsavedChanges {
    return _selectedSessionId != _activeSessionId || 
           _selectedTerm != _activeTerm;
  }

  // ----------------------
  // UI
  // ----------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Session & Term Management"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ==================
                // CREATE NEW SESSION
                // ==================
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.add_circle, color: Colors.indigo.shade700),
                            const SizedBox(width: 8),
                            const Text(
                              "Create New Session",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _sessionCtrl,
                          decoration: const InputDecoration(
                            labelText: "Session (e.g. 2024/2025)",
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.calendar_today),
                          ),
                          onSubmitted: (_) => _addSession(),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _addSession,
                            icon: const Icon(Icons.add),
                            label: const Text("Add Session"),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.all(16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ==================
                // AVAILABLE SESSIONS
                // ==================
                Row(
                  children: [
                    Icon(Icons.list, color: Colors.indigo.shade700),
                    const SizedBox(width: 8),
                    const Text(
                      "Available Sessions",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (_sessions.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.inbox, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text(
                              'No sessions created yet',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  ..._sessions.map((s) {
                    final int id = s['id'];
                    final String name = s['sessionName'];
                    final bool isActive = _activeSessionId == id;
                    final bool isSelected = _selectedSessionId == id;

                    return Card(
                      elevation: isSelected ? 4 : 1,
                      color: isSelected ? Colors.indigo.shade50 : null,
                      child: ListTile(
                        leading: Radio<int>(
                          value: id,
                          // ignore: deprecated_member_use
                          groupValue: _selectedSessionId,
                          // ignore: deprecated_member_use
                          onChanged: (value) {
                            setState(() => _selectedSessionId = value);
                          },
                        ),
                        title: Text(
                          name,
                          style: TextStyle(
                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Row(
                          children: [
                            if (isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.green.shade700),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle,
                                        size: 14, color: Colors.green.shade700),
                                    const SizedBox(width: 4),
                                    Text(
                                      "Active Session",
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (isSelected && !isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.orange.shade700),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.pending,
                                        size: 14, color: Colors.orange.shade700),
                                    const SizedBox(width: 4),
                                    Text(
                                      "Selected (Not Saved)",
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.orange.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteSession(id, name),
                          tooltip: 'Delete session',
                        ),
                        onTap: () {
                          setState(() => _selectedSessionId = id);
                        },
                      ),
                    );
                  }),

                const SizedBox(height: 24),

                // ==================
                // ACTIVE TERM
                // ==================
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.event, color: Colors.indigo.shade700),
                            const SizedBox(width: 8),
                            const Text(
                              "Active Term",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedTerm,
                          items: _terms
                              .map((t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            setState(() => _selectedTerm = v);
                          },
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.calendar_month),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ==================
                // SAVE BUTTON
                // ==================
                if (_hasUnsavedChanges)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200, width: 2),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning_amber, color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'You have unsaved changes!',
                                style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _saveChanges,
                            icon: const Icon(Icons.save),
                            label: const Text(
                              'Save Changes',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Current active settings display
                const SizedBox(height: 24),
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            const Text(
                              'Current Active Settings',
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
                            const Icon(Icons.calendar_today, size: 18),
                            const SizedBox(width: 8),
                            const Text('Session: '),
                            Text(
                              _activeSessionId != null
                                  ? _sessions.firstWhere(
                                      (s) => s['id'] == _activeSessionId,
                                      orElse: () => {'sessionName': 'None'},
                                    )['sessionName']
                                  : 'None',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.event, size: 18),
                            const SizedBox(width: 8),
                            const Text('Term: '),
                            Text(
                              _activeTerm ?? 'None',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}