// lib/utils/sms_service.dart
// SMS notification gateway (Termii cloud API or device SIM) + message
// templates for payment/bill SMS. Gateways are behind an interface so the
// active provider can be swapped without touching call sites.

import 'dart:async';
import 'dart:convert';
import 'package:another_telephony/telephony.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/database_helper_wrapper.dart';

/// Requests the SMS permissions declared in AndroidManifest.xml (just
/// SEND_SMS) via `another_telephony`. No-ops with no dialog if already
/// granted. The plugin throws a [PlatformException] rather than returning
/// false when the user denies the request, so that's normalized here into
/// a plain `false`.
Future<bool> requestDeviceSimSmsPermission() async {
  try {
    return await Telephony.instance.requestSmsPermissions ?? false;
  } on PlatformException {
    return false;
  }
}

class SmsSendResult {
  final bool success;
  final String? errorMessage;
  /// True when the gateway only handed the message off to another app
  /// (e.g. the device's Messages app) and the user still has to tap Send
  /// there themselves — the caller should word success messages accordingly.
  final bool requiresManualConfirmation;

  const SmsSendResult.success({this.requiresManualConfirmation = false})
      : success = true,
        errorMessage = null;
  const SmsSendResult.failure(this.errorMessage)
      : success = false,
        requiresManualConfirmation = false;
}

abstract class SmsGateway {
  Future<SmsSendResult> send({required String phone, required String message});
}

class TermiiSmsGateway implements SmsGateway {
  static const _endpoint = 'https://api.ng.termii.com/api/sms/send';

  final String apiKey;
  final String senderId;

  TermiiSmsGateway({required this.apiKey, required this.senderId});

  @override
  Future<SmsSendResult> send({required String phone, required String message}) async {
    try {
      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'to': phone,
          'from': senderId,
          'sms': message,
          'type': 'plain',
          'channel': 'generic',
          'api_key': apiKey,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        // Termii returns a message_id on success; anything else is treated as failure.
        if (body['message_id'] != null || body['code'] == 'ok') {
          return const SmsSendResult.success();
        }
        return SmsSendResult.failure(body['message']?.toString() ?? 'SMS provider rejected the message');
      }

      return SmsSendResult.failure('SMS provider returned status ${response.statusCode}');
    } catch (e) {
      return SmsSendResult.failure('Failed to reach SMS provider: $e');
    }
  }
}

/// Sends SMS through the device's own SIM card via [Telephony.sendSms].
/// Free (normal carrier SMS cost, no API fees) and works with no internet,
/// but Android-only and depends on the device having an active, funded SIM.
class DeviceSimSmsGateway implements SmsGateway {
  @override
  Future<SmsSendResult> send({required String phone, required String message}) async {
    final granted = await requestDeviceSimSmsPermission();
    if (!granted) {
      return const SmsSendResult.failure(
        'SMS permission was not granted. Enable it in device Settings > Apps > Bursary Manager > Permissions.',
      );
    }

    final completer = Completer<SmsSendResult>();
    try {
      await Telephony.instance.sendSms(
        to: phone,
        message: message,
        statusListener: (SendStatus sendStatus) {
          if (completer.isCompleted) return;
          if (sendStatus == SendStatus.SENT || sendStatus == SendStatus.DELIVERED) {
            completer.complete(const SmsSendResult.success());
          } else {
            completer.complete(const SmsSendResult.failure('Device SIM failed to send the SMS.'));
          }
        },
      );
    } catch (e) {
      return SmsSendResult.failure('Failed to send SMS via device SIM: $e');
    }

    // Some OEMs never fire the delivery-status broadcast; since sendSms()
    // above didn't throw, the OS accepted the message, so treat a timeout
    // as a (best-effort) success rather than leaving the caller hanging.
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => const SmsSendResult.success(),
    );
  }
}

/// Opens the device's default Messages app with the recipient and message
/// pre-filled, via an `sms:` intent — the user still has to tap Send
/// themselves. Needs no special permission at all (no SEND_SMS request, so
/// none of the Play Protect "restricted permission" friction that blocks
/// SEND_SMS on sideloaded installs), but isn't silent/automatic.
class DeviceMessagingAppGateway implements SmsGateway {
  @override
  Future<SmsSendResult> send({required String phone, required String message}) async {
    final uri = Uri(scheme: 'sms', path: phone, queryParameters: {'body': message});
    try {
      final opened = await launchUrl(uri);
      if (opened) {
        return const SmsSendResult.success(requiresManualConfirmation: true);
      }
      return const SmsSendResult.failure('Could not open the messaging app.');
    } catch (e) {
      return SmsSendResult.failure('Failed to open messaging app: $e');
    }
  }
}

