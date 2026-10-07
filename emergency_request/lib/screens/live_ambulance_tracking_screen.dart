import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/client_request_detail.dart';
import 'package:http/http.dart' as http;

class LiveAmbulanceTrackingScreen extends StatefulWidget {
  final String requestId;
  final LatLng patientLocation;
  final String? patientAddress;
  final String? mapboxAccessToken;

  const LiveAmbulanceTrackingScreen({
    super.key,
    required this.requestId,
    required this.patientLocation,
    this.patientAddress,
    this.mapboxAccessToken,
  });

  @override
  State<LiveAmbulanceTrackingScreen> createState() =>
      _LiveAmbulanceTrackingScreenState();
}

class _LiveAmbulanceTrackingScreenState
    extends State<LiveAmbulanceTrackingScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  final SupabaseClient _supabase = Supabase.instance.client;

  RealtimeChannel? _trackingChannel;
  RealtimeChannel? _globalChannel;
  RealtimeChannel? _driverDbChannel;
  Timer? _pollingTimer;

  String? _resolvedRequestId;
  String? _driverId;
  String? _driverName;
  String? _vehicleLabel;
  double _currentSpeedKmH = 0.0;
  String _missionStatus = "Connecting…";

  LatLng? _previousPos;
  LatLng? _targetPos;
  LatLng? _dbPatientLocation;

  LatLng get _effectivePatientLocation {
    if (_dbPatientLocation != null &&
        (_dbPatientLocation!.latitude != 0.0 || _dbPatientLocation!.longitude != 0.0)) {
      return _dbPatientLocation!;
    }
    if (widget.patientLocation.latitude != 0.0 || widget.patientLocation.longitude != 0.0) {
      return widget.patientLocation;
    }
    if (_targetPos != null &&
        (_targetPos!.latitude != 0.0 || _targetPos!.longitude != 0.0)) {
      return _targetPos!;
    }
    return const LatLng(7.4434, 4.0051);
  }
  double _vehicleHeading = 0.0;

  late AnimationController _animController;
  late Animation<double> _latAnimation;
  late Animation<double> _lngAnimation;
  late Animation<double> _headingAnimation;

  int? _etaMinutes;
  double? _distanceKm;
  List<LatLng> _routePoints = [];
  Timer? _etaDebounceTimer;
  bool _hasFittedBounds = false;

  @override
  void initState() {
    super.initState();
    _resolvedRequestId = widget.requestId.isNotEmpty ? widget.requestId : null;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _latAnimation = Tween<double>(
      begin: _effectivePatientLocation.latitude,
      end: _effectivePatientLocation.latitude,
    ).animate(_animController);

    _lngAnimation = Tween<double>(
      begin: _effectivePatientLocation.longitude,
      end: _effectivePatientLocation.longitude,
    ).animate(_animController);

    _headingAnimation = Tween<double>(begin: 0, end: 0).animate(_animController);

    _loadData();
    _subscribeChannels();

    // Polling fallback every 3 seconds for rock-solid stability
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollDriverLocation();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _pollingTimer?.cancel();
    _etaDebounceTimer?.cancel();
    if (_trackingChannel != null) _supabase.removeChannel(_trackingChannel!);
    if (_globalChannel != null) _supabase.removeChannel(_globalChannel!);
    if (_driverDbChannel != null) _supabase.removeChannel(_driverDbChannel!);
    super.dispose();
  }

  // 1. Initial Load: Resolve request and driver info
  Future<void> _loadData() async {
    try {
      Map<String, dynamic>? req;

      // A. Query with current requestId if available
      if (_resolvedRequestId != null && _resolvedRequestId!.isNotEmpty) {
        req = await _supabase
            .from('emergency_requests')
            .select('id, status, driver_id, patient_lat, patient_lng')
            .eq('id', _resolvedRequestId!)
            .maybeSingle();
      }

      // B. Only if caller did not pass an id — never steal another patient's ticket
      if (req == null &&
          (widget.requestId.isEmpty) &&
          (_resolvedRequestId == null || _resolvedRequestId!.isEmpty)) {
        final activeList = await _supabase
            .from('emergency_requests')
            .select('id, status, driver_id, patient_lat, patient_lng')
            .not('driver_id', 'is', null)
            .order('created_at', ascending: false)
            .limit(1);

        if (activeList.isNotEmpty) {
          req = activeList.first;
          _resolvedRequestId = req?['id']?.toString();
        }
      }

      if (req != null && mounted) {
        final plat = (req['patient_lat'] as num?)?.toDouble();
        final plng = (req['patient_lng'] as num?)?.toDouble();
        if (plat != null && plng != null && (plat != 0.0 || plng != 0.0)) {
          _dbPatientLocation = LatLng(plat, plng);
        }
        final status = req['status']?.toString() ?? "Driver Assigned";
        final driverId = req['driver_id']?.toString();

        setState(() {
          _missionStatus = status;
          _driverId = driverId;
        });

        if (driverId != null && driverId.isNotEmpty) {
          _fetchDriverDetails(driverId);
          _listenToDriverDb(driverId);
        }
        final rid = _resolvedRequestId ?? widget.requestId;
        if (rid.isNotEmpty) {
          _listenToRequestStatus(rid);
          // Re-bind request-tracking channel to resolved id
          _ensureRequestTrackingChannel(rid);
        }
      } else if (mounted) {
        setState(() {
          _missionStatus = "Waiting for assignment…";
        });
        debugPrint(
          "LiveTracking: no emergency_requests row for id=${widget.requestId}",
        );
      }
    } catch (e) {
      debugPrint("LiveTracking load error: $e");
      if (mounted) {
        setState(() => _missionStatus = "Connection error — retrying…");
      }
    }
  }

  Future<void> _fetchDriverDetails(String driverId) async {
    try {
      final d = await _supabase
          .from('drivers')
          .select('*')
          .eq('id', driverId)
          .maybeSingle();

      if (d != null && mounted) {
        final name = d['display_name']?.toString() ??
            d['full_name']?.toString() ??
            d['name']?.toString() ??
            "Ambulance Unit";

        final vehicle = d['vehicle_label']?.toString() ??
            d['vehicle_plate']?.toString() ??
            "Rapid Response Vehicle";

        final lat = (d['current_lat'] as num?)?.toDouble();
        final lng = (d['current_lng'] as num?)?.toDouble();
        final heading = (d['heading'] as num?)?.toDouble() ?? 0.0;
        final speed = (d['speed'] as num?)?.toDouble() ?? 0.0;

        setState(() {
          _driverName = name;
          _vehicleLabel = vehicle;
        });

        if (lat != null && lng != null) {
          _applyNewDriverPosition(
            newPos: LatLng(lat, lng),
            heading: heading,
            speedMps: speed,
            driverName: name,
            vehicleLabel: vehicle,
          );
        }
      }
    } catch (e) {
      debugPrint("Error loading driver: $e");
    }
  }

  // 2. Poller fallback
  Future<void> _pollDriverLocation() async {
    // Prefer SECURITY DEFINER detail (driver coords + phone) when table RLS blocks
    final reqKey = _resolvedRequestId ?? widget.requestId;
    if (reqKey.isNotEmpty) {
      final detail = await ClientRequestDetail.fetch(_supabase, reqKey);
      if (detail != null) {
        final plat = (detail['patient_lat'] as num?)?.toDouble();
        final plng = (detail['patient_lng'] as num?)?.toDouble();
        if (plat != null && plng != null && (plat != 0.0 || plng != 0.0)) {
          if (_dbPatientLocation == null ||
              _dbPatientLocation!.latitude != plat ||
              _dbPatientLocation!.longitude != plng) {
            if (mounted) {
              setState(() => _dbPatientLocation = LatLng(plat, plng));
            }
          }
        }
        final d = detail['driver'];
        if (d is Map) {
          final lat = (d['current_lat'] as num?)?.toDouble();
          final lng = (d['current_lng'] as num?)?.toDouble();
          final name = d['display_name']?.toString();
          final vehicle = d['vehicle_label']?.toString();
          final did = detail['driver_id']?.toString() ?? d['id']?.toString();
          if (did != null && did.isNotEmpty) _driverId = did;
          if (name != null || vehicle != null) {
            if (mounted) {
              setState(() {
                if (name != null && name.isNotEmpty) _driverName = name;
                if (vehicle != null && vehicle.isNotEmpty) _vehicleLabel = vehicle;
              });
            }
          }
          if (lat != null && lng != null) {
            _applyNewDriverPosition(
              newPos: LatLng(lat, lng),
              heading: (d['heading'] as num?)?.toDouble(),
              speedMps: (d['speed'] as num?)?.toDouble(),
              driverName: name,
              vehicleLabel: vehicle,
            );
            return;
          }
        }
        final st = detail['status']?.toString();
        if (st != null && mounted) {
          setState(() {
            // surface cancelled on map chrome if field exists
          });
        }
      }
    }


    final rid = _resolvedRequestId ?? widget.requestId;
    if (_driverId == null || _driverId!.isEmpty) {
      await _loadData();
      return;
    }

    // Keep status pill in sync (not only GPS)
    if (rid.isNotEmpty) {
      try {
        final req = await _supabase
            .from('emergency_requests')
            .select('status, driver_id')
            .eq('id', rid)
            .maybeSingle();
        if (req != null && mounted) {
          final st = req['status']?.toString();
          final did = req['driver_id']?.toString();
          setState(() {
            if (st != null && st.isNotEmpty) _missionStatus = st;
            if (did != null && did.isNotEmpty && did != _driverId) {
              _driverId = did;
            }
          });
          if (did != null && did.isNotEmpty && did != _driverId) {
            _fetchDriverDetails(did);
            _listenToDriverDb(did);
          }
        }
      } catch (e) {
        debugPrint("Status poll error: $e");
      }
    }

    try {
      final d = await _supabase
          .from('drivers')
          .select(
            'current_lat, current_lng, heading, speed, display_name, vehicle_label',
          )
          .eq('id', _driverId!)
          .maybeSingle();

      if (d != null && mounted) {
        final lat = (d['current_lat'] as num?)?.toDouble();
        final lng = (d['current_lng'] as num?)?.toDouble();
        final heading = (d['heading'] as num?)?.toDouble() ?? _vehicleHeading;
        final speed = (d['speed'] as num?)?.toDouble() ?? 0.0;
        final name = d['display_name']?.toString();
        final vehicle = d['vehicle_label']?.toString();

        if (name != null || vehicle != null) {
          setState(() {
            if (name != null && name.isNotEmpty) _driverName = name;
            if (vehicle != null && vehicle.isNotEmpty) _vehicleLabel = vehicle;
          });
        }

        if (lat != null && lng != null) {
          _applyNewDriverPosition(
            newPos: LatLng(lat, lng),
            heading: heading,
            speedMps: speed,
            driverName: name,
            vehicleLabel: vehicle,
          );
        }
      }
    } catch (e) {
      debugPrint("Driver poll error: $e");
    }
  }

  // 3. Realtime Dual-Subscription: Request-Specific + System-Wide
  void _subscribeChannels() {
    // A. Request channel
    final reqId = _resolvedRequestId ?? widget.requestId;
    if (reqId.isNotEmpty) {
      _trackingChannel = _supabase
          .channel('request-tracking:$reqId')
          .onBroadcast(
            event: 'location_update',
            callback: (payload) {
              _handleBroadcastPayload(Map<String, dynamic>.from(payload));
            },
          )
          .subscribe();
    }

    // B. Global responder channel (matches locChannel in DriverConsole.tsx)
    _globalChannel = _supabase
        .channel('responder_locations')
        .onBroadcast(
          event: 'location_update',
          callback: (payload) {
            final map = Map<String, dynamic>.from(payload);
            final unwrapped = _unwrapBroadcast(map);
            final incomingDriverId = unwrapped['driver_id']?.toString();
            if (_driverId == null ||
                incomingDriverId == null ||
                incomingDriverId == _driverId) {
              _handleBroadcastPayload(map);
            }
          },
        )
        .subscribe();
  }

  /// Web client sends { type, event, payload: { lat, lng, ... } }; some SDK
  /// paths deliver the inner map, others the outer — unwrap both.
  Map<String, dynamic> _unwrapBroadcast(Map<String, dynamic> payload) {
    final inner = payload['payload'];
    if (inner is Map) {
      return Map<String, dynamic>.from(inner);
    }
    return payload;
  }

  void _handleBroadcastPayload(Map<String, dynamic> raw) {
    final payload = _unwrapBroadcast(raw);
    final lat = (payload['lat'] as num?)?.toDouble();
    final lng = (payload['lng'] as num?)?.toDouble();
    final heading = (payload['heading'] as num?)?.toDouble() ?? _vehicleHeading;
    final speed = (payload['speed'] as num?)?.toDouble() ?? 0.0;
    final driverName = payload['driver_name']?.toString();
    final vehicleLabel = payload['vehicle_label']?.toString();
    final incomingDriverId = payload['driver_id']?.toString();

    if (incomingDriverId != null &&
        _driverId != null &&
        incomingDriverId != _driverId) {
      return;
    }

    if (lat != null && lng != null && mounted) {
      _applyNewDriverPosition(
        newPos: LatLng(lat, lng),
        heading: heading,
        speedMps: speed,
        driverName: driverName,
        vehicleLabel: vehicleLabel,
      );
    }
  }

  void _ensureRequestTrackingChannel(String reqId) {
    if (reqId.isEmpty) return;
    if (_trackingChannel != null) {
      _supabase.removeChannel(_trackingChannel!);
      _trackingChannel = null;
    }
    _trackingChannel = _supabase
        .channel('request-tracking:$reqId')
        .onBroadcast(
          event: 'location_update',
          callback: (payload) {
            _handleBroadcastPayload(Map<String, dynamic>.from(payload));
          },
        )
        .subscribe();
  }

  void _listenToRequestStatus(String reqId) {
    _supabase
        .channel('request-status:$reqId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'emergency_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: reqId,
          ),
          callback: (payload) {
            final rec = payload.newRecord;
            if (!mounted) return;
            final st = rec['status']?.toString();
            final did = rec['driver_id']?.toString();
            setState(() {
              if (st != null && st.isNotEmpty) _missionStatus = st;
              if (did != null && did.isNotEmpty) _driverId = did;
            });
            if (did != null && did.isNotEmpty) {
              _fetchDriverDetails(did);
              _listenToDriverDb(did);
            }
          },
        )
        .subscribe();
  }

  void _listenToDriverDb(String driverId) {
    _driverDbChannel = _supabase
        .channel('driver-db-sync:$driverId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'drivers',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: driverId,
          ),
          callback: (payload) {
            final rec = payload.newRecord;
            final lat = (rec['current_lat'] as num?)?.toDouble();
            final lng = (rec['current_lng'] as num?)?.toDouble();
            final heading = (rec['heading'] as num?)?.toDouble() ?? _vehicleHeading;
            final speed = (rec['speed'] as num?)?.toDouble() ?? 0.0;

            if (lat != null && lng != null && mounted) {
              _applyNewDriverPosition(
                newPos: LatLng(lat, lng),
                heading: heading,
                speedMps: speed,
              );
            }
          },
        )
        .subscribe();
  }

  // 4. Smooth Animation Engine
  void _applyNewDriverPosition({
    required LatLng newPos,
    double heading = 0.0,
    double speedMps = 0.0,
    String? driverName,
    String? vehicleLabel,
  }) {
    final startPos = _targetPos ?? newPos;

    setState(() {
      if (driverName != null) _driverName = driverName;
      if (vehicleLabel != null) _vehicleLabel = vehicleLabel;
      _currentSpeedKmH = (speedMps * 3.6).clamp(0.0, 160.0);
      _targetPos = newPos;
    });

    _latAnimation = Tween<double>(
      begin: startPos.latitude,
      end: newPos.latitude,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeInOut));

    _lngAnimation = Tween<double>(
      begin: startPos.longitude,
      end: newPos.longitude,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeInOut));

    double startHeading = _vehicleHeading;
    double endHeading = heading;
    if ((endHeading - startHeading).abs() > 180) {
      if (endHeading > startHeading) {
        startHeading += 360;
      } else {
        endHeading += 360;
      }
    }

    _headingAnimation = Tween<double>(
      begin: startHeading,
      end: endHeading,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _animController.reset();
    _animController.forward();

    _previousPos = startPos;
    _vehicleHeading = heading % 360;

    if (!_hasFittedBounds) {
      _hasFittedBounds = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fitMapBounds(newPos, _effectivePatientLocation);
      });
    }

    _etaDebounceTimer?.cancel();
    _etaDebounceTimer = Timer(const Duration(seconds: 2), () {
      _recalculateLiveETA(newPos);
    });
  }

  void _fitMapBounds(LatLng p1, LatLng p2) {
    try {
      final latDiff = (p1.latitude - p2.latitude).abs();
      final lngDiff = (p1.longitude - p2.longitude).abs();
      LatLng ptA = p1;
      LatLng ptB = p2;
      if (latDiff < 0.001 && lngDiff < 0.001) {
        ptA = LatLng(p1.latitude - 0.002, p1.longitude - 0.002);
        ptB = LatLng(p2.latitude + 0.002, p2.longitude + 0.002);
      }
      final bounds = LatLngBounds.fromPoints([ptA, ptB]);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 120),
        ),
      );
    } catch (_) {}
  }

  // 5. ETA Calculation
  Future<void> _recalculateLiveETA(LatLng driverPos) async {
    if (widget.mapboxAccessToken != null && widget.mapboxAccessToken!.isNotEmpty) {
      try {
        final url = Uri.parse(
          'https://api.mapbox.com/directions/v5/mapbox/driving/'
          '${driverPos.longitude},${driverPos.latitude};'
          '${_effectivePatientLocation.longitude},${_effectivePatientLocation.latitude}'
          '?geometries=geojson&overview=full&access_token=${widget.mapboxAccessToken}',
        );

        final res = await http.get(url);
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final route = data['routes'][0];
          final durationSec = (route['duration'] as num).toDouble();
          final distanceM = (route['distance'] as num).toDouble();

          final geometry = route['geometry']['coordinates'] as List;
          final polyline = geometry
              .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
              .toList();

          if (mounted) {
            setState(() {
              _etaMinutes = (durationSec / 60).ceil();
              _distanceKm = distanceM / 1000;
              _routePoints = polyline;
            });
          }
          return;
        }
      } catch (e) {
        debugPrint("Mapbox Directions API fallback: $e");
      }
    }

    // Fallback: Haversine distance with 35 km/h urban speed
    const Distance distance = Distance();
    final meters = distance.as(LengthUnit.Meter, driverPos, _effectivePatientLocation);
    final km = meters / 1000;
    final minutes = ((km / 35.0) * 60).ceil().clamp(1, 120);

    if (mounted) {
      setState(() {
        _distanceKm = km;
        _etaMinutes = minutes;
        _routePoints = [driverPos, _effectivePatientLocation];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Map
          AnimatedBuilder(
            animation: _animController,
            builder: (context, child) {
              final currentLat = _targetPos != null && _animController.isAnimating
                  ? _latAnimation.value
                  : _targetPos?.latitude ?? _effectivePatientLocation.latitude;
              final currentLng = _targetPos != null && _animController.isAnimating
                  ? _lngAnimation.value
                  : _targetPos?.longitude ?? _effectivePatientLocation.longitude;
              final animatedHeading = _animController.isAnimating
                  ? _headingAnimation.value
                  : _vehicleHeading;

              final currentDriverPos = LatLng(currentLat, currentLng);

              return FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _effectivePatientLocation,
                  initialZoom: 15.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate: widget.mapboxAccessToken != null && widget.mapboxAccessToken!.isNotEmpty
                        ? 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}?access_token=${widget.mapboxAccessToken}'
                        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.emergency.emergency_request',
                  ),

                  // Blue route line
                  if (_routePoints.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _routePoints,
                          color: const Color(0xFF2563EB),
                          strokeWidth: 4.5,
                        ),
                      ],
                    ),

                  MarkerLayer(
                    markers: [
                      // Patient Destination Pin
                      Marker(
                        point: _effectivePatientLocation,
                        width: 50,
                        height: 50,
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: Colors.redAccent,
                          size: 44,
                        ),
                      ),

                      // Animated Ambulance Marker
                      if (_targetPos != null)
                        Marker(
                          point: currentDriverPos,
                          width: 56,
                          height: 56,
                          child: Transform.rotate(
                            angle: (animatedHeading * (math.pi / 180)),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(8),
                              child: const Icon(
                                Icons.emergency_rounded,
                                color: Color(0xFFDC2626),
                                size: 30,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),

          // Header Bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.white,
                  radius: 20,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black87, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Color(0xFF16A34A),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _missionStatus.toUpperCase(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 0.8,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        if (_currentSpeedKmH > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              "${_currentSpeedKmH.toStringAsFixed(0)} km/h",
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Arrival Card
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "ESTIMATED ARRIVAL",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.9,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _etaMinutes != null ? "$_etaMinutes mins" : "Locating Unit…",
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                      if (_distanceKm != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Text(
                            "${_distanceKm!.toStringAsFixed(1)} km away",
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1D4ED8),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Divider(height: 22),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFF046A38).withOpacity(0.12),
                        child: const Icon(
                          Icons.local_shipping_rounded,
                          color: Color(0xFF046A38),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _driverName ?? "Assigned Ambulance Unit",
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              _vehicleLabel ?? "Rapid Response Vehicle",
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_targetPos != null)
                        IconButton(
                          icon: const Icon(Icons.my_location_rounded, color: Color(0xFF2563EB)),
                          onPressed: () {
                            _fitMapBounds(_targetPos!, _effectivePatientLocation);
                          },
                          tooltip: "Re-center",
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}




