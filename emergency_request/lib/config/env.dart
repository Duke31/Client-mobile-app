/// Compile-time environment via --dart-define / dart_defines.json
class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static const mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: 'YOUR_TOKEN',
  );

  /// SMS dispatch hotline E.164, e.g. +23480...
  static const emergencySmsHotline = String.fromEnvironment(
    'EMERGENCY_SMS_HOTLINE',
    defaultValue: '',
  );

  /// Optional voice line (your cell or local EMS). Empty = hide Call buttons.
  static const emergencyVoiceHotline = String.fromEnvironment(
    'EMERGENCY_VOICE_HOTLINE',
    defaultValue: '',
  );

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get hasMapboxToken =>
      mapboxAccessToken.isNotEmpty && mapboxAccessToken != 'YOUR_TOKEN';

  static bool get hasEmergencySmsHotline =>
      emergencySmsHotline.trim().isNotEmpty;

  static bool get hasEmergencyVoiceHotline =>
      emergencyVoiceHotline.trim().isNotEmpty;
}

class AppConfig {
  const AppConfig._();

  static String get emergencySmsHotline => Env.emergencySmsHotline;
  static String get emergencyVoiceHotline => Env.emergencyVoiceHotline;
}
