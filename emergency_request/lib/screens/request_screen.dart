import '../utils/error_sanitizer.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../maps/mapbox_geocoding.dart';
import '../maps/mapbox_map_view.dart';
import '../services/emergency_service.dart';
import '../services/emergency_sms_fallback.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import 'profile_screen.dart';
import 'submitted_screen.dart';
import '../models/member_profile.dart';

const LatLng kDefaultCenter = LatLng(6.5244, 3.3792);

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

  // Active mission tracking state
  Map<String, dynamic>? _activeMission;
  Timer? _activeMissionTimer;
  StreamSubscription? _realtimeSub;
  StreamSubscription<LocationFix>? _livePositionSub;

  // Cached profile data
  String? _profileName;
  String? _profilePhone;
  String? _profileAgeBand;
  String? _profileBloodGroup;
  String? _profileAllergies;
  String? _profileConditions;
  String? _profilePreferredHospital;
  String? _profileGenotype;
  int? _profileGestationalWeeks;
  String? _profileEdd;
  String? _profileGravidaPara;
  bool _profileIsMaternal = false;

  Future<void> triggerConditionDispatch(String condition, int priority) async {
    final fix = _fix ?? const LocationFix(latitude: 7.3775, longitude: 3.9470, accuracyMeters: 15);
    final intake = _IntakeData(
      condition: condition,
      priority: priority,
      ageBand: _profileAgeBand ?? '18-39',
      contactPhone: _profilePhone,
      notes: '1-Tap Fast-Pass Priority Dispatch: ' + condition,
    );
    await _executeEmergencyRequest(fix, intake);
  }

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _pulseScale = Tween<double>(begin: 1.0, end: 1.45).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOutQuad),
    );

    _pulseOpacity = Tween<double>(begin: 0.65, end: 0.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOutQuad),
    );

    _loadLocation();
    _startContinuousLocationFeed();
    _fetchProfileDefaults();
    _checkActiveMission();

    _activeMissionTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _checkActiveMission();
    });

    try {
      _realtimeSub = Supabase.instance.client
          .from('emergency_requests')
          .stream(primaryKey: ['id'])
          .listen((_) {
            _checkActiveMission();
          }, onError: (_) {});
    } catch (_) {}
  }

  void _startContinuousLocationFeed() {
    _livePositionSub?.cancel();
    try {
      _livePositionSub = _location.liveStream.listen((fix) {
        if (!mounted) return;
        final isFirst = _fix == null;
        final moved = isFirst ||
            Geolocator.distanceBetween(
                  _fix!.latitude,
                  _fix!.longitude,
                  fix.latitude,
                  fix.longitude,
                ) > 12;

        setState(() {
          _fix = fix;
          _loadingLocation = false;
        });

        if (isFirst) {
          try {
            _mapController.move(LatLng(fix.latitude, fix.longitude), 16.5);
          } catch (_) {}
        }

        if (moved) {
          _geocoding.reverseGeocode(
            latitude: fix.latitude,
            longitude: fix.longitude,
          ).then((addr) {
            if (mounted && addr.isNotEmpty) {
              setState(() => _address = addr);
            }
          });
        }
      }, onError: (Object e) {
        debugPrint('Continuous live GPS telemetry notice: $e');
      });
    } catch (e) {
      debugPrint('Failed to start continuous live GPS telemetry stream: $e');
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _activeMissionTimer?.cancel();
    _realtimeSub?.cancel();
    _livePositionSub?.cancel();
    _geocoding.dispose();
    super.dispose();
  }

  Future<void> _checkActiveMission() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || !mounted) return;
    try {
      final res = await Supabase.instance.client
          .from('emergency_requests')
          .select('id, status, emergency_type, patient_address, patient_lat, patient_lng, created_at, driver_id, drivers(display_name, phone, vehicle_label)')
          .or('client_user_id.eq.' + uid + ',reported_by_user_id.eq.' + uid)
          .neq('status', 'Completed').neq('status', 'Cancelled / failed').neq('status', 'completed').neq('status', 'cancelled')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _activeMission = res;
          if (res == null && _submitting) {
            _submitting = false;
          }
        });
      }
    } catch (_) {
      try {
        final res = await Supabase.instance.client
            .from('emergency_requests')
            .select('id, status, emergency_type, patient_address, patient_lat, patient_lng, created_at, driver_id')
            .or('client_user_id.eq.' + uid + ',reported_by_user_id.eq.' + uid)
            .neq('status', 'Completed').neq('status', 'Cancelled / failed').neq('status', 'completed').neq('status', 'cancelled')
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (mounted) {
          setState(() {
            _activeMission = res;
            if (res == null && _submitting) {
              _submitting = false;
            }
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _fetchProfileDefaults() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('full_name, phone, age_band, blood_group, allergies, chronic_conditions, preferred_hospital, profile_type, is_pregnant, gestational_weeks, edd, gravida_para, genotype')
          .eq('user_id', userId)
          .maybeSingle();
      if (res != null && mounted) {
        final hosp = res['preferred_hospital']?.toString();
        final cleanHosp = (hosp == null ||
                hosp.trim().isEmpty ||
                hosp.toLowerCase().contains('auto-select') ||
                hosp.toLowerCase().contains('none /') ||
                hosp.toLowerCase().contains('nearest capable'))
            ? null
            : hosp.trim();

        setState(() {
          _profileName = res['full_name']?.toString();
          _profilePhone = res['phone']?.toString();
          _profileAgeBand = res['age_band']?.toString();
          _profileBloodGroup = res['blood_group']?.toString();
          _profileAllergies = res['allergies']?.toString();
          _profileConditions = res['chronic_conditions']?.toString();
          _profilePreferredHospital = cleanHosp;
          _profileGenotype = res['genotype']?.toString();
          _profileGestationalWeeks = (res['gestational_weeks'] as num?)?.toInt();
          _profileEdd = res['edd']?.toString();
          _profileGravidaPara = res['gravida_para']?.toString();
          final pType = (res['profile_type']?.toString() ?? '').toLowerCase();
          _profileIsMaternal = res['is_pregnant'] == true || pType.contains('maternal');
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

    _geocoding.reverseGeocode(
      latitude: fix.latitude,
      longitude: fix.longitude,
    ).then((addr) {
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

  Future<void> _onMapTap(TapPosition _, LatLng point) async {
    HapticFeedback.lightImpact();
    await _applyFix(
      LocationFix(latitude: point.latitude, longitude: point.longitude),
    );
  }

  Future<void> _sendWhatsAppSos() async {
    if (_fix == null) return;
    final body = EmergencySmsFallback.buildBody(
      emergencyType: 'Medical Emergency',
      latitude: _fix!.latitude,
      longitude: _fix!.longitude,
      address: _address,
      callerPhone: _profilePhone,
    );
    final ok = await EmergencySmsFallback.openWhatsApp(body: body);
    if (!ok && mounted) {
      await _sendSmsSos();
    }
  }

  Future<void> _sendSmsSos() async {
    if (_fix == null) return;
    final body = EmergencySmsFallback.buildBody(
      emergencyType: 'Medical Emergency',
      latitude: _fix!.latitude,
      longitude: _fix!.longitude,
      address: _address,
      callerPhone: _profilePhone,
    );
    final launched = await EmergencySmsFallback.openNativeSms(body: body);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open messaging app. Please dial +2348133355709.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _openSosDispatchSheet() async {
    if (_fix == null || _submitting) return;

    HapticFeedback.heavyImpact();

    final isMaternal = _profileIsMaternal || (widget.initialProfile?.isMaternal ?? false);

    final intake = await showModalBottomSheet<_IntakeData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EmergencyConfirmSheet(
        defaultPhone: _profilePhone,
        defaultAgeBand: _profileAgeBand,
        bloodGroup: _profileBloodGroup,
        allergies: _profileAllergies,
        conditions: _profileConditions,
        currentAddress: _address,
        latitude: _fix!.latitude,
        longitude: _fix!.longitude,
        isMaternal: isMaternal,
        gestationalWeeks: _profileGestationalWeeks ?? widget.initialProfile?.computedWeeks,
        edd: _profileEdd ?? widget.initialProfile?.edd,
        gravidaPara: _profileGravidaPara ?? widget.initialProfile?.gravidaPara,
        preferredHospital: _profilePreferredHospital ?? widget.initialProfile?.preferredHospitalDisplay,
      ),
    );

    if (intake == null) return;
    await _executeEmergencyRequest(_fix!, intake);
  }

  Future<void> _executeEmergencyRequest(LocationFix fix, _IntakeData intake) async {
    setState(() => _submitting = true);
    final supabase = Supabase.instance.client;

    try {
      String? createdRequestId;
      final service = EmergencyService(
        supabase: supabase,
        geocoding: _geocoding,
      );

      final finalAddress = (intake.manualAddress != null && intake.manualAddress!.trim().isNotEmpty)
          ? intake.manualAddress!.trim()
          : (_address.isNotEmpty ? _address : 'GPS: ${fix.latitude}, ${fix.longitude}');

      final notesList = <String>[];
      if (intake.manualAddress != null && intake.manualAddress!.trim().isNotEmpty) {
        notesList.add('📍 Landmark: ${intake.manualAddress!.trim()}');
      }
      if (intake.notes != null && intake.notes!.trim().isNotEmpty) {
        notesList.add('Note: ${intake.notes!.trim()}');
      }
      if (_profilePreferredHospital != null && _profilePreferredHospital!.isNotEmpty) {
        notesList.add('[PREFERRED HOSPITAL: $_profilePreferredHospital]');
      }
      if (_profileIsMaternal ||
          intake.dbType == 'Obstetric' ||
          intake.condition.toLowerCase().contains('obstetric') ||
          intake.condition.toLowerCase().contains('labor') ||
          intake.condition.toLowerCase().contains('maternal')) {
        notesList.add('[OBSTETRIC CONDITION: ${intake.condition}]');
        final gWeeks = _profileGestationalWeeks != null
            ? '${_profileGestationalWeeks}w'
            : (widget.initialProfile?.computedWeeks != null
                ? '${widget.initialProfile!.computedWeeks}w'
                : 'Active Gestation');
        final eddStr = (_profileEdd != null && _profileEdd!.isNotEmpty)
            ? ' | EDD: $_profileEdd'
            : (widget.initialProfile?.edd != null ? ' | EDD: ${widget.initialProfile!.edd}' : '');
        final gpStr = (_profileGravidaPara != null && _profileGravidaPara!.isNotEmpty)
            ? ' | Parity: $_profileGravidaPara'
            : (widget.initialProfile?.gravidaPara != null ? ' | Parity: ${widget.initialProfile!.gravidaPara}' : '');
        final bgStr = (_profileBloodGroup != null && _profileBloodGroup != 'Unknown')
            ? ' | Blood: $_profileBloodGroup'
            : (widget.initialProfile?.bloodGroup != null ? ' | Blood: ${widget.initialProfile!.bloodGroup}' : '');
        final gtStr = (_profileGenotype != null && _profileGenotype!.isNotEmpty)
            ? ' | Genotype: $_profileGenotype'
            : '';
        notesList.add('[OBSTETRIC SBAR: Gestation: $gWeeks$eddStr$gpStr$bgStr$gtStr]');
      }
      if (_profileBloodGroup != null && _profileBloodGroup != 'Unknown') {
        notesList.add('Blood: $_profileBloodGroup');
      }
      if (_profileAllergies != null && _profileAllergies!.trim().isNotEmpty) {
        notesList.add('Allergies: $_profileAllergies');
      }
      if (_profileConditions != null && _profileConditions!.trim().isNotEmpty) {
        notesList.add('Conditions: $_profileConditions');
      }
      if (intake.ageBand.isNotEmpty && intake.ageBand != 'unknown') {
        notesList.add('Patient Age: ${intake.ageBand} yrs');
      }

      final assembledNotes = notesList.isNotEmpty ? notesList.join(' | ') : '';

      final mappedDbType = intake.dbType ?? (
        _profileIsMaternal || intake.condition.toLowerCase().contains('labor') || intake.condition.toLowerCase().contains('obstetric')
          ? 'Obstetric'
          : 'Other'
      );

      final rpcResult = await service.createRequest(
        latitude: fix.latitude,
        longitude: fix.longitude,
        address: finalAddress,
        emergencyType: mappedDbType,
        ageBand: intake.ageBand,
        contactPhone: intake.contactPhone ?? '',
        notes: assembledNotes,
        priority: intake.priority,
      );

      if (rpcResult is Map && rpcResult['id'] != null) {
        createdRequestId = rpcResult['id'] as String;
      }

      if (!mounted) return;

      setState(() => _submitting = false);

      if (widget.onEmergencyCreated != null && createdRequestId != null) {
        try {
          (widget.onEmergencyCreated as dynamic)(createdRequestId, finalAddress, fix.latitude, fix.longitude);
        } catch (_) {
          (widget.onEmergencyCreated as dynamic)(createdRequestId, finalAddress);
        }
      } else {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SubmittedScreen(
              requestId: createdRequestId,
              latitude: fix.latitude,
              longitude: fix.longitude,
              address: finalAddress,
            ),
          ),
        );
      }
    } on EmergencyNetworkException {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        
      });
      await _showOfflineFallbackSheet(fix, intake);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final looksNetwork = msg.contains('SocketException') ||
          msg.contains('Failed host lookup') ||
          msg.contains('Network') ||
          msg.contains('timed out') ||
          msg.contains('Timeout');
      setState(() {
        _submitting = false;
        if (looksNetwork) {
          
        }
      });
      if (looksNetwork) {
        await _showOfflineFallbackSheet(fix, intake);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorSanitizer.sanitize(e, fallback: 'Could not submit request. Please try again.')),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showOfflineFallbackSheet(
    LocationFix fix,
    _IntakeData intake,
  ) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF07193F),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: Color(0xFF00D4FF), width: 1.5),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.wifi_off_rounded, color: Colors.amber, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Dispatch Server Offline',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Data network is weak. Transmit via WhatsApp or SMS directly to Solace Central Operations Desk (+2348133355709).',
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final body = EmergencySmsFallback.buildBody(
                    emergencyType: intake.condition,
                    latitude: fix.latitude,
                    longitude: fix.longitude,
                    address: _address,
                    callerPhone: intake.contactPhone,
                  );
                  await EmergencySmsFallback.openWhatsApp(body: body);
                },
                icon: const Icon(Icons.chat_bubble_rounded),
                label: const Text(
                  'Send via WhatsApp (+2348133355709)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00D4FF),
                  side: const BorderSide(color: Color(0xFF00D4FF)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final smsBody = EmergencySmsFallback.buildBody(
                    emergencyType: intake.condition,
                    latitude: fix.latitude,
                    longitude: fix.longitude,
                    address: _address,
                    callerPhone: intake.contactPhone,
                  );
                  await EmergencySmsFallback.openNativeSms(body: smsBody);
                },
                icon: const Icon(Icons.sms_outlined),
                label: const Text(
                  'Transmit via SMS (+2348133355709)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_activeMission == null && _submitting) {
      _submitting = false;
    }
    final hasActiveMission = _activeMission != null;
    final accuracy = _fix?.accuracyMeters;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final cardBorder = isDark ? AppTheme.darkCardBorder : const Color(0xFFCBD5E1);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF81D4FA) : const Color(0xFF0284C7);
    final textMuted = isDark ? Colors.white60 : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: isDark ? 0 : 0.5,
        centerTitle: false,
        leadingWidth: 44,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12.0),
          child: Image.asset(
            'assets/images/solace_icon.png',
            height: 28,
            width: 28,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.emergency_rounded,
              color: Color(0xFF00D4FF),
              size: 26,
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'SOLACE RAPID EMS',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: 1.0,
              ),
            ),
            Text(
              '24/7 Emergency Network',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textSecondary,
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          // Medical ID / Blood Group Badge (Compact & No Overlap)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ActionChip(
              avatar: const Icon(
                Icons.medical_information_rounded,
                size: 14,
                color: Color(0xFF00D4FF),
              ),
              label: Text(
                _profileBloodGroup != null &&
                        _profileBloodGroup != 'Unknown' &&
                        _profileBloodGroup!.isNotEmpty
                    ? '🩸 $_profileBloodGroup'
                    : 'Medical ID',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0369A1),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: isDark ? const Color(0xFF0D2559) : const Color(0xFFE0F2FE),
              side: BorderSide(color: isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7), width: 0.8),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ProfileScreen(isStandalone: true)),
                );
                _fetchProfileDefaults();
              },
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // 1. ACTIVE MISSION BANNER (If unit is already responding)
              if (hasActiveMission)
                InkWell(
                  onTap: () {
                    final reqId = _activeMission!['id'] as String;
                    final addr = _activeMission!['patient_address'] as String?;
                    if (widget.onEmergencyCreated != null) {
                      widget.onEmergencyCreated!(reqId, addr ?? '');
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SubmittedScreen(
                            requestId: reqId,
                            address: addr,
                          ),
                        ),
                      );
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.red.shade900,
                          const Color(0xFF07193F),
                        ],
                      ),
                      border: const Border(
                        bottom: BorderSide(color: Color(0xFFFF334B), width: 1.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.sensors_rounded, color: Color(0xFF00D4FF), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '🚨 AMBULANCE EN ROUTE • ${_activeMission!['status']?.toString().toUpperCase()}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                'Unit: ${_activeMission!['drivers']?['vehicle_label'] ?? 'Assigned Medic'} • Tap to Track Live',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF80D8FF),
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 12),
                      ],
                    ),
                  ),
                ),

              // 2. INTERACTIVE MAP SECTION
              Expanded(
                child: Stack(
                  children: [
                    MapboxMapView.patientLocation(
                      latitude: _fix?.latitude ?? kDefaultCenter.latitude,
                      longitude: _fix?.longitude ?? kDefaultCenter.longitude,
                      zoom: 16.5,
                      interactive: false,
                      mapController: _mapController,
                    ),

                    // Live GPS Accuracy Tag (Top Left)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF07193F).withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: accuracy != null && accuracy <= 25
                                ? const Color(0xFF00E676)
                                : const Color(0xFF00D4FF),
                            width: 1.1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              accuracy != null && accuracy <= 25
                                  ? Icons.my_location_rounded
                                  : Icons.gps_fixed_rounded,
                              size: 13,
                              color: accuracy != null && accuracy <= 25
                                  ? const Color(0xFF00E676)
                                  : const Color(0xFF00D4FF),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              accuracy != null
                                  ? 'GPS Locked ±${accuracy.round()}m'
                                  : 'Acquiring GPS...',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Recenter GPS Button (Top Right)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'recenter_gps',
                        backgroundColor: const Color(0xFF07193F),
                        foregroundColor: const Color(0xFF00D4FF),
                        elevation: 4,
                        tooltip: 'Recenter GPS',
                        onPressed: _loadLocation,
                        child: _loadingLocation
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF00D4FF),
                                ),
                              )
                            : const Icon(Icons.near_me_rounded, size: 19),
                      ),
                    ),

                    // Address & Landmark Card over Map
                    Positioned(
                      bottom: 12,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF07193F).withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF1E3A8A), width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.pin_drop_rounded,
                              color: Color(0xFF00D4FF),
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: const [
                                      Text(
                                        'PICKUP DESTINATION',
                                        style: TextStyle(
                                          color: Color(0xFF81D4FA),
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                      Spacer(),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: const [
                                          Icon(Icons.lock_rounded, size: 10, color: Color(0xFF00E676)),
                                          SizedBox(width: 3),
                                          Text(
                                            'GPS Locked to Location',
                                            style: TextStyle(
                                              color: Color(0xFF00E676),
                                              fontSize: 9,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _address.isNotEmpty
                                        ? _address
                                        : 'Locating street address...',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 3. TACTICAL 1-TAP EMERGENCY SOS CONSOLE (NO HORIZONTAL CHIPS!)
              Container(
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkBg : Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 10,
                      offset: Offset(0, -3),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Network & Dispatch Status
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D2559),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1E3A8A)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.verified_user_rounded, color: Color(0xFF00E676), size: 14),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'SOLACE RAPID RESPONSE • 24/7 EMS NETWORK ACTIVE',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Color(0xFFB0BEC5),
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // COMMANDING 1-TAP EMERGENCY SOS BUTTON
                    SizedBox(
                      height: 80,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Pulsing radar glow
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _pulseScale.value,
                                child: Container(
                                  width: double.infinity,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(32),
                                    color: const Color(0xFFFF334B).withValues(
                                      alpha: _pulseOpacity.value,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                          // Main Action Button
                          SizedBox(
                            width: double.infinity,
                            height: 64,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFD32F2F),
                                foregroundColor: Colors.white,
                                elevation: 8,
                                shadowColor: const Color(0xFFFF334B).withValues(alpha: 0.6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(32),
                                  side: const BorderSide(
                                    color: Color(0xFFFF8A80),
                                    width: 2.0,
                                  ),
                                ),
                              ),
                              onPressed: _submitting ? null : _openSosDispatchSheet,
                              child: _submitting
                                  ? const SizedBox(
                                      width: 26,
                                      height: 26,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 3,
                                      ),
                                    )
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.emergency_rounded, size: 28),
                                        const SizedBox(width: 10),
                                        Flexible(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _profileIsMaternal
                                                    ? 'DISPATCH OBSTETRIC AMBULANCE'
                                                    : 'TAP FOR EMERGENCY SOS',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 14.5,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 0.8,
                                                ),
                                              ),
                                              Text(
                                                _profileIsMaternal
                                                    ? 'Priority L&D Bed • Theater Pre-Alert • En-route Medic'
                                                    : 'Instant Ambulance • Medic Crew • Hospital Bed',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Colors.white.withValues(alpha: 0.85),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Quick WhatsApp & SMS Fallback Bar (Clean High-Contrast Chips)
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF25D366).withValues(alpha: 0.12)
                                  : const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF25D366).withValues(alpha: 0.3)
                                    : const Color(0xFF86EFAC),
                              ),
                            ),
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: isDark
                                    ? const Color(0xFF25D366)
                                    : const Color(0xFF15803D),
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                              ),
                              onPressed: _sendWhatsAppSos,
                              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                              label: const Text(
                                'WhatsApp (+2348133355709)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF00D4FF).withValues(alpha: 0.12)
                                  : const Color(0xFFE0F2FE),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF00D4FF).withValues(alpha: 0.3)
                                    : const Color(0xFF7DD3FC),
                              ),
                            ),
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: isDark
                                    ? const Color(0xFF00D4FF)
                                    : const Color(0xFF0369A1),
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                              ),
                              onPressed: _sendSmsSos,
                              icon: const Icon(Icons.sms_rounded, size: 15),
                              label: const Text(
                                'SMS (+2348133355709)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Submitting Overlay
          if (_submitting)
            Container(
              color: Colors.black.withValues(alpha: 0.8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF07193F),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF00D4FF), width: 1.5),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: CircularProgressIndicator(
                          strokeWidth: 3.5,
                          color: Color(0xFF00D4FF),
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Dispatching Nearest Unit...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Broadcasting GPS coordinates to Solace response fleet',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
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
}

