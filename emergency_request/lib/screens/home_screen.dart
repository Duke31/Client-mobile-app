import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/member_profile.dart';
import '../services/client_request_detail.dart';
import '../theme/app_theme.dart';
import 'dashboard_tab.dart';
import 'health_library_tab.dart';
import 'history_screen.dart';
import 'profile_screen.dart';
import 'request_screen.dart';

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
  Map<String, dynamic>? _activeEmergency;
  Timer? _activeCheckTimer;
  StreamSubscription? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _fetchProfile();
    _checkActiveEmergency();

    _activeCheckTimer = Timer.periodic(const Duration(seconds: 4), (_) {
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
          .neq('status', 'Completed')
          .neq('status', 'Cancelled / failed')
          .neq('status', 'completed')
          .neq('status', 'cancelled')
          .order('created_at', ascending: false)
          .limit(1);

      Map<String, dynamic>? active;
      if (list is List && list.isNotEmpty) {
        active = Map<String, dynamic>.from(list.first as Map);
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
      setState(() {
        _activeEmergency = active;
      });
    } catch (e) {
      debugPrint('Active emergency check error: $e');
    }
  }

  void _onTabSelected(int idx) {
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = idx);
  }

  void _dispatchConditionFromOtherTab(String condition, int priority) {
    setState(() => _currentIndex = 1); // Switch to SOS tab
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestScreenKey.currentState?.triggerConditionDispatch(condition, priority);
    });
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
      // Tab 0: Role-Adaptive Clinical Care Dashboard
      DashboardTab(
        profile: _profile,
        onTriggerSos: () => setState(() => _currentIndex = 1),
        onTriggerFastPass: (cond, prio) => _dispatchConditionFromOtherTab(cond, prio),
      ),

      // Tab 1: Tactical SOS Engine & Live Telemetry Control Room
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
            _currentIndex = 1;
          });
          _checkActiveEmergency();
        },
      ),

      // Tab 2: Closed Incident Records & Patient Service Reviews
      HistoryScreen(
        onSwitchToSos: () => setState(() => _currentIndex = 1),
      ),

      // Tab 3: Health Library & Red Flags
      HealthLibraryTab(
        onDispatchCondition: (cond, prio) => _dispatchConditionFromOtherTab(cond, prio),
      ),

      // Tab 4: Member Medical ID & Care Plan Shield
      ProfileScreen(
        onProfileUpdated: () {
          _fetchProfile();
        },
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
            selectedIndex: _currentIndex,
            onDestinationSelected: _onTabSelected,
            backgroundColor: navBg,
            elevation: 0,
            destinations: [
              // Tab 0: Dashboard
              const NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard_rounded),
                label: 'Care Desk',
              ),

              // Tab 1: SOS Engine / Live Mission
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

              // Tab 2: Records & Reviews
              const NavigationDestination(
                icon: Icon(Icons.history_rounded),
                selectedIcon: Icon(Icons.history_edu_rounded),
                label: 'Records',
              ),

              // Tab 3: Health Library
              const NavigationDestination(
                icon: Icon(Icons.health_and_safety_outlined),
                selectedIcon: Icon(Icons.health_and_safety_rounded),
                label: 'Red Flags',
              ),

              // Tab 4: Member Profile & Shield
              const NavigationDestination(
                icon: Icon(Icons.shield_outlined),
                selectedIcon: Icon(Icons.shield_rounded),
                label: 'My Shield',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
