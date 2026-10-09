import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../maps/mapbox_geocoding.dart';
import 'emergency_type.dart';

class EmergencyService {
  EmergencyService({
    required this.supabase,
    MapboxGeocoding? geocoding,
  }) : geocoding = geocoding ?? MapboxGeocoding();

  final SupabaseClient supabase;
  final MapboxGeocoding geocoding;

  static const Duration requestTimeout = Duration(seconds: 8);

  Future<dynamic> createRequest({
    required double latitude,
    required double longitude,
    String? address,
    String emergencyType = 'Other',
    int priority = 2,
    String notes = '',
    String contactPhone = '',
    String ageBand = 'unknown',
    String? idempotencyKey,
    Map<String, dynamic> extraParams = const <String, dynamic>{},
  }) async {
    try {
      return await _createRequestInner(
        latitude: latitude,
        longitude: longitude,
        address: address,
        emergencyType: emergencyType,
        priority: priority,
        notes: notes,
        contactPhone: contactPhone,
        ageBand: ageBand,
        idempotencyKey: idempotencyKey,
        extraParams: extraParams,
      ).timeout(requestTimeout);
    } on TimeoutException {
      throw const EmergencyNetworkException(
        'Request timed out after 8 seconds. Dispatch server did not respond.',
      );
    } on SocketException catch (e) {
      throw EmergencyNetworkException(
        'No network connection (${e.message}).',
      );
    } on HttpException catch (e) {
      throw EmergencyNetworkException('HTTP error: ${e.message}');
    }
  }

  Future<dynamic> _createRequestInner({
    required double latitude,
    required double longitude,
    String? address,
    String emergencyType = 'Other',
    int priority = 2,
    String notes = '',
    String contactPhone = '',
    String ageBand = 'unknown',
    String? idempotencyKey,
    Map<String, dynamic> extraParams = const <String, dynamic>{},
  }) async {
    final session = supabase.auth.currentSession;
    if (session == null) {
      throw Exception(
        'User is not signed in. Please sign in to request an emergency.',
      );
    }

    final userId = session.user.id;
    try {
      await supabase.from('profiles').upsert({
        'user_id': userId,
        'role': 'client',
      }, onConflict: 'user_id');
    } catch (e) {
      debugPrint('Profile sync notice: $e');
    }

    final resolvedAddress = (address != null && address.trim().isNotEmpty)
        ? address.trim()
        : await geocoding.reverseGeocode(
            latitude: latitude,
            longitude: longitude,
          );

    final (typeForDb, typeNote) = EmergencyTypeNormalizer.normalize(emergencyType);
    final ageNote = (ageBand.trim().isNotEmpty && ageBand.trim().toLowerCase() != 'unknown')
        ? 'Age band: ${ageBand.trim()}'
        : null;
    final notesMerged = [
      if (notes.trim().isNotEmpty) notes.trim(),
      if (typeNote != null) typeNote,
      if (ageNote != null) ageNote,
    ].join(' | ');

    final params = <String, dynamic>{
      'p_patient_lat': latitude,
      'p_patient_lng': longitude,
      'p_patient_address':
          resolvedAddress.isNotEmpty ? resolvedAddress : 'Current GPS location',
      'p_emergency_type': typeForDb,
      'p_priority': priority,
      'p_notes': notesMerged.isNotEmpty ? notesMerged : null,
      'p_contact_phone':
          contactPhone.trim().isNotEmpty ? contactPhone.trim() : null,
      'p_patient_age_band': ageBand,
      'p_idempotency_key': idempotencyKey ?? _uuidV4(),
      ...extraParams,
    };

    return supabase.rpc('create_emergency_request', params: params);
  }

  static String _uuidV4() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String h(int i) => bytes[i].toRadixString(16).padLeft(2, '0');
    return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
  }
}

/// Raised when dispatch cannot reach the backend (timeout / offline).
class EmergencyNetworkException implements Exception {
  const EmergencyNetworkException(this.message);
  final String message;

  @override
  String toString() => message;
}
