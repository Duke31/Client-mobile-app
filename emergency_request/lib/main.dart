import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String supabaseUrl = const String.fromEnvironment('SUPABASE_URL').trim();
  final supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY').trim();

  // Strip trailing slashes to prevent //rest/v1 SSL handshake issues
  while (supabaseUrl.endsWith('/')) {
    supabaseUrl = supabaseUrl.substring(0, supabaseUrl.length - 1);
  }

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const EmergencyApp());
}

class EmergencyApp extends StatelessWidget {
  const EmergencyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.themeModeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'Solace Emergency',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentMode,
          home: const AuthGate(),
        );
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      return const HomeScreen();
    }
    return const AuthScreen();
  }
}
