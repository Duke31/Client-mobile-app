import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/member_profile.dart';
import '../services/client_request_detail.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import 'history_screen.dart';
import 'profile_screen.dart';
import 'request_screen.dart';
import 'submitted_screen.dart';
import 'maternal_today_tab.dart';
import 'health_library_tab.dart';

class HomeScreen extends StatefulWidget {
  final int initialIndex;
  const HomeScreen({super.key, this.initialIndex = 0});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final GlobalKey<RequestScreenState> _requestScreenKey = GlobalKey<RequestScreenState>();

  int _currentIndex = 0;
  MemberProfile _profile = const MemberProfile(userId: '');
  bool _profileInitialized = false;
  Map<String, dynamic>? _activeEmergency;
  Timer? _activeCheckTimer;
  StreamSubscription? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;

    // Pre-warm high-accuracy GPS hardware in background so cold start / reinstall acquires immediate precision
    const LocationService().warmUp();

    // Synchronously initialize profile from cached session metadata to eliminate SOS screen flash
    final user = _supabase.auth.currentUser;
    if (user != null) {
      final meta = user.userMetadata;
      if (meta != null && meta.isNotEmpty) {
        _profile = MemberProfile.fromMap(meta, user.id);
        _profileInitialized = true;
      } else {
        _profile = MemberProfile(userId: user.id);
      }
    }

    _fetchProfile();
    _checkActiveEmergency();