/// Loads settings, checks connectivity, sends via the configured gateway,
/// and writes an audit row to sms_log — the single entry point every
/// screen should call instead of talking to [SmsGateway] directly.
class SmsService {
  static final DatabaseHelperWrapper _db = DatabaseHelperWrapper();

  static const keyEnabled = 'sms_enabled';
  static const keyProvider = 'sms_provider';
  static const keyApiKey = 'sms_api_key';
  static const keySenderId = 'sms_sender_id';

  /// Converts common Nigerian phone formats (0803..., 803..., +234803...,
  /// 234803...) into the +234 E.164 form Termii expects. Returns null if the
  /// input doesn't look like a valid Nigerian mobile number.
  static String? normalizeNigerianPhone(String? raw) {
    if (raw == null) return null;
    var digits = raw.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return null;

    if (digits.startsWith('+234')) {
      digits = digits.substring(1);
    } else if (digits.startsWith('234')) {
      // already country-coded, leave as-is
    } else if (digits.startsWith('0')) {
      digits = '234${digits.substring(1)}';
    } else {
      digits = '234$digits';
    }

    // Nigerian mobile numbers are 234 + 10 digits = 13 digits total.
    if (digits.length != 13) return null;
    return '+$digits';
  }

  static const providerTermii = 'termii';
  static const providerDeviceSim = 'device_sim';
  static const providerDeviceMessagingApp = 'device_messaging_app';

  static Future<bool> isConfigured() async {
    final enabled = await _db.getSetting(keyEnabled);
    if (enabled != 'true') return false;
    if (await _usesOnDeviceProvider()) return true;
    final apiKey = await _db.getSetting(keyApiKey);
    return apiKey != null && apiKey.isNotEmpty;
  }

  /// True for providers that run entirely on this device (no internet
  /// call to a cloud gateway, no API key needed).
  static Future<bool> _usesOnDeviceProvider() async {
    final provider = await _db.getSetting(keyProvider);
    return provider == providerDeviceSim || provider == providerDeviceMessagingApp;
  }

  static Future<SmsGateway?> _buildGateway() async {
    final provider = await _db.getSetting(keyProvider) ?? providerTermii;
    if (provider == providerDeviceSim) return DeviceSimSmsGateway();
    if (provider == providerDeviceMessagingApp) return DeviceMessagingAppGateway();

    final apiKey = await _db.getSetting(keyApiKey);
    final senderId = await _db.getSetting(keySenderId);
    if (apiKey == null || apiKey.isEmpty) return null;
    return TermiiSmsGateway(apiKey: apiKey, senderId: senderId ?? '');
  }

  /// Sends [message] to [rawPhone], guarding against missing config, bad
  /// phone numbers, and no internet connection before attempting the call.
  /// Always logs the attempt (success or failure) to sms_log.
  static Future<SmsSendResult> send({
    required String? rawPhone,
    required String message,
    int? studentId,
    required String context,
  }) async {
    final phone = normalizeNigerianPhone(rawPhone);
    if (phone == null) {
      return _fail(
        studentId: studentId,
        phone: rawPhone ?? '',
        message: message,
        context: context,
        error: 'No valid phone number on file for this parent',
      );
    }

    final enabled = await _db.getSetting(keyEnabled);
    if (enabled != 'true') {
      return _fail(
        studentId: studentId,
        phone: phone,
        message: message,
        context: context,
        error: 'SMS notifications are not enabled. Configure them in Preferences > SMS Settings.',
      );
    }

    final onDevice = await _usesOnDeviceProvider();
    if (!onDevice) {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.every((r) => r == ConnectivityResult.none)) {
        return _fail(
          studentId: studentId,
          phone: phone,
          message: message,
          context: context,
          error: 'No internet connection. SMS was not sent.',
        );
      }
    }

    final gateway = await _buildGateway();
    if (gateway == null) {
      return _fail(
        studentId: studentId,
        phone: phone,
        message: message,
        context: context,
        error: 'SMS gateway is not configured. Add an API key in Preferences > SMS Settings.',
      );
    }