class _IntakeData {
  final String condition;
  final String? dbType;
  final String ageBand;
  final String? contactPhone;
  final String? manualAddress;
  final String? notes;
  final int priority;

  const _IntakeData({
    required this.condition,
    this.dbType,
    this.ageBand = 'unknown',
    this.contactPhone,
    this.manualAddress,
    this.notes,
    this.priority = 1,
  });
}

class _EmergencyConfirmSheet extends StatefulWidget {
  final String? defaultPhone;
  final String? defaultAgeBand;
  final String? bloodGroup;
  final String? allergies;
  final String? conditions;
  final String currentAddress;
  final double latitude;
  final double longitude;
  final bool isMaternal;
  final int? gestationalWeeks;
  final String? edd;
  final String? gravidaPara;
  final String? preferredHospital;

  const _EmergencyConfirmSheet({
    this.defaultPhone,
    this.defaultAgeBand,
    this.bloodGroup,
    this.allergies,
    this.conditions,
    required this.currentAddress,
    required this.latitude,
    required this.longitude,
    this.isMaternal = false,
    this.gestationalWeeks,
    this.edd,
    this.gravidaPara,
    this.preferredHospital,
  });

  @override
  State<_EmergencyConfirmSheet> createState() => _EmergencyConfirmSheetState();
}

