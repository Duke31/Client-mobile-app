import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sanitizes backend, database (PostgREST / Postgres), and network errors
/// before displaying them to end users.
///
/// Prevents CWE-209 Information Disclosure vulnerabilities by shielding
/// internal table names, schemas, SQL constraints, and RLS policy details.
class ErrorSanitizer {
  ErrorSanitizer._();

  static String sanitize(Object? error, {String fallback = 'An unexpected error occurred. Please try again.'}) {
    if (error == null) return fallback;

    // Always log the technical error to dev console for debugging
    debugPrint('[INTERNAL SECURE LOG] Raw error: $error');

    if (error is PostgrestException) {
      final code = error.code ?? '';
      final msg = error.message.toLowerCase();
      final details = (error.details?.toString() ?? '').toLowerCase();

      // RLS or permission denied (Postgres code 42501)
      if (code == '42501' ||
          msg.contains('permission denied') ||
          msg.contains('violates row-level security') ||
          msg.contains('insufficient_standing') ||
          details.contains('permission denied')) {
        return 'Access denied: You do not have permission to perform this action.';
      }

      // Unauthenticated
      if (msg.contains('unauthenticated') || msg.contains('auth.uid() is null')) {
        return 'Session expired. Please sign in again.';
      }

      // Unique constraint violation (code 23505)
      if (code == '23505' || msg.contains('unique') || msg.contains('duplicate key')) {
        return 'This record or emergency request has already been submitted.';
      }

      // Foreign key or not found
      if (code == '23503' || msg.contains('foreign key')) {
        return 'Referenced record was not found or has changed.';
      }

      // Clean business exceptions that don't leak SQL details
      if (!msg.contains('table') &&
          !msg.contains('column') &&
          !msg.contains('syntax') &&
          !msg.contains('relation') &&
          !msg.contains('violates') &&
          !msg.contains('pg_') &&
          error.message.trim().isNotEmpty) {
        return error.message.trim();
      }

      return 'Unable to process request due to an authorization or validation rule.';
    }

    if (error is AuthException) {
      return error.message;
    }

    final errStr = error.toString().toLowerCase();

    // Catch raw PostgrestException string representation if wrapped in another exception
    if (errStr.contains('postgrestexception') || errStr.contains('42501') || errStr.contains('permission denied')) {
      return 'Access denied: You do not have permission to perform this action.';
    }

    if (errStr.contains('socketexception') ||
        errStr.contains('failed host lookup') ||
        errStr.contains('network') ||
        errStr.contains('timed out') ||
        errStr.contains('timeout')) {
      return 'Network connection issue. Please check your internet connectivity.';
    }

    return fallback;
  }
}
