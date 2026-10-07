import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  /// Global notifier to allow instant switching between Dark and Light mode
  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

  static bool get isDark => themeModeNotifier.value == ThemeMode.dark;

  static void toggleTheme() {
    themeModeNotifier.value =
        isDark ? ThemeMode.light : ThemeMode.dark;
  }

  static void setTheme(ThemeMode mode) {
    themeModeNotifier.value = mode;
  }

  // --- DARK TACTICAL PALETTE (Emergency Midnight Navy) ---
  static const Color darkBg = Color(0xFF061536);
  static const Color darkCard = Color(0xFF07193F);
  static const Color darkCardBorder = Color(0xFF1E3A8A);
  static const Color darkPrimary = Color(0xFF00D4FF); // Tactical Cyan
  static const Color darkAccent = Color(0xFFFF334B);  // Emergency Red
  static const Color darkSuccess = Color(0xFF00E676); // Responded Green
  static const Color darkTextPrimary = Colors.white;
  static const Color darkTextSecondary = Color(0xFF81D4FA);
  static const Color darkTextMuted = Colors.white60;

  // --- LIGHT CLINICAL PALETTE (Clean Platinum Medical) ---
  static const Color lightBg = Color(0xFFF1F5F9);
  static const Color lightCard = Colors.white;
  static const Color lightCardBorder = Color(0xFFCBD5E1);
  static const Color lightPrimary = Color(0xFF0284C7); // Clinical Blue
  static const Color lightAccent = Color(0xFFDC2626);  // Emergency Red
  static const Color lightSuccess = Color(0xFF16A34A); // Verified Green
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF334155);
  static const Color lightTextMuted = Color(0xFF64748B);

  // --- DARK THEME DATA ---
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      colorScheme: const ColorScheme.dark(
        primary: darkPrimary,
        secondary: darkAccent,
        surface: darkCard,
        onSurface: Colors.white,
        onPrimary: darkBg,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkCard,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkCard,
        elevation: 0,
        indicatorColor: darkPrimary.withValues(alpha: 0.22),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: darkPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            );
          }
          return const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: darkPrimary, size: 24);
          }
          return const IconThemeData(color: Color(0xFF94A3B8), size: 22);
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: darkAccent,
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkPrimary,
          side: const BorderSide(color: darkPrimary),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  // --- LIGHT THEME DATA ---
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBg,
      colorScheme: const ColorScheme.light(
        primary: lightPrimary,
        secondary: lightAccent,
        surface: lightCard,
        onSurface: lightTextPrimary,
        onPrimary: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: lightTextPrimary,
        elevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: lightTextPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        elevation: 1,
        indicatorColor: lightPrimary.withValues(alpha: 0.16),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: lightPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            );
          }
          return const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: lightPrimary, size: 24);
          }
          return const IconThemeData(color: Color(0xFF64748B), size: 22);
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: lightAccent,
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: lightPrimary,
          side: const BorderSide(color: lightPrimary),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
