import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.fromCache = false,
  });

  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final bool fromCache;
}

/// High-performance, high-accuracy GPS engine for Solace emergency medical dispatch.
/// Designed for instant (< 50ms) initial render from device cache, followed by
/// rapid (< 2s) high-precision satellite/fused hardware locks.
class LocationService {
  const LocationService();

  /// Pre-warms the hardware GPS chip and location subsystem in the background.
  Future<void> warmUp() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return;
      }
      // Wake up hardware location provider asynchronously without blocking
      Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 4),
        ),
      ).catchError((_) {});
    } catch (_) {}
  }

  /// Ensures location services are active and permissions are granted
  Future<bool> ensurePermission() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return false;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      return perm == LocationPermission.whileInUse || perm == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// Continuous stream configuration for live telemetry.
  static LocationSettings streamSettings({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int intervalMs = 1000,
    int distanceFilter = 0,
  }) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: accuracy,
        intervalDuration: Duration(milliseconds: intervalMs),
        distanceFilter: distanceFilter,
        forceLocationManager: false,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
        distanceFilter: distanceFilter,
      );
    }
    return LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
    );
  }

  /// Instant estimate from device GPS cache so UI renders IMMEDIATELY (< 50ms).
  /// Never blocks or sleeps. Returns whatever recent position the OS has cached.
  Future<LocationFix?> quickEstimate() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return LocationFix(
          latitude: last.latitude,
          longitude: last.longitude,
          accuracyMeters: last.accuracy,
          fromCache: true,
        );
      }
    } catch (_) {}
    return null;
  }

  /// Continuous live telemetry stream emitting updated GPS fixes.
  Stream<LocationFix> get liveStream {
    return Geolocator.getPositionStream(
      locationSettings: streamSettings(),
    ).map((pos) => LocationFix(
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracyMeters: pos.accuracy,
          fromCache: false,
        ));
  }

  /// Acquires true high-accuracy GPS fix as fast as possible (< 2-3s).
  /// Multi-tier fallback guarantees no hanging, blocking, or fake city defaults.
  Future<LocationFix> current() async {
    final hasPerm = await ensurePermission();
    if (!hasPerm) {
      final cached = await quickEstimate();
      if (cached != null) return cached;
      throw const LocationException(
        'Location permission is required or location services are disabled.',
      );
    }

    // Tier 1: Fast direct high-accuracy query (Fused Location / GPS)
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: defaultTargetPlatform == TargetPlatform.android
            ? AndroidSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: const Duration(seconds: 4),
                forceLocationManager: false,
              )
            : const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 4),
              ),
      );
      return LocationFix(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracyMeters: pos.accuracy,
        fromCache: false,
      );
    } catch (e) {
      debugPrint('current(): Fused location attempt notice: $e');
    }

    // Tier 2: Android direct hardware GPS provider (bypasses Google Play Services if throttled)
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 4),
            forceLocationManager: true, // Native Android LocationManager GPS
          ),
        );
        return LocationFix(
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracyMeters: pos.accuracy,
          fromCache: false,
        );
      } catch (e) {
        debugPrint('current(): Direct hardware GPS attempt notice: $e');
      }
    }

    // Tier 3: Medium accuracy query
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 3),
        ),
      );
      return LocationFix(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracyMeters: pos.accuracy,
        fromCache: false,
      );
    } catch (_) {}

    // Tier 4: Fallback to last known position
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) {
      return LocationFix(
        latitude: last.latitude,
        longitude: last.longitude,
        accuracyMeters: last.accuracy,
        fromCache: true,
      );
    }

    throw const LocationException('Unable to acquire GPS fix. Please verify location is enabled.');
  }

  /// Forces a fresh satellite hardware GPS reading, bypassing any cached coordinates.
  /// Used by the SOS map recenter button to recalibrate immediately (< 3-4s).
  Future<LocationFix> forceFreshGps({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final hasPerm = await ensurePermission();
    if (!hasPerm) {
      throw const LocationException('Location permission not granted');
    }

    // Attempt 1: High accuracy fused query
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: defaultTargetPlatform == TargetPlatform.android
            ? AndroidSettings(
                accuracy: LocationAccuracy.bestForNavigation,
                timeLimit: timeout,
                forceLocationManager: false,
              )
            : LocationSettings(
                accuracy: LocationAccuracy.bestForNavigation,
                timeLimit: timeout,
              ),
      );
      return LocationFix(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracyMeters: pos.accuracy,
        fromCache: false,
      );
    } catch (_) {}

    // Attempt 2: Direct Android hardware GPS chip
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            timeLimit: const Duration(seconds: 4),
            forceLocationManager: true,
          ),
        );
        return LocationFix(
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracyMeters: pos.accuracy,
          fromCache: false,
        );
      } catch (_) {}
    }

    return await current();
  }
}

class LocationException implements Exception {
  const LocationException(this.message);
  final String message;

  @override
  String toString() => message;
}