class _EmergencyConfirmSheetState extends State<_EmergencyConfirmSheet> {
  late final TextEditingController _phoneController;
  final _landmarkController = TextEditingController();
  final _notesController = TextEditingController();

  String _selectedCondition = 'Accident';
  String _selectedAgeBand = '18-39';
  int _priority = 1;

  static const List<Map<String, String>> _ageBandOptions = [
    {'value': '0-1', 'label': '0-1 yr (Infant)'},
    {'value': '2-12', 'label': '2-12 yrs (Child)'},
    {'value': '13-17', 'label': '13-17 yrs (Teen)'},
    {'value': '18-39', 'label': '18-39 yrs (Adult)'},
    {'value': '40-64', 'label': '40-64 yrs (Mature)'},
    {'value': '65+', 'label': '65+ yrs (Senior)'},
  ];

  List<Map<String, String>> get _effectiveAgeBandOptions {
    if (widget.isMaternal) {
      return const [
        {'value': '18-39', 'label': '18-39 yrs (Adult Mother)'},
        {'value': '13-17', 'label': '13-17 yrs (Adolescent)'},
        {'value': '40-64', 'label': '40-64 yrs (Mature)'},
      ];
    }
    return _ageBandOptions;
  }

  static const List<Map<String, dynamic>> _maternalConditions = [
    {
      'label': 'Active Labor / PROM',
      'title': 'Water Broke / Labor',
      'icon': Icons.water_drop_rounded,
      'color': Color(0xFFE11D48),
      'priority': 1,
      'dbType': 'Obstetric',
    },
    {
      'label': 'Vaginal Bleeding',
      'title': 'Severe Bleeding',
      'icon': Icons.bloodtype_rounded,
      'color': Color(0xFFDC2626),
      'priority': 1,
      'dbType': 'Obstetric',
    },
    {
      'label': 'Pre-eclampsia / Fits',
      'title': 'Pre-eclampsia / Fits',
      'icon': Icons.warning_amber_rounded,
      'color': Color(0xFFEA580C),
      'priority': 1,
      'dbType': 'Obstetric',
    },
    {
      'label': 'Fetal Distress',
      'title': 'Fetal Distress',
      'icon': Icons.favorite_border_rounded,
      'color': Color(0xFFD97706),
      'priority': 1,
      'dbType': 'Obstetric',
    },
    {
      'label': 'Severe Pelvic Pain',
      'title': 'Severe Pelvic Pain',
      'icon': Icons.healing_rounded,
      'color': Color(0xFFC026D3),
      'priority': 1,
      'dbType': 'Obstetric',
    },
    {
      'label': 'Imminent Delivery',
      'title': 'Imminent Delivery',
      'icon': Icons.emergency_rounded,
      'color': Color(0xFFB91C1C),
      'priority': 1,
      'dbType': 'Obstetric',
    },
    {
      'label': 'Other Emergency',
      'title': 'Other Medical Event',
      'icon': Icons.medical_services_rounded,
      'color': Color(0xFF2563EB),
      'priority': 2,
      'dbType': 'Other',
    },
  ];