    final result = await gateway.send(phone: phone, message: message);
    await _db.insertSmsLog(
      studentId: studentId,
      phone: phone,
      message: message,
      context: context,
      status: result.success ? 'sent' : 'failed',
      errorMessage: result.errorMessage,
    );
    return result;
  }

  static Future<SmsSendResult> _fail({
    required int? studentId,
    required String phone,
    required String message,
    required String context,
    required String error,
  }) async {
    await _db.insertSmsLog(
      studentId: studentId,
      phone: phone,
      message: message,
      context: context,
      status: 'failed',
      errorMessage: error,
    );
    return SmsSendResult.failure(error);
  }
}

// ========================================
// MESSAGE TEMPLATES
// ========================================

final _naira = NumberFormat('#,##0.00');
String _formatCurrency(double amount) => '₦${_naira.format(amount)}';

/// Formats bank accounts (bankName/accountNumber/accountName maps) as a
/// trailing block for SMS bodies, e.g. "Name of Bank: X\nAccount Number: Y".
/// Returns '' when there are no valid accounts, so callers can append it
/// unconditionally.
String formatBankAccountsForSms(List<Map<String, dynamic>>? bankAccounts) {
  if (bankAccounts == null || bankAccounts.isEmpty) return '';

  final valid = bankAccounts.where((acc) {
    final bankName = acc['bankName']?.toString() ?? '';
    final accNum = acc['accountNumber']?.toString() ?? '';
    return bankName.isNotEmpty && accNum.isNotEmpty;
  }).toList();
  if (valid.isEmpty) return '';

  final sb = StringBuffer('\n\nSchool Account Details:');
  for (final acc in valid) {
    sb.write('\nName of Bank: ${acc['bankName']}');
    sb.write('\nAccount Number: ${acc['accountNumber']}');
    final accName = acc['accountName']?.toString() ?? '';
    if (accName.isNotEmpty) sb.write('\nAccount Name: $accName');
  }
  return sb.toString();
}

String buildPaymentReceiptSms({
  required String schoolName,
  required String studentName,
  required double amount,
  required double grandTotal,
  required double outstanding,
  required String term,
  required String session,
}) {
  final balanceLine = outstanding > 0
      ? 'Outstanding balance: ${_formatCurrency(outstanding)}.'
      : 'Fees fully paid for $term, $session.';
  return "Dear Parent, a payment of ${_formatCurrency(amount)} for $studentName was received at $schoolName ($term, $session). $balanceLine Thank you.";
}

String buildBillSummarySms({
  required String schoolName,
  required String studentName,
  required double grandTotal,
  required double totalPaid,
  required double outstanding,
  required String term,
  required String session,
  List<Map<String, dynamic>>? bankAccounts,
}) {
  final balanceLine = outstanding > 0
      ? 'Outstanding balance: ${_formatCurrency(outstanding)}.'
      : 'Fees fully paid.';
  return "Dear Parent, $studentName's bill for $term, $session at $schoolName is ${_formatCurrency(grandTotal)}. Paid so far: ${_formatCurrency(totalPaid)}. $balanceLine"
      "${formatBankAccountsForSms(bankAccounts)}";
}

/// Bill summary SMS for the flat, class-level New Intake Bill (registration +
/// term + special fees) rather than a per-student tracked bill — there's no
/// totalPaid/outstanding concept here, just the amount due.
String buildNewIntakeBillSummarySms({
  required String schoolName,
  required String studentName,
  required double grandTotal,
  required String term,
  required String session,
  List<Map<String, dynamic>>? bankAccounts,
}) {
  return "Dear Parent, $studentName's New Intake Bill for $term, $session at $schoolName is ${_formatCurrency(grandTotal)}."
      "${formatBankAccountsForSms(bankAccounts)}";
}

class FamilyChildSummary {
  final String studentName;
  final double outstanding;
  const FamilyChildSummary({required this.studentName, required this.outstanding});
}

String buildFamilySms({
  required String schoolName,
  required String parentName,
  required List<FamilyChildSummary> children,
  required double totalOutstanding,
  required String term,
  required String session,
}) {
  final childrenLine = children
      .map((c) => '${c.studentName}: ${_formatCurrency(c.outstanding)}')
      .join(', ');
  return "Dear $parentName, family bill update for $term, $session at $schoolName - $childrenLine. Total outstanding: ${_formatCurrency(totalOutstanding)}. Thank you.";
}
