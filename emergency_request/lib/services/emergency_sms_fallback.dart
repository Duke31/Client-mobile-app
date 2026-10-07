import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class EmergencySmsFallback {
  const EmergencySmsFallback._();

  /// Solace Central Dispatch Desk Hotline & WhatsApp Line
  static const String solaceDispatchPhone = '+2348133355709';

  static String buildBody({
    required String emergencyType,
    required double latitude,
    required double longitude,
    String? address,
    String? callerPhone,
  }) {
    final loc = (address != null && address.trim().isNotEmpty)
        ? address.trim()
        : '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
    final caller = (callerPhone != null && callerPhone.trim().isNotEmpty)
        ? callerPhone.trim()
        : 'Patient / Bystander';
    final time = DateTime.now().toIso8601String();
    return '🚨 SOLACE EMERGENCY SOS\n'
        '• Condition: $emergencyType\n'
        '• Location: $loc\n'
        '• Caller: $caller\n'
        '• GPS Coordinates: $latitude, $longitude\n'
        '• Live Map Link: https://maps.google.com/?q=$latitude,$longitude\n'
        '• Time: $time';
  }

  /// Opens WhatsApp directly to Solace Central Dispatch Desk (+2348133355709)
  static Future<bool> openWhatsApp({
    required String body,
    String phone = solaceDispatchPhone,
  }) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final encoded = Uri.encodeComponent(body);
    final candidates = [
      Uri.parse('whatsapp://send?phone=$cleanPhone&text=$encoded'),
      Uri.parse('https://wa.me/$cleanPhone?text=$encoded'),
      Uri.parse('https://api.whatsapp.com/send?phone=$cleanPhone&text=$encoded'),
    ];

    for (final uri in candidates) {
      try {
        final ok = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (ok) return true;
      } catch (e) {
        debugPrint('WhatsApp launch error for $uri: $e');
      }
    }
    return false;
  }

  /// Opens native SMS composer directly to Solace Central Dispatch Desk (+2348133355709)
  static Future<bool> openNativeSms({
    required String body,
    String hotline = solaceDispatchPhone,
  }) async {
    final number = hotline.trim();
    final encodedBody = Uri.encodeComponent(body);

    final candidates = <Uri>[
      if (number.isNotEmpty) ...[
        if (!kIsWeb && Platform.isIOS)
          Uri.parse('sms:$number&body=$encodedBody')
        else
          Uri.parse('sms:$number?body=$encodedBody'),
        Uri(scheme: 'sms', path: number, queryParameters: {'body': body}),
      ] else ...[
        if (!kIsWeb && Platform.isIOS)
          Uri.parse('sms:&body=$encodedBody')
        else
          Uri.parse('sms:?body=$encodedBody'),
        Uri(scheme: 'sms', queryParameters: {'body': body}),
      ],
    ];

    for (final uri in candidates) {
      try {
        final ok = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (ok) return true;
      } catch (e) {
        debugPrint('SMS launch failed for $uri: $e');
      }
    }
    return false;
  }
}