  static const List<Map<String, dynamic>> _standardConditions = [
    {
      'label': 'Accident',
      'title': 'Road Accident',
      'icon': Icons.car_crash_rounded,
      'color': Color(0xFFFB8C00),
      'priority': 1,
      'dbType': 'Trauma',
    },
    {
      'label': 'Cardiac',
      'title': 'Chest Pain / Heart',
      'icon': Icons.favorite_rounded,
      'color': Color(0xFFE53935),
      'priority': 1,
      'dbType': 'Cardiac',
    },
    {
      'label': 'Trauma',
      'title': 'Severe Bleeding',
      'icon': Icons.healing_rounded,
      'color': Color(0xFFD81B60),
      'priority': 1,
      'dbType': 'Trauma',
    },
    {
      'label': 'Respiratory',
      'title': 'Breathing Distress',
      'icon': Icons.air_rounded,
      'color': Color(0xFF00ACC1),
      'priority': 1,
      'dbType': 'Respiratory',
    },
    {
      'label': 'Stroke',
      'title': 'Stroke / Collapse',
      'icon': Icons.psychology_rounded,
      'color': Color(0xFF8E24AA),
      'priority': 1,
      'dbType': 'Stroke',
    },
    {
      'label': 'Other',
      'title': 'General Emergency',
      'icon': Icons.medical_services_rounded,
      'color': Color(0xFF1E88E5),
      'priority': 2,
      'dbType': 'Other',
    },
  ];

