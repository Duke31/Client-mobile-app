import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/client_request_detail.dart';
import 'home_screen.dart';
import 'package:latlong2/latlong.dart';
import 'live_ambulance_tracking_screen.dart';

class SubmittedScreen extends StatefulWidget {
  final String? requestId;
  final double? latitude;
  final double? longitude;
  final String? address;
  final String? patientAddress;
  final VoidCallback? onReturnHome;

  const SubmittedScreen({
    super.key,
    this.requestId,
    this.latitude,
    this.longitude,
    this.address,
    this.patientAddress,
    this.onReturnHome,
  });

  @override
  State<SubmittedScreen> createState() => _SubmittedScreenState();
}

class _SubmittedScreenState extends State<SubmittedScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _requestId;
  String _currentStatus = 'Pending dispatch';
  String? _hospitalId;
  String? _hospitalName;
  RealtimeChannel? _statusBroadcastChannel;
  String? _hospitalAddress;
  String? _hospitalPhone;
  String? _driverName;
  String? _driverPhone;
  String? _vehicleLabel;
  String _actorRole = 'client';
  double? _patientLat;
  double? _patientLng;

  Timer? _pollTimer;
  StreamSubscription<List<Map<String, dynamic>>>? _realtimeSub;
  bool _isCancelling = false;

  late AnimationController _radarController;
  late Animation<double> _radarScale;
  late Animation<double> _radarOpacity;

  static const List<String> _orderedPhases = [
    'Pending dispatch',
    'Hospital confirmed',
    'Driver assigned',
    'En route to patient',
    'Arrived at scene',
    'Patient picked up',
    'En route to hospital',
    'Arrived / intake',
    'Completed',
  ];

  static const List<String> _phaseLabels = [
    'Triage & Broadcast',
    'Hospital ER Bay Allocated',
    'Paramedic Crew Mobilized',
    'Ambulance En Route',
    'Arrived at Patient',
    'Patient On Board',
    'En Route to Emergency Hospital',
    'Hospital Intake & Transfer',
    'Patient Care Handover Complete',
  ];

  int get _currentPhaseIndex {
    final status = _currentStatus.trim();
    for (int i = 0; i < _orderedPhases.length; i++) {
      if (status.toLowerCase() == _orderedPhases[i].toLowerCase()) return i;
    }
    if (status.toLowerCase().contains('hospital confirmed')) return 1;
    if (status.toLowerCase().contains('driver assigned')) return 2;
    if (status.toLowerCase().contains('en route to patient')) return 3;
    if (status.toLowerCase().contains('arrived at scene')) return 4;
    if (status.toLowerCase().contains('picked up')) return 5;
    if (status.toLowerCase().contains('en route to hospital')) return 6;
    if (status.toLowerCase().contains('intake')) return 7;
    if (status.toLowerCase().contains('complete')) return 8;
    return 0;
  }

  bool get _isCompleted =>
      _currentStatus.toLowerCase().contains('complete');

  bool get _isCancelled =>
      _currentStatus.toLowerCase().contains('cancel') ||
      _currentStatus.toLowerCase().contains('fail');

  bool get _canClientCancel {
    final s = _currentStatus.toLowerCase();
    return s.contains('pending') ||
        s.contains('hospital confirmed') ||
        s.contains('driver assigned');
  }

  bool get _canTrackLive {
    final s = _currentStatus.toLowerCase();
    return s.contains('driver assigned') ||
        s.contains('en route') ||
        s.contains('arrived') ||
        s.contains('picked up');
  }

  String get _shortId {
    final id = _requestId ?? '';
    return id.length > 8 ? id.substring(0, 8).toUpperCase() : id;
  }

  @override
  void initState() {
    super.initState();
    _requestId = widget.requestId;

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _radarScale = Tween<double>(begin: 0.9, end: 1.5).animate(
      CurvedAnimation(parent: _radarController, curve: Curves.easeOutCubic),
    );
    _radarOpacity = Tween<double>(begin: 0.75, end: 0.0).animate(
      CurvedAnimation(parent: _radarController, curve: Curves.easeOutCubic),
    );

    _patientLat = widget.latitude;
    _patientLng = widget.longitude;
    _fetchUserRole();

    if (_requestId != null && _requestId!.isNotEmpty) {
      _startStatusMonitoring(_requestId!);
    } else {
      _fetchActiveRequestId();
    }
  }

  @override
  void dispose() {
    _radarController.dispose();
    _stopMonitoring();
    try {
      _statusBroadcastChannel?.unsubscribe();
      _statusBroadcastChannel = null;
    } catch (_) {}
    super.dispose();
  }

  Future<void> _fetchUserRole() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final res = await _supabase
          .from('profiles')
          .select('role')
          .eq('user_id', uid)
          .maybeSingle();
      if (res != null && res['role'] != null && mounted) {
        setState(() {
          _actorRole = res['role'].toString();
        });
      }
    } catch (_) {}
  }

  void _stopMonitoring() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _realtimeSub?.cancel();
    _realtimeSub = null;
    try {
      _statusBroadcastChannel?.unsubscribe();
      _statusBroadcastChannel = null;
    } catch (_) {}
  }

  void _startStatusMonitoring(String reqId) {
    _refreshStatus(reqId);
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _refreshStatus(reqId);
    });

    _realtimeSub?.cancel();
    try {
      _realtimeSub = _supabase
          .from('emergency_requests')
          .stream(primaryKey: ['id'])
          .eq('id', reqId)
          .listen((data) {
            if (data.isNotEmpty && mounted) {
              final rec = data.first;
              final newStatus = rec['status']?.toString();
              final hid = rec['hospital_id']?.toString();
              if (newStatus != null && newStatus != _currentStatus) {
                _handleStatusChange(newStatus);
              }
              if (hid != null && hid.isNotEmpty) {
                _hospitalId = hid;
                if (_hospitalName == null) {
                  _fetchHospitalById(hid);
                }
              }
              _refreshStatus(reqId);
            }
          }, onError: (_) {});
    } catch (_) {}

    // Instant broadcast listener for hospital confirmation and dispatcher alerts
    try {
      _statusBroadcastChannel?.unsubscribe();
      _statusBroadcastChannel = _supabase.channel('request-status:$reqId')
        ..onBroadcast(
          event: 'hospital_assigned',
          callback: (payload) {
            final hName = payload['hospital_name']?.toString();
            final hAddr = payload['hospital_address']?.toString();
            final hId = payload['hospital_id']?.toString();
            final st = payload['status']?.toString();
            if (mounted) {
              setState(() {
                if (hId != null && hId.isNotEmpty) _hospitalId = hId;
                if (hName != null && hName.isNotEmpty) _hospitalName = hName;
                if (hAddr != null && hAddr.isNotEmpty) _hospitalAddress = hAddr;
                if (st != null && st.isNotEmpty) _currentStatus = st;
              });
            }
          },
        )
        ..subscribe();
    } catch (_) {}
  }

  void _handleStatusChange(String newStatus) {
    setState(() {
      _currentStatus = newStatus;
    });
    if (_isCompleted || _isCancelled) {
      _stopMonitoring();
      if (_isCancelled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Emergency request has been closed / cancelled by dispatch.'),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _fetchHospitalById(String hospitalId) async {
    if (hospitalId.isEmpty) return;
    _hospitalId = hospitalId;
    // 1. Direct Supabase query
    try {
      final h = await _supabase
          .from('hospitals')
          .select('id, name, address')
          .eq('id', hospitalId)
          .maybeSingle();
      if (h != null && mounted) {
        setState(() {
          _hospitalName = h['name']?.toString() ?? _hospitalName;
          _hospitalAddress = h['address']?.toString() ?? _hospitalAddress;
        });
        return;
      }
    } catch (_) {}

    // 2. Reliable Ops proxy fallback (bypasses any table RLS restriction)
    try {
      final url = Uri.parse('https://ops-dashboard-eta-ten.vercel.app/api/hospitals?id=$hospitalId');
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && mounted) {
          setState(() {
            _hospitalName = data['name']?.toString() ?? _hospitalName;
            _hospitalAddress = data['address']?.toString() ?? _hospitalAddress;
          });
          return;
        }
      }
    } catch (_) {}
  }

  Future<void> _refreshStatus(String reqId) async {
    if (reqId.isEmpty) return;
    Map<String, dynamic>? req;

    // 1) Preferred: SECURITY DEFINER RPC (bypasses hospital/driver RLS safely)
    req = await ClientRequestDetail.fetch(_supabase, reqId);

    // 2) Fallback: direct selects
    if (req == null) {
      try {
        req = await _supabase
            .from('emergency_requests')
            .select('*, hospital:hospitals(*), driver:drivers(*)')
            .eq('id', reqId)
            .maybeSingle();
      } catch (e) {
        debugPrint('Submitted rich select failed: $e');
      }
    }
    if (req == null) {
      try {
        req = await _supabase
            .from('emergency_requests')
            .select(
              'id, status, emergency_type, patient_address, patient_lat, patient_lng, '
              'hospital_id, driver_id, notes, priority, created_at, contact_phone',
            )
            .eq('id', reqId)
            .maybeSingle();
      } catch (e) {
        debugPrint('Submitted plain select failed: $e');
        return;
      }
    }

    if (req == null || !mounted) return;

    final newStatus = req['status']?.toString();
    if (newStatus != null && newStatus != _currentStatus) {
      _handleStatusChange(newStatus);
    }

    final plat = (req['patient_lat'] as num?)?.toDouble();
    final plng = (req['patient_lng'] as num?)?.toDouble();
    if (plat != null && plng != null && (plat != 0.0 || plng != 0.0)) {
      _patientLat = plat;
      _patientLng = plng;
    }

    final reqHid = req['hospital_id']?.toString();
    if (reqHid != null && reqHid.isNotEmpty) {
      _hospitalId = reqHid;
      if (_hospitalName == null || _hospitalName!.isEmpty) {
        _fetchHospitalById(reqHid);
      }
    }
    String? hName = _hospitalName;
    String? hAddr = _hospitalAddress;
    String? hPhone = _hospitalPhone;
    String? dName = _driverName;
    String? vLabel = _vehicleLabel;
    String? dPhone = _driverPhone;

    final hospital = req['hospital'];
    if (hospital is Map) {
      hName = hospital['name']?.toString() ?? hName;
      hAddr = hospital['address']?.toString() ?? hAddr;
      hPhone = hospital['intake_phone']?.toString() ??
          hospital['phone']?.toString() ??
          hPhone;
    }

    final driver = req['driver'];
    if (driver is Map) {
      dName = driver['display_name']?.toString() ??
          driver['full_name']?.toString() ??
          dName;
      vLabel = driver['vehicle_label']?.toString() ?? vLabel;
      dPhone = driver['phone']?.toString() ??
          driver['phone_number']?.toString() ??
          driver['contact_phone']?.toString() ??
          dPhone;
    }
    final reqDriverId = req['driver_id']?.toString();
    if (reqDriverId != null && reqDriverId.isNotEmpty && (dPhone == null || dPhone.isEmpty)) {
      try {
        final dRow = await _supabase
            .from('drivers')
            .select('id, display_name, vehicle_label, phone')
            .eq('id', reqDriverId)
            .maybeSingle();
        if (dRow != null) {
          dName = dRow['display_name']?.toString() ?? dName;
          vLabel = dRow['vehicle_label']?.toString() ?? vLabel;
          dPhone = dRow['phone']?.toString() ?? dPhone;
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _hospitalName = (hName != null && hName.trim().isNotEmpty) ? hName : _hospitalName;
      _hospitalAddress =
          (hAddr != null && hAddr.trim().isNotEmpty) ? hAddr : _hospitalAddress;
      _hospitalPhone =
          (hPhone != null && hPhone.trim().isNotEmpty) ? hPhone : _hospitalPhone;
      _driverName = (dName != null && dName.trim().isNotEmpty) ? dName : _driverName;
      _vehicleLabel =
          (vLabel != null && vLabel.trim().isNotEmpty) ? vLabel : _vehicleLabel;
      _driverPhone =
          (dPhone != null && dPhone.trim().isNotEmpty) ? dPhone : _driverPhone;
      if (newStatus != null) _currentStatus = newStatus;
    });
  }

  Future<void> _fetchActiveRequestId() async {
    try {
      final uid = _supabase.auth.currentUser?.id;
      if (uid == null) return;

      Map<String, dynamic>? res;
      try {
        res = await _supabase
            .from('emergency_requests')
            .select('id, status')
            .or('client_user_id.eq.$uid,reported_by_user_id.eq.$uid')
            .order('created_at', ascending: false)
            .limit(15)
            .maybeSingle();
      } catch (_) {
        res = null;
      }

      // Prefer non-terminal among recent rows
      if (res == null) {
        try {
          final list = await _supabase
              .from('emergency_requests')
              .select('id, status')
              .eq('client_user_id', uid)
              .order('created_at', ascending: false)
              .limit(15);
          for (final row in List<Map<String, dynamic>>.from(list as List)) {
            final st = row['status']?.toString() ?? '';
            if (!st.toLowerCase().contains('completed') &&
                !st.toLowerCase().contains('cancel')) {
              res = row;
              break;
            }
          }
        } catch (e) {
          debugPrint('fetchActiveRequestId fallback: $e');
        }
      } else {
        final st = res['status']?.toString() ?? '';
        if (st.toLowerCase().contains('completed') ||
            st.toLowerCase().contains('cancel')) {
          // maybeSingle got newest which is terminal — scan list
          try {
            final list = await _supabase
                .from('emergency_requests')
                .select('id, status')
                .eq('client_user_id', uid)
                .order('created_at', ascending: false)
                .limit(15);
            res = null;
            for (final row in List<Map<String, dynamic>>.from(list as List)) {
              final s = row['status']?.toString() ?? '';
              if (!s.toLowerCase().contains('completed') &&
                  !s.toLowerCase().contains('cancel')) {
                res = row;
                break;
              }
            }
          } catch (_) {}
        }
      }

      if (res != null && mounted) {
        final id = res['id']?.toString();
        setState(() {
          _requestId = id;
          if (res!['status'] != null) {
            _currentStatus = res['status'].toString();
          }
        });
        if (id != null) {
          _startStatusMonitoring(id);
        }
      }
    } catch (e) {
      debugPrint('fetchActiveRequestId error: $e');
    }
  }

  Future<void> _confirmAndCancelRequest() async {
    if (!_canClientCancel) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot cancel: Ambulance is already en route with patient.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF07193F) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Cancel Emergency Request?',
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Are you sure you want to cancel this emergency dispatch? Central medical dispatch and responding paramedics will stand down.',
            style: TextStyle(
              color: isDark ? Colors.white70 : const Color(0xFF475569),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'Keep Active',
                style: TextStyle(color: isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7)),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Yes, Cancel Request'),
            ),
          ],
        );
      },
    );

    if (shouldCancel == true && mounted) {
      await _executeCancelRpc();
    }
  }

  Future<void> _executeCancelRpc() async {
    final idToCancel = _requestId;
    if (idToCancel == null || idToCancel.isEmpty) return;
    setState(() => _isCancelling = true);
    try {
      await _supabase.rpc('transition_emergency_state', params: {
        'request_id': idToCancel,
        'new_state': 'Cancelled / failed',
        'actor_role': _actorRole,
      });
      if (!mounted) return;
      _returnHome();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCancelling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cancel error: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _openLiveTracking() {
    final id = _requestId;
    if (id == null) return;
    HapticFeedback.selectionClick();
    final lat = _patientLat ?? widget.latitude;
    final lng = _patientLng ?? widget.longitude;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LiveAmbulanceTrackingScreen(
          requestId: id,
          patientLocation: (lat != null && lng != null)
              ? LatLng(lat, lng)
              : const LatLng(0, 0),
          patientAddress: widget.address ?? widget.patientAddress ?? 'Scene Location',
        ),
      ),
    );
  }

  Future<void> _callNumber(String phone) async {
    HapticFeedback.heavyImpact();
    if (phone.trim().isEmpty) return;
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (clean.isEmpty) return;

    final uri = Uri(scheme: 'tel', path: clean);
    bool launched = false;
    try {
      // 1. Standard Android dialer invocation (platformDefault mode)
      launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (e) {
      debugPrint('Dialer platformDefault error: $e');
    }

    if (!launched) {
      try {
        // 2. Direct launch without mode constraint
        launched = await launchUrl(uri);
      } catch (e) {
        debugPrint('Dialer default error: $e');
      }
    }

    if (!launched) {
      try {
        // 3. Fallback with Uri.parse external
        final parsed = Uri.parse('tel:$clean');
        launched = await launchUrl(parsed, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('Dialer externalApplication error: $e');
      }
    }

    if (!launched && mounted) {
      // Direct clipboard copy and instant user notification
      await Clipboard.setData(ClipboardData(text: clean));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Dialer intent initiated: $clean (Number copied)'),
          backgroundColor: const Color(0xFF00E676),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _sendSms(String phone, String body) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('sms:$clean?body=${Uri.encodeComponent(body)}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _openWhatsApp(String phone, String body) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$clean?text=${Uri.encodeComponent(body)}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _returnHome() {
    if (widget.onReturnHome != null) {
      widget.onReturnHome!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      );
    }
  }

  String get _headlineText {
    final s = _currentStatus.toLowerCase();
    if (s.contains('pending')) return 'Broadcasting Emergency Call...';
    if (s.contains('hospital confirmed')) return 'Hospital Trauma Bay Reserved';
    if (s.contains('driver assigned')) return 'Ambulance Unit Assigned';
    if (s.contains('en route to patient')) return 'Ambulance En Route To You';
    if (s.contains('arrived at scene')) return 'Ambulance Arrived At Scene';
    if (s.contains('picked up')) return 'Patient On Board Ambulance';
    if (s.contains('en route to hospital')) return 'Transferring To Emergency ER';
    if (s.contains('intake')) return 'Hospital Triage & Transfer Active';
    if (s.contains('complete')) return 'Emergency Mission Complete';
    if (s.contains('cancel')) return 'Emergency Request Cancelled';
    return _currentStatus;
  }

  String get _descriptionText {
    final s = _currentStatus.toLowerCase();
    if (s.contains('pending')) {
      return 'Central dispatch is alerting rapid response fleet and reserving an ER bay.';
    }
    if (s.contains('hospital confirmed')) {
      final h = _hospitalName ?? 'Emergency Center';
      return '$h has confirmed ICU/triage readiness for your arrival.';
    }
    if (s.contains('driver assigned')) {
      final d = _driverName ?? 'Paramedic Unit';
      final v = _vehicleLabel != null ? ' ($_vehicleLabel)' : '';
      return '$d$v accepted dispatch and is activating siren & telemetry.';
    }
    if (s.contains('en route to patient')) {
      return 'Ambulance is navigating rapidly to your GPS coordinates. Stay on the line.';
    }
    if (s.contains('arrived at scene')) {
      return 'Paramedics have arrived at your location. Please signal response unit.';
    }
    if (s.contains('picked up')) {
      return 'Patient is safely on board ambulance receiving continuous clinical care.';
    }
    if (s.contains('en route to hospital')) {
      final h = _hospitalName ?? 'Hospital ER';
      return 'Ambulance en route to $h. Paramedics updating receiving doctors.';
    }
    if (s.contains('intake')) {
      return 'Handover to trauma doctors and triage team in progress.';
    }
    if (s.contains('complete')) {
      return 'Patient care transferred to medical team. Emergency run finished.';
    }
    if (s.contains('cancel')) {
      return 'This emergency dispatch request has been closed / cancelled.';
    }
    return 'Status: $_currentStatus';
  }

  @override
  Widget build(BuildContext context) {
    final isTerminal = _isCompleted || _isCancelled;
    final activePhase = _currentPhaseIndex;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final cardBorder = isDark ? AppTheme.darkCardBorder : const Color(0xFFCBD5E1);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF81D4FA) : const Color(0xFF0284C7);
    final textMuted = isDark ? Colors.white60 : const Color(0xFF64748B);
    final innerChipBg = isDark ? const Color(0xFF0D2559) : const Color(0xFFF1F5F9);

    return PopScope(
      canPop: isTerminal,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _returnHome();
        }
      },
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: cardColor,
          elevation: isDark ? 0 : 0.5,
          leadingWidth: 44,
          leading: Padding(
            padding: const EdgeInsets.only(left: 12.0),
            child: Image.asset(
              'assets/images/solace_icon.png',
              height: 28,
              width: 28,
              errorBuilder: (_, __, ___) => Icon(
                Icons.emergency_rounded,
                color: isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7),
                size: 26,
              ),
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'SOLACE RAPID DISPATCH',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 14.5,
                  letterSpacing: 1.0,
                ),
              ),
              Text(
                isTerminal ? 'Incident Summary' : 'Live Emergency Mission Desk',
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
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0D2559) : const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7),
                  width: 0.8,
                ),
              ),
              child: Text(
                '#$_shortId',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. BEACON / STATUS VISUAL
                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (!isTerminal)
                        AnimatedBuilder(
                          animation: _radarController,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _radarScale.value,
                              child: Container(
                                width: 104,
                                height: 104,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: (_canTrackLive
                                          ? (isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7))
                                          : const Color(0xFFFF334B))
                                      .withValues(alpha: _radarOpacity.value),
                                ),
                              ),
                            );
                          },
                        ),
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark ? const Color(0xFF07193F) : Colors.white,
                          border: Border.all(
                            color: isTerminal
                                ? (_isCompleted ? const Color(0xFF00E676) : Colors.redAccent)
                                : (_canTrackLive
                                    ? (isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7))
                                    : const Color(0xFFFF334B)),
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (isDark ? const Color(0xFF00D4FF) : Colors.black12)
                                  .withValues(alpha: 0.2),
                              blurRadius: 14,
                            ),
                          ],
                        ),
                        child: Icon(
                          isTerminal
                              ? (_isCompleted ? Icons.check_circle_rounded : Icons.cancel_outlined)
                              : (_canTrackLive ? Icons.directions_car_rounded : Icons.sensors_rounded),
                          size: 38,
                          color: isTerminal
                              ? (_isCompleted ? const Color(0xFF00E676) : Colors.redAccent)
                              : (_canTrackLive
                                  ? (isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7))
                                  : const Color(0xFFFF334B)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Headline & Description (theme-aware, crystal clear!)
                Text(
                  _headlineText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _descriptionText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textMuted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),

                // TERMINAL BANNER (If completed or cancelled)
                if (isTerminal) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _isCompleted
                          ? (isDark ? const Color(0xFF00E676).withValues(alpha: 0.15) : const Color(0xFFDCFCE7))
                          : (isDark ? Colors.red.withValues(alpha: 0.15) : const Color(0xFFFEE2E2)),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isCompleted
                            ? (isDark ? const Color(0xFF00E676) : const Color(0xFF16A34A))
                            : (isDark ? Colors.redAccent : const Color(0xFFDC2626)),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _isCompleted ? 'Patient Safely Admitted' : 'Emergency Request Closed / Cancelled',
                          style: TextStyle(
                            color: _isCompleted
                                ? (isDark ? const Color(0xFF00E676) : const Color(0xFF15803D))
                                : (isDark ? Colors.redAccent : const Color(0xFF991B1B)),
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isCompleted
                              ? 'Emergency medical handover is complete. View full records and submit feedback in the History tab.'
                              : 'This emergency dispatch request has been closed. Tap below to return to the SOS screen.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: textMuted, fontSize: 12, height: 1.35),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _isCompleted
                                ? (isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7))
                                : const Color(0xFFD32F2F),
                            foregroundColor: isDark ? const Color(0xFF061536) : Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _returnHome,
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: Text(
                            _isCompleted ? 'VIEW HISTORY & REVIEWS' : 'RETURN TO SOS DISPATCH',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // 2. SIMPLIFIED EMERGENCY STATUS CARD (Clean & Professional)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cardBorder),
                      boxShadow: isDark
                          ? []
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Request Reference',
                              style: TextStyle(
                                color: textMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '#$_shortId',
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(Icons.copy_rounded, size: 15, color: textSecondary),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Copy ID',
                              onPressed: () {
                                if (_requestId != null) {
                                  Clipboard.setData(ClipboardData(text: _requestId!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Request ID copied to clipboard'),
                                      duration: Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        Row(
                          children: [
                            Text(
                              'Current Lifecycle State',
                              style: TextStyle(
                                color: textMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: (_isCompleted
                                        ? const Color(0xFF00E676)
                                        : (_canTrackLive
                                            ? const Color(0xFF00D4FF)
                                            : const Color(0xFFFFA000)))
                                    .withValues(alpha: isDark ? 0.2 : 0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: (_isCompleted
                                          ? const Color(0xFF00E676)
                                          : (_canTrackLive
                                              ? const Color(0xFF00D4FF)
                                              : const Color(0xFFFFA000)))
                                      .withValues(alpha: isDark ? 0.5 : 0.4),
                                ),
                              ),
                              child: Text(
                                _currentStatus,
                                style: TextStyle(
                                  color: _isCompleted
                                      ? const Color(0xFF00E676)
                                      : (_canTrackLive
                                          ? (isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7))
                                          : const Color(0xFFE65100)),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 80,
                              child: Text(
                                'Location',
                                style: TextStyle(
                                  color: textMuted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.address ?? widget.patientAddress ?? 'Scene Location (GPS Locked)',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 3. RECEIVING HOSPITAL ER CARD
                  // Displays IMMEDIATELY once confirmed by dispatcher/admin
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: (_hospitalName != null || _hospitalId != null || _currentStatus.toLowerCase().contains('hospital confirmed'))
                            ? const Color(0xFF00ACC1)
                            : cardBorder,
                        width: (_hospitalName != null || _hospitalId != null) ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00ACC1).withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.local_hospital_rounded, color: Color(0xFF00ACC1), size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (_hospitalName != null || _hospitalId != null || _currentStatus.toLowerCase().contains('hospital confirmed'))
                                    ? 'RECEIVING HOSPITAL (CONFIRMED & RESERVED)'
                                    : 'RECEIVING HOSPITAL (MATCHING IN PROGRESS)',
                                style: TextStyle(
                                  color: isDark ? const Color(0xFF80DEEA) : const Color(0xFF00838F),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _hospitalName ??
                                    ((_hospitalId != null || _currentStatus.toLowerCase().contains('hospital confirmed'))
                                        ? 'Hospital ER Bay Reserved'
                                        : 'Matching Closest Verified Trauma Bay...'),
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_hospitalAddress != null && _hospitalAddress!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  _hospitalAddress!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: textMuted, fontSize: 11),
                                ),
                              ] else if (_hospitalName != null || _hospitalId != null || _currentStatus.toLowerCase().contains('hospital confirmed')) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Trauma Bay Allocated • Medical Team Standing By',
                                  style: TextStyle(
                                    color: isDark ? const Color(0xFF80DEEA) : const Color(0xFF00838F),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Hospital phone interaction and display removed as requested
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 4. RESPONDING AMBULANCE DRIVER CARD
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _driverName != null
                            ? (isDark ? const Color(0xFF00E676) : const Color(0xFF16A34A))
                            : cardBorder,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00E676).withValues(alpha: 0.18),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.directions_car_rounded, color: Color(0xFF00E676), size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ASSIGNED AMBULANCE RESPONDER',
                                    style: TextStyle(
                                      color: isDark ? const Color(0xFF81D4FA) : const Color(0xFF0284C7),
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  Text(
                                    _driverName ?? 'Locating Closest Paramedic Team...',
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_vehicleLabel != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: innerChipBg,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: cardBorder),
                                ),
                                child: Text(
                                  _vehicleLabel!,
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (_canTrackLive) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7),
                                foregroundColor: isDark ? const Color(0xFF061536) : Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _openLiveTracking,
                              icon: const Icon(Icons.radar_rounded, size: 18),
                              label: const Text(
                                'TRACK AMBULANCE RADAR LIVE',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5),
                              ),
                            ),
                          ),
                        ],
                        // Interactive Driver Card: allows patient or bystander to call assigned driver
                        if (_driverPhone != null && _driverPhone!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: innerChipBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF00E676).withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00E676).withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.phone_in_talk_rounded,
                                    size: 16,
                                    color: Color(0xFF00E676),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _callNumber(_driverPhone!),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'CALL ASSIGNED DRIVER',
                                          style: TextStyle(
                                            color: isDark ? const Color(0xFF81D4FA) : const Color(0xFF0284C7),
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.6,
                                          ),
                                        ),
                                        Text(
                                          _driverPhone!,
                                          style: const TextStyle(
                                            color: Color(0xFF00E676),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF00E676),
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    visualDensity: VisualDensity.compact,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () => _callNumber(_driverPhone!),
                                  icon: const Icon(Icons.call, size: 16),
                                  label: const Text(
                                    'Call Driver',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF25D366).withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: IconButton(
                                    icon: const Icon(Icons.chat_bubble_rounded, size: 18, color: Color(0xFF25D366)),
                                    tooltip: 'WhatsApp Driver',
                                    padding: const EdgeInsets.all(8),
                                    constraints: const BoxConstraints(),
                                    onPressed: () => _openWhatsApp(_driverPhone!, 'Solace EMS: Patient ready for pickup.'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (_driverName != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: innerChipBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: cardBorder),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.phone_in_talk_rounded, size: 15, color: Color(0xFF00E676)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Direct Ambulance Dispatch Channel Active',
                                    style: TextStyle(
                                      color: textMuted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 5. QUICK FIRST AID CARD (Only shown when waiting for ambulance!)
                  if (!_isCompleted && !_isCancelled)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.medical_services_rounded, color: Color(0xFFFF334B), size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'QUICK FIRST AID (WHILE WAITING FOR AMBULANCE)',
                              style: TextStyle(
                                color: isDark ? const Color(0xFF81D4FA) : const Color(0xFF0284C7),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildAidTip(
                          icon: Icons.air_rounded,
                          title: 'Airway & Recovery Position',
                          body: 'Keep airway open. If breathing but unconscious, gently roll onto their side. Never leave face-down.',
                          textPrimary: textPrimary,
                          textMuted: textMuted,
                        ),
                        const Divider(height: 16, thickness: 0.7),
                        _buildAidTip(
                          icon: Icons.healing_rounded,
                          title: 'Severe Bleeding Control',
                          body: 'Press a clean cloth firmly directly over wound. Maintain continuous pressure with hands.',
                          textPrimary: textPrimary,
                          textMuted: textMuted,
                        ),
                        const Divider(height: 16, thickness: 0.7),
                        _buildAidTip(
                          icon: Icons.favorite_rounded,
                          title: 'Chest Pain / Heart Distress',
                          body: 'Keep patient resting seated or half-upright. Loosen collar. Prevent any physical walking.',
                          textPrimary: textPrimary,
                          textMuted: textMuted,
                        ),
                        const Divider(height: 16, thickness: 0.7),
                        _buildAidTip(
                          icon: Icons.warning_rounded,
                          title: 'Crash / Spine Injury — Do Not Move',
                          body: 'Do NOT move or drag an accident patient unless immediate fire or explosion hazard exists.',
                          textPrimary: textPrimary,
                          textMuted: textMuted,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 6. CANCEL BUTTON
                  if (_canClientCancel)
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isCancelling ? null : _confirmAndCancelRequest,
                        icon: _isCancelling
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                              )
                            : const Icon(Icons.cancel_outlined, size: 18),
                        label: Text(
                          _isCancelling ? 'CANCELLING REQUEST...' : 'CANCEL EMERGENCY REQUEST',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAidTip({
    required IconData icon,
    required String title,
    required String body,
    required Color textPrimary,
    required Color textMuted,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF00D4FF), size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                body,
                style: TextStyle(
                  color: textMuted,
                  fontSize: 10.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}



