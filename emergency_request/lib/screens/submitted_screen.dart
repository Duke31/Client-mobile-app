import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
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

class _SubmittedScreenState extends State<SubmittedScreen> with SingleTickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _requestId;
  String _currentStatus = 'Pending dispatch';
  String? _hospitalName;
  String? _hospitalAddress;
  String? _hospitalPhone;
  String? _driverName;
  String? _driverPhone;
  String? _vehicleLabel;
  String _actorRole = 'client';

  Timer? _pollTimer;
  StreamSubscription<List<Map<String, dynamic>>>? _realtimeSub;
  bool _isCancelling = false;

  late AnimationController _radarController;
  late Animation<double> _radarScale;
  late Animation<double> _radarOpacity;

  bool get _isCompleted => _currentStatus.toLowerCase().contains('complete');
  bool get _isCancelled => _currentStatus.toLowerCase().contains('cancel') || _currentStatus.toLowerCase().contains('fail');
  String get _shortId => _requestId != null && _requestId!.length > 8 ? _requestId!.substring(0, 8).toUpperCase() : (_requestId ?? 'PENDING');

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
    _radarScale = Tween<double>(begin: 0.8, end: 1.6).animate(CurvedAnimation(parent: _radarController, curve: Curves.easeOut));
    _radarOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(CurvedAnimation(parent: _radarController, curve: Curves.easeOut));

    if (widget.requestId != null) {
      _requestId = widget.requestId;
      _startStatusMonitoring();
    } else {
      _fetchActiveRequestId();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _realtimeSub?.cancel();
    _radarController.dispose();
    super.dispose();
  }

  Future<void> _fetchActiveRequestId() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final res = await _supabase
          .from('emergency_requests')
          .select('id, status')
          .eq('client_user_id', uid)
          .neq('status', 'Completed')
          .neq('status', 'Cancelled / failed')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (res != null && mounted) {
        setState(() {
          _requestId = res['id']?.toString();
          _currentStatus = res['status']?.toString() ?? 'Pending dispatch';
        });
        _startStatusMonitoring();
      }
    } catch (_) {}
  }

  void _startStatusMonitoring() {
    if (_requestId == null) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchStatus());
    try {
      _realtimeSub = _supabase
          .from('emergency_requests')
          .stream(primaryKey: ['id'])
          .eq('id', _requestId!)
          .listen((data) {
            if (data.isNotEmpty) {
              _updateStateFromDb(data.first);
            }
          });
    } catch (_) {}
    _fetchStatus();
  }

  Future<void> _fetchStatus() async {
    if (_requestId == null) return;
    try {
      final data = await _supabase
          .from('emergency_requests')
          .select('*, hospital:hospitals(name, address, phone), driver:drivers(display_name, full_name, phone, phone_number, vehicle_label)')
          .eq('id', _requestId!)
          .maybeSingle();
      if (data != null && mounted) _updateStateFromDb(data);
    } catch (_) {}
  }

  void _updateStateFromDb(Map<String, dynamic> data) {
    if (!mounted) return;
    setState(() {
      _currentStatus = data['status']?.toString() ?? _currentStatus;
      if (data['hospital'] != null) {
        _hospitalName = data['hospital']['name']?.toString();
        _hospitalAddress = data['hospital']['address']?.toString();
        _hospitalPhone = data['hospital']['phone']?.toString();
      }
      if (data['driver'] != null) {
        _driverName = data['driver']['display_name']?.toString() ?? data['driver']['full_name']?.toString();
        _driverPhone = data['driver']['phone']?.toString() ?? data['driver']['phone_number']?.toString();
        _vehicleLabel = data['driver']['vehicle_label']?.toString();
      }
    });
  }

  Future<void> _cancelRequest() async {
    final id = _requestId;
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Emergency?'),
        content: const Text('Are you sure you want to cancel this emergency dispatch?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('NO, KEEP ACTIVE')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('YES, CANCEL', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _isCancelling = true);
    try {
      await _supabase.from('emergency_requests').update({'status': 'Cancelled / failed'}).eq('id', id);
      if (mounted) setState(() { _isCancelling = false; _currentStatus = 'Cancelled / failed'; });
    } catch (e) {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  void _openLiveTracking() {
    final id = _requestId;
    if (id == null) return;
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LiveAmbulanceTrackingScreen(
          requestId: id,
          patientLocation: (widget.latitude != null && widget.longitude != null) 
              ? LatLng(widget.latitude!, widget.longitude!) 
              : LatLng(0, 0),
          patientAddress: widget.address ?? widget.patientAddress ?? 'Scene Location',
        ),
      ),
    );
  }

  void _returnHome() {
    if (widget.onReturnHome != null) {
      widget.onReturnHome!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const HomeScreen()));
    }
  }

  // --- Dynamic UI Helpers ---
  
  IconData get _statusIcon {
    final s = _currentStatus.toLowerCase();
    if (s.contains('cancel') || s.contains('fail')) return Icons.cancel_rounded;
    if (s.contains('complete')) return Icons.check_circle_rounded;
    if (s.contains('en route to patient')) return Icons.directions_car_filled_rounded;
    if (s.contains('hospital confirmed')) return Icons.local_hospital_rounded;
    if (s.contains('driver assigned')) return Icons.person_pin_circle_rounded;
    return Icons.notifications_active_rounded;
  }

  Color get _statusColor {
    final s = _currentStatus.toLowerCase();
    if (s.contains('cancel') || s.contains('fail')) return Colors.redAccent;
    if (s.contains('complete')) return const Color(0xFF00E676);
    if (s.contains('en route to patient') || s.contains('driver assigned')) return const Color(0xFF0284C7);
    return Colors.orange;
  }

  String get _headlineText {
    final s = _currentStatus.toLowerCase();
    if (s.contains('pending')) return 'Help is being notified';
    if (s.contains('hospital confirmed')) return 'Hospital Bay Reserved';
    if (s.contains('driver assigned')) return 'Ambulance Assigned';
    if (s.contains('en route to patient')) return 'Ambulance En Route';
    if (s.contains('arrived at scene')) return 'Ambulance Arrived';
    if (s.contains('picked up')) return 'Patient On Board';
    if (s.contains('en route to hospital')) return 'Transferring to ER';
    if (s.contains('intake')) return 'Hospital Triage Active';
    if (s.contains('complete')) return 'Mission Complete';
    if (s.contains('cancel')) return 'Request Cancelled';
    return _currentStatus;
  }

  String get _descriptionText {
    final s = _currentStatus.toLowerCase();
    if (s.contains('pending')) return 'Your dispatch request is being broadcast to nearby verified hospitals and response teams.';
    if (s.contains('hospital confirmed')) return 'Emergency center has confirmed ICU/triage readiness for your arrival.';
    if (s.contains('driver assigned') || s.contains('en route to patient')) return 'A paramedic unit has accepted the dispatch and is navigating to your location.';
    if (s.contains('arrived at scene')) return 'Paramedics have arrived at your location. Please signal the response unit.';
    if (s.contains('picked up') || s.contains('en route to hospital')) return 'Patient is safely on board ambulance and receiving care en route to hospital.';
    if (s.contains('complete')) return 'Patient care transferred to medical team.';
    if (s.contains('cancel')) return 'This emergency dispatch request has been closed.';
    return 'Status: $_currentStatus';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Mimic the clean yellowish-white or deep dark background
    final bgColor = isDark ? AppTheme.darkBg : const Color(0xFFFFFDF8);
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1E293B);
    final textMuted = isDark ? Colors.white70 : const Color(0xFF64748B);

    final isTerminal = _isCompleted || _isCancelled;

    return PopScope(
      canPop: isTerminal,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _returnHome();
      },
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          title: Text(
            'Emergency Status',
            style: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          iconTheme: IconThemeData(color: textPrimary),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                
                // Animated Icon Circle
                Stack(
                  alignment: Alignment.center,
                  children: [
                    if (!isTerminal)
                      AnimatedBuilder(
                        animation: _radarController,
                        builder: (_, __) {
                          return Transform.scale(
                            scale: _radarScale.value,
                            child: Opacity(
                              opacity: _radarOpacity.value,
                              child: Container(
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _statusColor.withOpacity(0.3),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _statusColor.withOpacity(isDark ? 0.2 : 0.1),
                        border: Border.all(color: _statusColor.withOpacity(0.5), width: 2),
                      ),
                      child: Icon(_statusIcon, size: 40, color: _statusColor),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                Text(
                  _headlineText,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textPrimary, fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                Text(
                  _descriptionText,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textMuted, fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 32),

                // Main Details Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: isDark ? [] : [
                      BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))
                    ],
                    border: isDark ? Border.all(color: AppTheme.darkCardBorder) : Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      _buildInfoRow('Request Reference', '#$_shortId', textPrimary, textMuted, isBold: true),
                      const Divider(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text('Current Lifecycle State', style: TextStyle(color: textMuted, fontSize: 13)),
                          ),
                          Expanded(
                            flex: 3,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _statusColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _statusColor.withOpacity(0.3)),
                                ),
                                child: Text(
                                  _currentStatus,
                                  style: TextStyle(color: _statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      _buildInfoRow('Location', widget.address ?? widget.patientAddress ?? 'GPS Location verified', textPrimary, textMuted),
                      
                      if (_hospitalName != null) ...[
                        const Divider(height: 24),
                        _buildInfoRow('Receiving Hospital', _hospitalName!, textPrimary, textMuted, icon: Icons.local_hospital_rounded),
                      ],
                      if (_driverName != null) ...[
                        const Divider(height: 24),
                        _buildInfoRow('Assigned Paramedic', '$_driverName $_vehicleLabel', textPrimary, textMuted, icon: Icons.directions_car_rounded),
                      ],
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),

                // Map Button (if driver assigned)
                if (!isTerminal && _driverName != null) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _openLiveTracking,
                      icon: const Icon(Icons.map_rounded),
                      label: const Text('OPEN LIVE AMBULANCE MAP', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Cancel Button
                if (!isTerminal)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: BorderSide(color: Colors.redAccent.withOpacity(0.3)),
                        backgroundColor: Colors.red.withOpacity(isDark ? 0.1 : 0.05),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isCancelling ? null : _cancelRequest,
                      icon: _isCancelling 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))
                        : const Icon(Icons.close_rounded),
                      label: Text(_isCancelling ? 'CANCELLING...' : 'Cancel Emergency Request', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),

                if (isTerminal)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.darkPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _returnHome,
                      icon: const Icon(Icons.home_rounded),
                      label: const Text('RETURN TO HOME', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color textPrimary, Color textMuted, {bool isBold = false, IconData? icon}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(label, style: TextStyle(color: textMuted, fontSize: 13)),
        ),
        Expanded(
          flex: 3,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: textMuted),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  value.replaceAll('', ''), // Just stripping any stray backticks safely
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: textPrimary, 
                    fontSize: 13, 
                    fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}