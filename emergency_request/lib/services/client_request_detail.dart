import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Loads one request + assigned hospital/driver via SECURITY DEFINER RPC
/// so client UI is not blocked by tight table RLS on hospitals/drivers,
/// with robust client-side fallback if the RPC is not yet created.
class ClientRequestDetail {
  ClientRequestDetail._();

  static Future<Map<String, dynamic>?> fetch(
    SupabaseClient supabase,
    String requestId,
  ) async {
    if (requestId.isEmpty) return null;

    // 1. Preferred: SECURITY DEFINER RPC
    try {
      final res = await supabase.rpc(
        'client_get_request_detail',
        params: {'p_request_id': requestId},
      );
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
    } catch (e) {
      debugPrint('client_get_request_detail RPC notice: ');
    }

    // 2. Direct query fallback
    try {
      final req = await supabase
          .from('emergency_requests')
          .select('*, hospital:hospitals(*), driver:drivers(*)')
          .eq('id', requestId)
          .maybeSingle();

      if (req == null) return null;
      final out = Map<String, dynamic>.from(req);

      // Standalone queries if nested embeds were omitted
      if (out['hospital'] == null && out['hospital_id'] != null) {
        try {
          final h = await supabase
              .from('hospitals')
              .select('id, name, address, intake_phone')
              .eq('id', out['hospital_id'])
              .maybeSingle();
          if (h != null) out['hospital'] = h;
        } catch (_) {}
      }

      if (out['driver'] == null && out['driver_id'] != null) {
        try {
          final d = await supabase
              .from('drivers')
              .select('id, display_name, vehicle_label, phone, current_lat, current_lng, heading, speed, last_location_at')
              .eq('id', out['driver_id'])
              .maybeSingle();
          if (d != null) out['driver'] = d;
        } catch (_) {}
      }

      return out;
    } catch (e) {
      debugPrint('ClientRequestDetail direct fallback error: ');
      return null;
    }
  }
}
