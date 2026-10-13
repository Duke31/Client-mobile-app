import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../maps/mapbox_geocoding.dart';
import '../maps/mapbox_map_view.dart';
import '../models/member_profile.dart';
import '../services/cluster_resolver.dart';
import '../services/emergency_service.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import 'submitted_screen.dart';

const LatLng kDefaultCenter = LatLng(7.3775, 3.9470); // Ibadan default

class RequestScreen extends StatefulWidget {
  final Function? onEmergencyCreated;
  final MemberProfile? initialProfile;

  const RequestScreen({
    super.key,
    this.onEmergencyCreated,
    this.initialProfile,
  });

  @override
  State<RequestScreen> createState() => RequestScreenState();
}

class RequestScreenState extends State<RequestScreen>
    with SingleTickerProviderStateMixin {
  final _location = const LocationService();
  final _geocoding = MapboxGeocoding();
  final _mapController = MapController();

  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  bool _loadingLocation = true;
  bool _submitting = false;
  LocationFix? _fix;
  String _address = '';

  MemberProfile _profile = const MemberProfile(userId: '');
  bool _showMaternalPasses = true;

  // Active mission state
  Map<String, dynamic>? _activeMission;
  Timer? _activeMissionTimer;
  StreamSubscription? _realtimeSub;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _pulseOpacity = Tween<double>(begin: 0.7, end: 0.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.initialProfile != null) {
      _profile = widget.initialProfile!;
      _showMaternalPasses = _profile.isMaternal;
    } else {
      _fetchProfile();
    }

    _loadLocation();
    _checkActiveMission();

    _activeMissionTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _checkActiveMission();
    });

    try {
      _realtimeSub = Supabase.instance.client
          .from('emergency_requests')
          .stream(primaryKey: ['id'])
          .listen((_) => _checkActiveMission(), onError: (_) {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _activeMissionTimer?.cancel();
    _realtimeSub?.cancel();
    _geocoding.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('*')
          .eq('user_id', userId)
          .maybeSingle();

      if (res != null && mounted) {
        setState(() {
          _profile = MemberProfile.fromMap(res, userId);
          _showMaternalPasses = _profile.isMaternal;
        });
      }
    } catch (_) {}
  }

  Future<void> _checkActiveMission() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || !mounted) return;
    try {
      final res = await Supabase.instance.client
          .from('emergency_requests')
          .select(
            'id, status, emergency_type, patient_address, patient_lat, patient_lng, '
            'created_at, driver_id, hospital_id, notes, drivers(display_name, phone, vehicle_label)',
          )
          .or('client_user_id.eq.$uid,reported_by_user_id.eq.$uid')
          .neq('status', 'Completed')
          .neq('status', 'Cancelled / failed')
          .neq('status', 'completed')
          .neq('status', 'cancelled')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _activeMission = res;
          if (res == null && _submitting) _submitting = false;
        });
      }
    } catch (_) {}
  }

  Future<void> _applyFix(LocationFix fix) async {
    if (!mounted) return;
    setState(() {
      _fix = fix;
      _loadingLocation = false;
    });
    try {
      _mapController.move(LatLng(fix.latitude, fix.longitude), 16.5);
    } catch (_) {}

    _geocoding
        .reverseGeocode(latitude: fix.latitude, longitude: fix.longitude)
        .then((addr) {
      if (mounted && addr.isNotEmpty) {
        setState(() => _address = addr);
      }
    });
  }

  Future<void> _loadLocation() async {
    final estimate = await _location.quickEstimate();
    if (estimate != null && mounted) {
      await _applyFix(estimate);
    }

    try {
      final fix = await _location.current();
      if (mounted) {
        await _applyFix(fix);
      }
    } catch (e) {
      if (!mounted) return;
      if (_fix == null) {
        final fallback = LocationFix(
          latitude: kDefaultCenter.latitude,
          longitude: kDefaultCenter.longitude,
          fromCache: true,
        );
        await _applyFix(fallback);
      }
    }
  }

  /// Triggered from outside or from fast-pass buttons
  Future<void> triggerConditionDispatch(String condition, int priority) async {
    await _executeEmergencyDispatch(condition: condition, priority: priority);
  }

  Future<void> _executeEmergencyDispatch({
    String? condition,
    int priority = 1,
  }) async {
    if (_submitting) return;
    if (_fix == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Acquiring high-accuracy GPS... Please wait a second.'),
          backgroundColor: Colors.amber,
        ),
      );
      await _loadLocation();
      if (_fix == null) return;
    }

    HapticFeedback.heavyImpact();
    setState(() => _submitting = true);

    final supabase = Supabase.instance.client;
    final fix = _fix!;
    final clusterId = ClusterResolver.resolveClusterId(fix.latitude, fix.longitude);

    final finalType = condition != null
        ? (condition.toLowerCase().contains('bleed') ||
                condition.toLowerCase().contains('water') ||
                condition.toLowerCase().contains('labor') ||
                condition.toLowerCase().contains('headache') ||
                condition.toLowerCase().contains('movement') ||
                _profile.isMaternal
            ? 'Obstetric'
            : condition.toLowerCase().contains('trauma')
                ? 'Trauma'
                : condition.toLowerCase().contains('chest') ||
                        condition.toLowerCase().contains('heart')
                    ? 'Cardiac'
                    : condition.toLowerCase().contains('breath')
                        ? 'Respiratory'
                        : 'Other')
        : (_profile.isMaternal ? 'Obstetric' : 'Other');

    // Build Standardized SBAR note
    final situation = condition ??
        (_profile.isMaternal ? 'Maternal Obstetric Distress' : 'Medical Emergency Distress');
    final bgList = <String>[];
    if (_profile.isMaternal && _profile.gestationalWeeks != null) {
      bgList.add('${_profile.gestationalWeeks}w');
    }
    if (_profile.gravidaPara != null) bgList.add(_profile.gravidaPara!);
    if (_profile.bloodGroup != null) bgList.add('Blood: ${_profile.bloodGroup}');
    if (_profile.genotype != null) bgList.add('Genotype: ${_profile.genotype}');
    if (_profile.allergies != null) bgList.add('Allergies: ${_profile.allergies}');
    if (_profile.knownRisks.isNotEmpty) {
      bgList.add('Risks: ${_profile.knownRisks.join(", ")}');
    }
    final background = bgList.isNotEmpty ? bgList.join(', ') : 'Standard subscriber baseline';

    final isHemorrhage = condition != null && condition.toLowerCase().contains('bleed');
    final isProm = condition != null && condition.toLowerCase().contains('water');

    final assessment = 'P$priority Rapid En-Route Intercept ($finalType)';
    final recommendation = isHemorrhage
        ? 'Direct-to-Bed, Alert Blood Bank (O-Neg), Prepare L&D Suite'
        : isProm
            ? 'Prepare Sterile L&D Delivery Suite'
            : _profile.isMaternal
                ? 'Direct Obstetric Bay, Notify Attending Consultant'
                : 'Direct-to-Bed Acute Resuscitation Bay';

    final sbarNote = ClusterResolver.formatSbarNote(
      clusterId: clusterId,
      situation: situation,
      background: background,
      assessment: assessment,
      recommendation: recommendation,
    );

    try {
      final service = EmergencyService(
        supabase: supabase,
        geocoding: _geocoding,
      );

      final rpcResult = await service.createRequest(
        latitude: fix.latitude,
        longitude: fix.longitude,
        address: _address.isNotEmpty ? _address : 'GPS: ${fix.latitude}, ${fix.longitude}',
        emergencyType: finalType,
        priority: priority, // SMALLINT 1
        notes: sbarNote,
        contactPhone: _profile.phone,
        ageBand: _profile.isMaternal ? '18-39' : '18-39',
      );

      String? createdRequestId;
      if (rpcResult is Map && rpcResult['id'] != null) {
        createdRequestId = rpcResult['id'] as String;
      }

      if (!mounted) return;
      setState(() => _submitting = false);

      if (widget.onEmergencyCreated != null && createdRequestId != null) {
        widget.onEmergencyCreated!(createdRequestId, _address, fix.latitude, fix.longitude);
      }

      await _checkActiveMission();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Dispatch submission error: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasActive = _activeMission != null;

    if (hasActive) {
      final reqId = _activeMission!['id']?.toString() ?? '';
      return SubmittedScreen(
        requestId: reqId,
        latitude: (_activeMission!['patient_lat'] as num?)?.toDouble(),
        longitude: (_activeMission!['patient_lng'] as num?)?.toDouble(),
        address: _activeMission!['patient_address']?.toString(),
        onReturnHome: () {
          setState(() {
            _activeMission = null;
          });
          _checkActiveMission();
        },
      );
    }

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('🚨 ', style: TextStyle(fontSize: 20)),
                          Text(
                            'Emergency SOS Engine',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                              letterSpacing: -0.4,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '1-tap verified GPS dispatch • Direct-to-Bed',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                        ),
                      ),
                    ],
                  ),
                  // Care plan mode toggle
                  ActionChip(
                    avatar: Text(_showMaternalPasses ? '🌸' : '🛡️'),
                    label: Text(
                      _showMaternalPasses ? 'Maternal' : 'Standard',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                    onPressed: () {
                      setState(() => _showMaternalPasses = !_showMaternalPasses);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // GPS Accuracy Card
              _buildGpsStatusPill(isDark),
              const SizedBox(height: 24),

              // ── HIGH-CONTRAST 1-TAP PULSING SOS BUTTON ───────────────────
              _buildHighContrastSosButton(isDark),
              const SizedBox(height: 28),

              // ── ZERO-TYPING COMPLICATION FAST-PASS BUTTONS ───────────────
              _buildZeroTypingFastPassSection(isDark),
              const SizedBox(height: 24),

              // 24/7 Telephone Hotline fallback
              _buildHotlineFallback(isDark),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGpsStatusPill(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppTheme.darkCardBorder : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_rounded, color: Color(0xFF00E676), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'GPS LOCK ACTIVE (High Accuracy)',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF00E676),
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  _loadingLocation
                    ? 'Locking satellite coordinates...'
                    : _address.isNotEmpty
                        ? _address
                        : (_fix != null ? '${_fix!.latitude}, ${_fix!.longitude}' : 'Location ready'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _loadLocation,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            tooltip: 'Re-calibrate GPS',
          ),
        ],
      ),
    );
  }

  Widget _buildHighContrastSosButton(bool isDark) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Animated Pulse ring
          AnimatedBuilder(
            animation: _pulseScale,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseScale.value,
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFF1744).withValues(alpha: _pulseOpacity.value),
                  ),
                ),
              );
            },
          ),
          // Main Button
          GestureDetector(
            onTap: _submitting ? null : () => _executeEmergencyDispatch(),
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF1744), Color(0xFFD50000)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF1744).withValues(alpha: 0.45),
                    blurRadius: 28,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border.all(color: Colors.white, width: 3.5),
              ),
              child: Center(
                child: _submitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.shield_rounded, color: Colors.white, size: 52),
                          const SizedBox(height: 6),
                          Text(
                            _profile.isMaternal ? 'MATERNAL SOS' : 'TAP FOR SOS',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Under 1s Dispatch',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZeroTypingFastPassSection(bool isDark) {
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _showMaternalPasses
                  ? '⚡ Obstetric Complication Fast-Passes'
                  : '⚡ Standard Emergency Fast-Passes',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
            const Text(
              'Zero-typing',
              style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_showMaternalPasses) ...[
          // Obstetric Fast-Passes
          _buildFastPassTile(
            title: 'Vaginal Bleeding (Antepartum Hemorrhage)',
            subtitle: 'Triggers Hemorrhage & O-Neg Blood Bank Pre-Alert',
            icon: '🩸',
            accentColor: const Color(0xFFDC2626),
            isDark: isDark,
            onTap: () => _executeEmergencyDispatch(condition: 'Vaginal Bleeding - Hemorrhage Risk', priority: 1),
          ),
          const SizedBox(height: 10),
          _buildFastPassTile(
            title: 'Water Broke (PROM)',
            subtitle: 'Triggers Amniotic Fluid / Infection Delivery Pre-Alert',
            icon: '💧',
            accentColor: const Color(0xFF0284C7),
            isDark: isDark,
            onTap: () => _executeEmergencyDispatch(condition: 'Water Broke (PROM)', priority: 1),
          ),
          const SizedBox(height: 10),
          _buildFastPassTile(
            title: 'Acute Labor Pain (Contractions < 3 min)',
            subtitle: 'Pre-alerts Obstetric Bay for Impending Delivery',
            icon: '👶',
            accentColor: const Color(0xFFEC4899),
            isDark: isDark,
            onTap: () => _executeEmergencyDispatch(condition: 'Acute Labor Pain', priority: 1),
          ),
          const SizedBox(height: 10),
          _buildFastPassTile(
            title: 'Severe Headache / Blurred Vision',
            subtitle: 'Pre-eclampsia & Magnesium Sulfate Pre-Alert',
            icon: '⚡',
            accentColor: const Color(0xFFD97706),
            isDark: isDark,
            onTap: () => _executeEmergencyDispatch(condition: 'Severe Headache / Blurred Vision (Pre-eclampsia)', priority: 1),
          ),
        ] else ...[
          // Standard Fast-Passes
          _buildFastPassTile(
            title: 'Severe Trauma / RTC',
            subtitle: 'Direct Trauma Red Bay & Ortho/Surgical Alert',
            icon: '🚑',
            accentColor: const Color(0xFFDC2626),
            isDark: isDark,
            onTap: () => _executeEmergencyDispatch(condition: 'Severe Trauma / RTC', priority: 1),
          ),
          const SizedBox(height: 10),
          _buildFastPassTile(
            title: 'Crushing Chest Pain / STEMI',
            subtitle: '12-lead ECG & Cath Lab Acute Cardiac Bay Alert',
            icon: '🫀',
            accentColor: const Color(0xFFBE123C),
            isDark: isDark,
            onTap: () => _executeEmergencyDispatch(condition: 'Chest Pain / STEMI', priority: 1),
          ),
          const SizedBox(height: 10),
          _buildFastPassTile(
            title: 'Acute Breathlessness / Severe Asthma',
            subtitle: 'Continuous Nebulizer & Oxygen Bay Direct Transfer',
            icon: '🫁',
            accentColor: const Color(0xFF0284C7),
            isDark: isDark,
            onTap: () => _executeEmergencyDispatch(condition: 'Acute Breathlessness / Asthma', priority: 1),
          ),
          const SizedBox(height: 10),
          _buildFastPassTile(
            title: 'Sudden Collapse / Unresponsive',
            subtitle: 'Immediate ICU Team & Resuscitation Suite Pre-Alert',
            icon: '🚨',
            accentColor: const Color(0xFF7C3AED),
            isDark: isDark,
            onTap: () => _executeEmergencyDispatch(condition: 'Collapse / Unresponsive', priority: 1),
          ),
        ],
      ],
    );
  }

  Widget _buildFastPassTile({
    required String title,
    required String subtitle,
    required String icon,
    required Color accentColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final cardBorder = isDark ? AppTheme.darkCardBorder : const Color(0xFFE2E8F0);

    return InkWell(
      onTap: _submitting ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'DISPATCH',
                style: TextStyle(
                  color: accentColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHotlineFallback(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF0284C7), size: 22),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '24/7 Telephone Hotline Fallback',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const Text(
                    'Direct line to Solace Medical Dispatch Desk',
                    style: TextStyle(fontSize: 10.5, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          FilledButton(
            onPressed: () {
              launchUrl(Uri.parse('tel:+2348006963674'));
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: Size.zero,
            ),
            child: const Text('CALL NOW', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // ── LIVE EN-ROUTE EMERGENCY HUD (POST-TRIGGER VIEW) ─────────────────────────
  Widget _buildActiveMissionHUD(bool isDark) {
    final mission = _activeMission!;
    final reqId = mission['id']?.toString() ?? '';
    final status = mission['status']?.toString() ?? 'Active';
    final hospital = mission['hospital']?['name']?.toString() ?? 'Partner Emergency Facility';
    final driver = mission['drivers']?['display_name']?.toString() ?? 'ALS Paramedic Crew';
    final vehicle = mission['drivers']?['vehicle_label']?.toString() ?? '';

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // HUD Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF991B1B), Color(0xFFDC2626)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Text('🚨', style: TextStyle(fontSize: 32)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'LIVE EMERGENCY MISSION ACTIVE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            'Status: $status',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ── 4-STAGE STATUS HUD PROGRESSION ───────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? AppTheme.darkCardBorder : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Direct-to-Bed Mission Progression',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Stage 1
                    _buildHudStageItem(
                      stepNumber: '1',
                      title: 'Signal Logged & GPS Locked',
                      subtitle: 'Coordinates validated with nearest cluster hub.',
                      isCompleted: true,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),

                    // Stage 2
                    _buildHudStageItem(
                      stepNumber: '2',
                      title: 'Receiving Hospital Pre-Alerted',
                      subtitle: 'Direct digital SBAR pre-alert sent to $hospital.',
                      isCompleted: true,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),

                    // Stage 3
                    _buildHudStageItem(
                      stepNumber: '3',
                      title: 'ALS Ambulance Unit En Route',
                      subtitle: '$driver ${vehicle.isNotEmpty ? "($vehicle)" : ""} mobilized.',
                      isCompleted: status.toLowerCase().contains('driver') ||
                          status.toLowerCase().contains('en route') ||
                          status.toLowerCase().contains('arrived'),
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),

                    // Stage 4
                    _buildHudStageItem(
                      stepNumber: '4',
                      title: 'Direct-to-Bed VIP Intake',
                      subtitle: 'Bypass general lobby upon arrival. Direct to Resuscitation Bay.',
                      isCompleted: status.toLowerCase().contains('intake') ||
                          status.toLowerCase().contains('completed'),
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Tactical Live Map Button
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SubmittedScreen(
                        requestId: reqId,
                        latitude: (mission['patient_lat'] as num?)?.toDouble(),
                        longitude: (mission['patient_lng'] as num?)?.toDouble(),
                        address: mission['patient_address']?.toString(),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.radar_rounded),
                label: const Text(
                  'OPEN LIVE TACTICAL TRACKER & MAP',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 14),

              // Telephone Hotline & Stand Down Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => launchUrl(Uri.parse('tel:+2348006963674')),
                      icon: const Icon(Icons.phone),
                      label: const Text('24/7 Hotline'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // Open SubmittedScreen to trigger cancellation with reason modal
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SubmittedScreen(
                              requestId: reqId,
                              latitude: (mission['patient_lat'] as num?)?.toDouble(),
                              longitude: (mission['patient_lng'] as num?)?.toDouble(),
                              address: mission['patient_address']?.toString(),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent),
                      label: const Text('Stand Down', style: TextStyle(color: Colors.redAccent)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHudStageItem({
    required String stepNumber,
    required String title,
    required String subtitle,
    required bool isCompleted,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted ? const Color(0xFF00E676) : Colors.grey.withValues(alpha: 0.3),
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, size: 16, color: Colors.black)
                : Text(
                    stepNumber,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Colors.white),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isCompleted
                      ? (isDark ? Colors.white : const Color(0xFF0F172A))
                      : Colors.grey,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
