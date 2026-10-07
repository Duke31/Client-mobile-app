import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Loads one request + assigned hospital/driver via SECURITY DEFINER RPC
/// so client UI is not blocked by tight table RLS on hospitals/drivers.
class ClientRequestDetail {
  ClientRequestDetail._();

  static Future<Map<String, dynamic>?> fetch(
    SupabaseClient supabase,
    String requestId,
  ) async {
    if (requestId.isEmpty) return null;
    try {
      final res = await supabase.rpc(
        'client_get_request_detail',
        params: {'p_request_id': requestId},
      );
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      if (res is String) {
        // unlikely
        return null;
      }
      return null;
    } catch (e) {
      debugPrint('client_get_request_detail RPC failed: $e');
      return null;
    }
  }
}