  List<Map<String, dynamic>> get _conditionsList =>
      widget.isMaternal ? _maternalConditions : _standardConditions;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.defaultPhone ?? '');
    if (widget.isMaternal) {
      _selectedCondition = 'Active Labor / PROM';
      _priority = 1;
      _selectedAgeBand = '18-39';
    } else {
      _selectedCondition = 'Accident';
      _priority = 1;
      if (widget.defaultAgeBand != null && widget.defaultAgeBand!.trim().isNotEmpty) {
        _selectedAgeBand = widget.defaultAgeBand!.trim();
      }
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _landmarkController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _confirm() {
    HapticFeedback.heavyImpact();
    final match = _conditionsList.firstWhere(
      (c) => c['label'] == _selectedCondition,
      orElse: () => _conditionsList.first,
    );
    final dbType = match['dbType'] as String? ?? (widget.isMaternal ? 'Obstetric' : 'Other');
    final p = match['priority'] as int? ?? _priority;

    Navigator.of(context).pop(
      _IntakeData(
        condition: _selectedCondition,
        dbType: dbType,
        ageBand: _selectedAgeBand,
        contactPhone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
        manualAddress: _landmarkController.text.trim().isNotEmpty ? _landmarkController.text.trim() : null,
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
        priority: p,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF07193F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(
          top: BorderSide(color: Color(0xFF00D4FF), width: 1.5),
        ),
      ),
      padding: EdgeInsets.fromLTRB(18, 14, 18, 18 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4.5,
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: widget.isMaternal ? const Color(0xFFE11D48).withOpacity(0.2) : Colors.red.shade900.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.isMaternal ? Icons.pregnant_woman_rounded : Icons.emergency_rounded,
                    color: widget.isMaternal ? const Color(0xFFFF4081) : Colors.redAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isMaternal ? 'Maternal Obstetric Emergency Desk' : 'Instant Emergency Dispatch',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        widget.isMaternal
                            ? 'Priority L&D Direct-to-Bed Intake • Theater Standby Alert'
                            : 'Select condition & confirm pickup landmark for crew',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (widget.isMaternal) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE11D48).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE11D48).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_hospital_rounded, color: Color(0xFFFF8A65), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Assigned L&D Facility: ${widget.preferredHospital ?? "Nearest Capable Obstetric Center"}',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),

            // Continuous Live Satellite Telemetry & Verified Address Summary
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D2559),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E3A8A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'CONTINUOUS LIVE SATELLITE GPS',
                        style: TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${widget.latitude.toStringAsFixed(4)}, ${widget.longitude.toStringAsFixed(4)}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 9.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded, color: Color(0xFF00D4FF), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.currentAddress.isNotEmpty
                              ? widget.currentAddress
                              : 'Resolving precise street & landmark telemetry...',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Emergency Types: Balanced 2-Column Grid (All visible at once!)
            Text(
              widget.isMaternal ? 'SELECT OBSTETRIC EMERGENCY CONDITION' : 'SELECT EMERGENCY CONDITION',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),

            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 2.7,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _conditionsList.length,
              itemBuilder: (ctx, idx) {
                final c = _conditionsList[idx];
                final label = c['label'] as String;
                final title = c['title'] as String;
                final isSel = label == _selectedCondition;
                final color = c['color'] as Color;

                return InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedCondition = label;
                      _priority = c['priority'] as int;
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSel ? color.withValues(alpha: 0.25) : const Color(0xFF0D2559),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSel ? color : Colors.white12,
                        width: isSel ? 1.6 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          c['icon'] as IconData,
                          size: 18,
                          color: isSel ? Colors.white : color,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isSel ? Colors.white : Colors.white70,
                              fontSize: 10.5,
                              height: 1.15,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 14),

            // Patient Age Selection
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'PATIENT AGE CATEGORY',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  _selectedAgeBand == 'unknown' ? 'Not specified' : '$_selectedAgeBand yrs',
                  style: const TextStyle(
                    color: Color(0xFF00D4FF),
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _effectiveAgeBandOptions.map((opt) {
                  final val = opt['value']!;
                  final lbl = opt['label']!;
                  final isSel = _selectedAgeBand == val;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedAgeBand = val);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: isSel
                              ? const Color(0xFF00D4FF).withValues(alpha: 0.25)
                              : const Color(0xFF0D2559),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSel ? const Color(0xFF00D4FF) : Colors.white12,
                            width: isSel ? 1.5 : 1.0,
                          ),
                        ),
                        child: Text(
                          lbl,
                          style: TextStyle(
                            color: isSel ? Colors.white : Colors.white70,
                            fontSize: 11,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 14),

            // Landmark Field
            TextField(
              controller: _landmarkController,
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0D2559),
                labelText: 'Landmark, Estate Gate, Compound or Junction',
                labelStyle: const TextStyle(color: Colors.white60, fontSize: 11.5),
                hintText: 'e.g. Near Total filling station, blue gate opposite pharmacy',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                prefixIcon: const Icon(Icons.place_outlined, color: Color(0xFF00D4FF), size: 18),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Callback Phone Field
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0D2559),
                labelText: 'Callback Phone Number (for Driver & Dispatcher)',
                labelStyle: const TextStyle(color: Colors.white60, fontSize: 11.5),
                hintText: 'e.g. 0803 123 4567',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                prefixIcon: const Icon(Icons.phone_outlined, color: Color(0xFF00D4FF), size: 18),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Brief Notes Field
            TextField(
              controller: _notesController,
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
              maxLines: 2,
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0D2559),
                labelText: 'Patient condition / Access note (Optional)',
                labelStyle: const TextStyle(color: Colors.white60, fontSize: 11.5),
                hintText: 'e.g. Patient unconscious / gate security informed',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                prefixIcon: const Icon(Icons.notes_rounded, color: Color(0xFF00D4FF), size: 18),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            if (widget.bloodGroup != null && widget.bloodGroup != 'Unknown') ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade400.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bloodtype_rounded, color: Colors.redAccent, size: 15),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Attached: Blood Group ${MemberProfile.sanitizeBloodGroup(widget.bloodGroup)}' +
                            (MemberProfile.sanitizeBloodGroup(widget.bloodGroup).contains('-')
                                ? ' (Rare Rh-Negative Reserve)'
                                : ' (Standard Reserve)'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Confirm & Dispatch Action Button
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD32F2F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFFFF5252), width: 1.5),
                  ),
                ),
                onPressed: _confirm,
                icon: const Icon(Icons.emergency_rounded, size: 22),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    widget.isMaternal
                        ? 'CONFIRM OBSTETRIC AMBULANCE DISPATCH'
                        : 'CONFIRM & DISPATCH AMBULANCE NOW',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
