import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/client_request_detail.dart';
import '../theme/app_theme.dart';
import 'request_screen.dart';
import 'submitted_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final int initialIndex;
  const HomeScreen({super.key, this.initialIndex = 0});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  int _currentIndex = 0;
  Map<String, dynamic>? _activeEmergency;
  Timer? _activeCheckTimer;
  StreamSubscription<List<Map<String, dynamic>>>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _checkActiveEmergency();
    _activeCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkActiveEmergency();
    });

    // Real-time stream for instant status progression
    try {
      _realtimeSub = _supabase
          .from('emergency_requests')
          .stream(primaryKey: ['id'])
          .listen((data) {
            _checkActiveEmergency();
          }, onError: (_) {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _activeCheckTimer?.cancel();
    _realtimeSub?.cancel();
    super.dispose();
  }

  Future<void> _checkActiveEmergency() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null || !mounted) return;

    try {
      final list = await _supabase
          .from('emergency_requests')
          .select(
            'id, status, emergency_type, patient_address, patient_lat, patient_lng, '
            'created_at, client_user_id, hospital_id, driver_id',
          )
          .or('client_user_id.eq.$uid,reported_by_user_id.eq.$uid')
          .order('created_at', ascending: false)
          .limit(20);

      Map<String, dynamic>? active;
      for (final row in List<Map<String, dynamic>>.from(list as List)) {
        final st = (row['status']?.toString() ?? '').toLowerCase();
        if (st.contains('completed') || st.contains('cancel') || st.contains('failed')) {
          continue;
        }
        active = row;
        break;
      }

      // Enrich active with hospital/driver names via RPC
      if (active != null && active['id'] != null) {
        final detail = await ClientRequestDetail.fetch(
          _supabase,
          active['id'].toString(),
        );
        if (detail != null) {
          active = <String, dynamic>{
            ...Map<String, dynamic>.from(active!),
            ...Map<String, dynamic>.from(detail),
          };
        }
      }

      if (!mounted) return;
      setState(() {
        _activeEmergency = active; // null clears stuck post-cancel SOS
      });
    } catch (e) {
      debugPrint('Active emergency check error: $e');
      // Fallback without or-filter
      try {
        final list = await _supabase
            .from('emergency_requests')
            .select('id, status, emergency_type, patient_address, patient_lat, patient_lng, created_at, hospital_id, driver_id')
            .eq('client_user_id', uid)
            .order('created_at', ascending: false)
            .limit(20);
        Map<String, dynamic>? active;
        for (final row in List<Map<String, dynamic>>.from(list as List)) {
          final st = (row['status']?.toString() ?? '').toLowerCase();
          if (st.contains('completed') || st.contains('cancel') || st.contains('failed')) {
            continue;
          }
          active = row;
          break;
        }
        if (active != null && active['id'] != null) {
          final detail = await ClientRequestDetail.fetch(
            _supabase,
            active['id'].toString(),
          );
          if (detail != null) {
            active = <String, dynamic>{
              ...Map<String, dynamic>.from(active!),
              ...Map<String, dynamic>.from(detail),
            };
          }
        }
        if (mounted) setState(() => _activeEmergency = active);
      } catch (e2) {
        debugPrint('Active fallback error: $e2');
      }
    }
  }

  void _onTabSelected(int idx) {
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = idx);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasActive = _activeEmergency != null;

    final bgColor = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final navBg = isDark ? AppTheme.darkCard : Colors.white;
    final navBorder = isDark ? AppTheme.darkCardBorder : const Color(0xFFCBD5E1);
    final activeColor = isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7);
    final unselectedColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final pages = [
      // 0: SOS Screen
      RequestScreen(
        onEmergencyCreated: (requestId, address, [lat, lng]) {
          HapticFeedback.heavyImpact();
          setState(() {
            _activeEmergency = {
              'id': requestId,
              'patient_address': address,
              'patient_lat': lat,
              'patient_lng': lng,
              'status': 'Pending dispatch',
              'created_at': DateTime.now().toIso8601String(),
            };
            _currentIndex = 1; // Immediately route to Live Tracker!
          });
          _checkActiveEmergency();
        },
      ),
      // 1: Active Mission Tracker
      hasActive
          ? SubmittedScreen(
              key: ValueKey(_activeEmergency!['id']),
              requestId: _activeEmergency!['id']?.toString(),
              address: _activeEmergency!['patient_address']?.toString(),
              patientAddress: _activeEmergency!['patient_address']?.toString(),
              latitude: (_activeEmergency!['patient_lat'] as num?)?.toDouble(),
              longitude: (_activeEmergency!['patient_lng'] as num?)?.toDouble(),
              onReturnHome: () {
                setState(() {
                  _activeEmergency = null;
                  _currentIndex = 0;
                });
                _checkActiveEmergency();
              },
            )
          : _NoActiveMissionView(
              onTriggerSos: () => setState(() => _currentIndex = 0),
            ),
      // 2: History & Feedback
      HistoryScreen(
        onSwitchToSos: () => setState(() => _currentIndex = 0),
      ),
      // 3: Settings & General Preferences
      SettingsScreen(
        onSwitchToSos: () => setState(() => _currentIndex = 0),
      ),
    ];

    return Scaffold(
      backgroundColor: bgColor,
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: navBg,
          border: Border(
            top: BorderSide(color: navBorder, width: 1.0),
          ),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: navBg,
            indicatorColor: activeColor.withValues(alpha: isDark ? 0.22 : 0.16),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return TextStyle(
                  color: activeColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                );
              }
              return TextStyle(
                color: unselectedColor,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              );
            }),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return IconThemeData(color: activeColor, size: 24);
              }
              return IconThemeData(color: unselectedColor, size: 22);
            }),
          ),
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: _onTabSelected,
            backgroundColor: navBg,
            elevation: 0,
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.emergency_outlined),
                selectedIcon: const Icon(Icons.emergency_rounded, color: Color(0xFFFF334B)),
                label: 'SOS Dispatch',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: hasActive,
                  backgroundColor: const Color(0xFFFF334B),
                  smallSize: 8,
                  child: const Icon(Icons.radar_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: hasActive,
                  backgroundColor: const Color(0xFFFF334B),
                  smallSize: 8,
                  child: const Icon(Icons.radar_rounded),
                ),
                label: hasActive ? 'Active Mission' : 'Live Tracker',
              ),
              const NavigationDestination(
                icon: Icon(Icons.history_rounded),
                selectedIcon: Icon(Icons.history_rounded),
                label: 'History & Review',
              ),
              const NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoActiveMissionView extends StatelessWidget {
  final VoidCallback onTriggerSos;
  const _NoActiveMissionView({required this.onTriggerSos});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final cardBorder = isDark ? AppTheme.darkCardBorder : const Color(0xFFCBD5E1);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? Colors.white60 : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: isDark ? 0 : 0.5,
        title: Text(
          'ACTIVE MISSION TRACKER',
          style: TextStyle(
            color: textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 14.5,
            letterSpacing: 1.0,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: cardColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: cardBorder, width: 1.5),
                  boxShadow: isDark
                      ? []
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                          ),
                        ],
                ),
                child: Icon(
                  Icons.sensors_off_rounded,
                  size: 48,
                  color: isDark ? const Color(0xFF81D4FA) : const Color(0xFF0284C7),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'No Active Emergency Request',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'When you request an ambulance, live telemetry, hospital bed reservation, and responder routing will update here in real time.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textMuted,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD32F2F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: onTriggerSos,
                icon: const Icon(Icons.emergency_rounded, size: 22),
                label: const Text(
                  'TRIGGER EMERGENCY SOS',
                  style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


