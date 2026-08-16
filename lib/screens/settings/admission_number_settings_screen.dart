// lib/screens/settings/admission_number_settings_screen.dart
import 'package:flutter/material.dart';
import '../../utils/admission_settings_helper.dart';
import '../../utils/display_settings_helper.dart';

class AdmissionNumberSettingsScreen extends StatefulWidget {
  const AdmissionNumberSettingsScreen({super.key});

  @override
  State<AdmissionNumberSettingsScreen> createState() => _AdmissionNumberSettingsScreenState();
}

class _AdmissionNumberSettingsScreenState extends State<AdmissionNumberSettingsScreen> {
  bool _loading = true;
  bool _editable = false;
  bool _restartPerSession = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final editable = await AdmissionSettingsHelper.isEditable();
    final restart = await AdmissionSettingsHelper.isRestartSerialPerSession();
    if (mounted) {
      setState(() {
        _editable = editable;
        _restartPerSession = restart;
        _loading = false;
      });
    }
  }

  Future<void> _setEditable(bool value) async {
    setState(() => _editable = value);
    await AdmissionSettingsHelper.setEditable(value);
  }

  Future<void> _setRestartPerSession(bool value) async {
    setState(() => _restartPerSession = value);
    await AdmissionSettingsHelper.setRestartSerialPerSession(value);
  }

  @override
  Widget build(BuildContext context) {
    final ds = DisplaySettingsProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admission Number Settings'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(ds.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: EdgeInsets.all(ds.cardPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.edit_note, color: Colors.indigo),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Editable Admission Number',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Switch(
                                value: _editable,
                                onChanged: _setEditable,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _editable
                                ? 'Staff can manually type or change the admission number for new and existing students.'
                                : 'Admission number is auto-generated and locked, on both the registration and edit screens.',
                            style: TextStyle(
                              color: _editable ? Colors.green : Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: ds.cardPadding),
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: EdgeInsets.all(ds.cardPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.restart_alt, color: Colors.indigo),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Restart Serial Per Session',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Switch(
                                value: _restartPerSession,
                                onChanged: _setRestartPerSession,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _restartPerSession
                                ? 'When the session year in the admission number changes, the serial restarts at 0001 (e.g. DAWOT/2026/0001).'
                                : 'The serial number keeps counting up across every session and never restarts.',
                            style: TextStyle(
                              color: _restartPerSession ? Colors.green : Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: ds.cardPadding),
                  Container(
                    padding: EdgeInsets.all(ds.cardPadding * 0.75),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'These settings apply to this device only. Changes take effect on the next admission number generated.',
                            style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