    _activeCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkActiveEmergency();
    });

    try {
      _realtimeSub = _supabase
          .from('emergency_requests')
          .stream(primaryKey: ['id'])
          .listen((_) {
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

  Future<void> _fetchProfile() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final res = await _supabase
          .from('profiles')
          .select('*')
          .eq('user_id', uid)
          .maybeSingle();

      if (res != null && mounted) {
        setState(() {
          _profile = MemberProfile.fromMap(res, uid);
          _profileInitialized = true;
        });
      }
    } catch (_) {}
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
      if (list is List) {
        for (final row in List<Map<String, dynamic>>.from(list)) {
          final st = (row['status']?.toString() ?? '').toLowerCase();
          if (st.contains('completed') || st.contains('cancel') || st.contains('failed')) {
            continue;
          }
          active = row;
          break;
        }
      }

      if (active != null && active['id'] != null) {
        final detail = await ClientRequestDetail.fetch(
          _supabase,
          active['id'].toString(),
        );
        if (detail != null) {
          active = <String, dynamic>{
            ...Map<String, dynamic>.from(active),
            ...Map<String, dynamic>.from(detail),
          };
        }
      }

      if (!mounted) return;
      final hadActive = _activeEmergency != null;
      setState(() {
        _activeEmergency = active;
        // If an active emergency completed/cancelled while on tracker, return to primary tab
        if (hadActive && active == null && _currentIndex == 1 && !_profile.isMaternal) {
          _currentIndex = 0;
        }
      });
    } catch (e) {
      debugPrint('Active emergency check notice: $e');
    }
  }

  void _onTabSelected(int idx) {
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = idx);
  }

  void _dispatchConditionFromOtherTab(String condition, int priority) {
    final targetSosIndex = _profile.isMaternal ? 1 : 0;
    setState(() => _currentIndex = targetSosIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestScreenKey.currentState?.triggerConditionDispatch(condition, priority);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasActive = _activeEmergency != null;
    final isMaternal = _profile.isMaternal;

    final bgColor = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final navBg = isDark ? AppTheme.darkCard : Colors.white;
    final navBorder = isDark ? AppTheme.darkCardBorder : const Color(0xFFCBD5E1);
    final activeColor = isMaternal
        ? const Color(0xFFFF8A65)
        : (isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7));
    final unselectedColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    // Guard against cold-boot flash: wait until profile is resolved before choosing tab suite
    if (!_profileInitialized && _supabase.auth.currentUser != null) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFE8DC),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A65)),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Connecting Solace EMS...',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // A. MATERNAL CARE SUITE (5 Tabs: Today, SOS/Mission, Insights, Records, Shield)
    // ─────────────────────────────────────────────────────────────────────────
    if (isMaternal) {
      final maternalPages = [
        // Tab 0: Obstetric Maternal Dashboard (Matching reference images)
        MaternalTodayTab(
          profile: _profile,
          activeEmergency: _activeEmergency,
          onTriggerSos: () => setState(() => _currentIndex = 1),
          onOpenMissionTracker: () => setState(() => _currentIndex = 1),
          onTriggerFastPass: (cond, prio) => _dispatchConditionFromOtherTab(cond, prio),
          onOpenShieldTab: () => setState(() => _currentIndex = 4),
          onOpenInsightsTab: () => setState(() => _currentIndex = 2),
        ),

        // Tab 1: SOS Engine or Live Mission Tracker
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
            : RequestScreen(
                key: _requestScreenKey,
                initialProfile: _profile,
                onEmergencyCreated: (requestId, address, [lat, lng]) {
                  HapticFeedback.heavyImpact();
                  setState(() {
                    _activeEmergency = {
                      'id': requestId,
                      'patient_address': address,
                      'patient_lat': lat,
                      'patient_lng': lng,
                      'status': 'Requested',
                      'created_at': DateTime.now().toIso8601String(),
                    };
                    _currentIndex = 1;
                  });
                  _checkActiveEmergency();
                },
              ),

        // Tab 2: Health Library & Red Flags
        HealthLibraryTab(
          profile: _profile,
          onDispatchCondition: (cond, prio) => _dispatchConditionFromOtherTab(cond, prio),
        ),

        // Tab 3: History & Reviews
        HistoryScreen(
          onSwitchToSos: () => setState(() => _currentIndex = 1),
        ),

        // Tab 4: Maternal Shield & Medical ID
        ProfileScreen(
          onProfileUpdated: () {
            _fetchProfile();
          },
        ),
      ];

      return Scaffold(
        backgroundColor: bgColor,
        body: IndexedStack(
          index: _currentIndex.clamp(0, maternalPages.length - 1),
          children: maternalPages,
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: navBg,
            border: Border(top: BorderSide(color: navBorder, width: 1.0)),
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
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  );
                }
                return TextStyle(
                  color: unselectedColor,
                  fontSize: 10,
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
              selectedIndex: _currentIndex.clamp(0, 4),
              onDestinationSelected: _onTabSelected,
              backgroundColor: navBg,
              elevation: 0,
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.calendar_today_outlined),
                  selectedIcon: Icon(Icons.calendar_today_rounded),
                  label: 'Today',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: hasActive,
                    backgroundColor: const Color(0xFFFF334B),
                    smallSize: 8,
                    child: const Icon(Icons.emergency_outlined),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: hasActive,
                    backgroundColor: const Color(0xFFFF334B),
                    smallSize: 8,
                    child: const Icon(Icons.emergency_rounded, color: Color(0xFFFF334B)),
                  ),
                  label: hasActive ? 'Live Mission' : 'SOS Engine',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  selectedIcon: Icon(Icons.grid_view_rounded),
                  label: 'Insights',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.history_rounded),
                  selectedIcon: Icon(Icons.history_edu_rounded),
                  label: 'Records',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.badge_outlined),
                  selectedIcon: Icon(Icons.badge_rounded),
                  label: 'Medical ID',
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // B. STANDARD / NORMAL EMERGENCY PATIENT (The Loved Classic UI: 4 Tabs)
    // ─────────────────────────────────────────────────────────────────────────
    final standardPages = [
      // Tab 0: Primary Mapbox Emergency SOS Request Screen (Instant 1-Tap Dispatch)
      RequestScreen(
        key: _requestScreenKey,
        initialProfile: _profile,
        onEmergencyCreated: (requestId, address, [lat, lng]) {
          HapticFeedback.heavyImpact();
          setState(() {
            _activeEmergency = {
              'id': requestId,
              'patient_address': address,
              'patient_lat': lat,
              'patient_lng': lng,
              'status': 'Requested',
              'created_at': DateTime.now().toIso8601String(),
            };
            _currentIndex = 1; // Immediate live route to Tactical Tracker Desk!
          });
          _checkActiveEmergency();
        },
      ),

      // Tab 1: Live Tactical Mission Tracker Desk (Milestones, Hospital, Driver, Radar)
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

      // Tab 2: Closed Incident Records & Patient Service Reviews
      HistoryScreen(
        onSwitchToSos: () => setState(() => _currentIndex = 0),
      ),

      // Tab 3: Member Medical ID & Care Plan Shield
      ProfileScreen(
        onProfileUpdated: () {
          _fetchProfile();
        },
      ),
    ];

    return Scaffold(
      backgroundColor: bgColor,
      body: IndexedStack(
        index: _currentIndex.clamp(0, standardPages.length - 1),
        children: standardPages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: navBg,
          border: Border(top: BorderSide(color: navBorder, width: 1.0)),
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
                fontSize: 10,
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
            selectedIndex: _currentIndex.clamp(0, 3),
            onDestinationSelected: _onTabSelected,
            backgroundColor: navBg,
            elevation: 0,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.emergency_rounded),
                selectedIcon: Icon(Icons.emergency_rounded),
                label: 'Emergency SOS',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: hasActive,
                  backgroundColor: const Color(0xFFFF334B),
                  smallSize: 8,
                  child: const Icon(Icons.radar_rounded),
                ),
                selectedIcon: Badge(
                  isLabelVisible: hasActive,
                  backgroundColor: const Color(0xFFFF334B),
                  smallSize: 8,
                  child: const Icon(Icons.radar_rounded, color: Color(0xFF00D4FF)),
                ),
                label: hasActive ? 'Live Mission' : 'Mission Desk',
              ),
              const NavigationDestination(
                icon: Icon(Icons.history_rounded),
                selectedIcon: Icon(Icons.history_edu_rounded),
                label: 'Records',
              ),
              const NavigationDestination(
                icon: Icon(Icons.badge_outlined),
                selectedIcon: Icon(Icons.badge_rounded),
                label: 'Medical ID',
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
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final cardBorder = isDark ? AppTheme.darkCardBorder : const Color(0xFFCBD5E1);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? Colors.white60 : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cardBorder),
                boxShadow: isDark
                    ? []
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00D4FF).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.sensors_off_rounded,
                      color: Color(0xFF00D4FF),
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'No Active Emergency Run',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your telemetry and response radar are on high standby. When an ambulance is dispatched, real-time vehicle movement, hospital reservation, and paramedic contact cards will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: textMuted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: onTriggerSos,
                      icon: const Icon(Icons.emergency_rounded, size: 20),
                      label: const Text(
                        'DISPATCH EMERGENCY AMBULANCE',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
