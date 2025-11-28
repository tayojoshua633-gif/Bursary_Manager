// lib/screens/sessions/session_term_management_screen.dart

import 'package:flutter/material.dart';
import 'package:bursary_manager/db/database_helper.dart';
import 'package:sqflite/sqflite.dart';

class SessionTermManagementScreen extends StatefulWidget {
  const SessionTermManagementScreen({super.key});

  @override
  State<SessionTermManagementScreen> createState() =>
      _SessionTermManagementScreenState();
}

class _SessionTermManagementScreenState
    extends State<SessionTermManagementScreen> {
  final DatabaseHelper _db = DatabaseHelper();

  final TextEditingController _sessionCtrl = TextEditingController();
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;

  final List<String> _terms = ["1st Term", "2nd Term", "3rd Term"];
  String? _activeTerm;

  @override
  void initState() {
    super.initState();
    _loadAll();
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
      await db.insert('settings', {
        'key': 'activeTerm',
        'value': "1st Term",
      });
    }

    setState(() => _loading = false);
  }

  // ----------------------
  // SESSION MANAGEMENT
  // ----------------------

  Future<void> _addSession() async {
    final name = _sessionCtrl.text.trim();
    if (name.isEmpty) return;

    final db = await _db.database;

    await db.insert('sessions', {
      'sessionName': name,
      'isActive': 0,
    });

    _sessionCtrl.clear();
    await _loadAll();
  }

  Future<void> _activateSession(int id) async {
    final db = await _db.database;

    // Set all inactive
    await db.update('sessions', {'isActive': 0});

    // Set selected active
    await db.update(
      'sessions',
      {'isActive': 1},
      where: 'id = ?',
      whereArgs: [id],
    );

    await _loadAll();
  }

  Future<void> _deleteSession(int id) async {
    final db = await _db.database;
    await db.delete('sessions', where: 'id = ?', whereArgs: [id]);

    await _loadAll();
  }

  // ----------------------
  // TERM MANAGEMENT
  // ----------------------
  Future<void> _setActiveTerm(String newTerm) async {
    final db = await _db.database;

    await db.insert(
      'settings',
      {'key': 'activeTerm', 'value': newTerm},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    setState(() => _activeTerm = newTerm);
  }

  // ----------------------
  // UI
  // ----------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Session & Term Management")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  "Create New Session",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextField(
                  controller: _sessionCtrl,
                  decoration: const InputDecoration(
                    labelText: "Session (e.g. 2024/2025)",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _addSession,
                  child: const Text("Add Session"),
                ),

                const Divider(height: 40),

                const Text(
                  "Available Sessions",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),

                ..._sessions.map((s) {
                  final bool active = s['isActive'] == 1;
                  return Card(
                    child: ListTile(
                      title: Text(s['sessionName']),
                      subtitle: Text(
                        active ? "Active Session" : "Inactive",
                        style: TextStyle(
                            color: active ? Colors.green : Colors.black54),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!active)
                            IconButton(
                              icon: const Icon(Icons.check_circle,
                                  color: Colors.green),
                              onPressed: () => _activateSession(s['id']),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteSession(s['id']),
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                const Divider(height: 40),

                const Text(
                  "Active Term",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _activeTerm,
                  items: _terms
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(t),
                          ))
                      .toList(),
                  onChanged: (v) => _setActiveTerm(v!),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
    );
  }
}
