// lib/screens/settings/sms_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;
import '../../data/database_helper_wrapper.dart';
import '../../utils/sms_service.dart';

class SmsSettingsScreen extends StatefulWidget {
  const SmsSettingsScreen({super.key});

  @override
  State<SmsSettingsScreen> createState() => _SmsSettingsScreenState();
}

class _SmsSettingsScreenState extends State<SmsSettingsScreen> {
  final DatabaseHelperWrapper _db = DatabaseHelperWrapper();
  final _formKey = GlobalKey<FormState>();

  final _apiKeyCtrl = TextEditingController();
  final _senderIdCtrl = TextEditingController();
  final _testPhoneCtrl = TextEditingController();

  String _provider = SmsService.providerTermii;
  bool _enabled = false;
  bool _obscureApiKey = true;
  bool _loading = true;
  bool _saving = false;
  bool _sendingTest = false;
  bool _smsPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _provider = await _db.getSetting(SmsService.keyProvider) ?? SmsService.providerTermii;
    _enabled = (await _db.getSetting(SmsService.keyEnabled)) == 'true';
    _apiKeyCtrl.text = await _db.getSetting(SmsService.keyApiKey) ?? '';
    _senderIdCtrl.text = await _db.getSetting(SmsService.keySenderId) ?? '';
    // Only touch the SMS permission if the user has already opted into
    // device-SIM mode — other providers should never be prompted for it.
    if (_provider == SmsService.providerDeviceSim) {
      _smsPermissionGranted = await requestDeviceSimSmsPermission();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _requestSmsPermission() async {
    final granted = await requestDeviceSimSmsPermission();
    if (mounted) setState(() => _smsPermissionGranted = granted);
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('SMS permission was not granted. You may need to enable it manually in app settings.'),
          action: SnackBarAction(label: 'Open Settings', onPressed: openAppSettings),
        ),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_provider == SmsService.providerDeviceSim && !_smsPermissionGranted) {
      await _requestSmsPermission();
      if (!_smsPermissionGranted) return;
    }

    setState(() => _saving = true);
    await _db.setSetting(SmsService.keyProvider, _provider);
    await _db.setSetting(SmsService.keyEnabled, _enabled.toString());
    await _db.setSetting(SmsService.keyApiKey, _apiKeyCtrl.text.trim());
    await _db.setSetting(SmsService.keySenderId, _senderIdCtrl.text.trim());
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SMS settings saved')),
      );
    }
  }

  Future<void> _sendTestSms() async {
    final phone = _testPhoneCtrl.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a phone number to test')),
      );
      return;
    }

    // Test uses whatever is currently on screen, even if not saved yet.
    setState(() => _sendingTest = true);
    await _db.setSetting(SmsService.keyProvider, _provider);
    await _db.setSetting(SmsService.keyEnabled, 'true');
    await _db.setSetting(SmsService.keyApiKey, _apiKeyCtrl.text.trim());
    await _db.setSetting(SmsService.keySenderId, _senderIdCtrl.text.trim());

    final result = await SmsService.send(
      rawPhone: phone,
      message: 'This is a test SMS from Bursary Manager.',
      context: 'test',
    );

    // Restore the enabled toggle to whatever the user had selected on screen.
    await _db.setSetting(SmsService.keyEnabled, _enabled.toString());

    if (mounted) {
      setState(() => _sendingTest = false);
      final label = result.success
          ? (result.requiresManualConfirmation
              ? 'Messaging app opened — tap Send there to deliver it'
              : 'Test SMS sent successfully')
          : (result.errorMessage ?? 'Failed to send test SMS');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(label),
          backgroundColor: result.success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _senderIdCtrl.dispose();
    _testPhoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('SMS Settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isDeviceSim = _provider == SmsService.providerDeviceSim;
    final isMessagingApp = _provider == SmsService.providerDeviceMessagingApp;
    final isCloudGateway = !isDeviceSim && !isMessagingApp;

    return Scaffold(
      appBar: AppBar(title: const Text('SMS Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable SMS notifications'),
                subtitle: const Text('Allow sending payment/bill SMS to parents'),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              const SizedBox(height: 12),
              const Text('SMS Provider', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: const Text('Cloud Gateway (Termii)'),
                subtitle: const Text('Sends via the internet using a Termii API key. Costs per SMS.'),
                value: SmsService.providerTermii,
                groupValue: _provider,
                onChanged: (v) => setState(() => _provider = v!),
              ),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: const Text('Device Messaging App'),
                subtitle: const Text(
                  'Opens the phone\'s own Messages app with the text pre-filled; you tap Send there. '
                  'No special permission needed, free, works on any sideloaded install.',
                ),
                value: SmsService.providerDeviceMessagingApp,
                groupValue: _provider,
                onChanged: (v) => setState(() => _provider = v!),
              ),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: const Text('Device SIM (silent)'),
                subtitle: const Text(
                  'Sends automatically using this device\'s own SIM card — no tap needed. '
                  'Requires the SEND_SMS permission, which some devices restrict for sideloaded apps.',
                ),
                value: SmsService.providerDeviceSim,
                groupValue: _provider,
                onChanged: (v) => setState(() => _provider = v!),
              ),
              const SizedBox(height: 16),

              if (isCloudGateway) ...[
                TextFormField(
                  controller: _apiKeyCtrl,
                  obscureText: _obscureApiKey,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureApiKey ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                    ),
                  ),
                  validator: (v) => (_enabled && isCloudGateway && (v == null || v.isEmpty)) ? 'Required when SMS is enabled' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _senderIdCtrl,
                  decoration: InputDecoration(
                    labelText: 'Sender ID',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ] else if (isDeviceSim)
                Card(
                  color: _smsPermissionGranted ? Colors.green.shade50 : Colors.orange.shade50,
                  child: ListTile(
                    leading: Icon(
                      _smsPermissionGranted ? Icons.check_circle : Icons.warning_amber,
                      color: _smsPermissionGranted ? Colors.green : Colors.orange,
                    ),
                    title: Text(_smsPermissionGranted ? 'SMS permission granted' : 'SMS permission required'),
                    subtitle: _smsPermissionGranted
                        ? null
                        : const Text('This device needs permission to send SMS via its own SIM'),
                    trailing: _smsPermissionGranted
                        ? null
                        : TextButton(
                            onPressed: _requestSmsPermission,
                            child: const Text('Grant'),
                          ),
                  ),
                )
              else
                Card(
                  color: Colors.blue.shade50,
                  child: const ListTile(
                    leading: Icon(Icons.info_outline, color: Colors.blue),
                    title: Text('One tap still required'),
                    subtitle: Text('Each SMS opens the Messages app pre-filled — the user sending it must tap Send to deliver it.'),
                  ),
                ),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save Settings'),
                ),
              ),
              const Divider(height: 40),
              const Text('Send Test SMS', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _testPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  hintText: '080XXXXXXXX',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _sendingTest ? null : _sendTestSms,
                  child: _sendingTest
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Send Test SMS'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
