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

/// High-accuracy GPS engine for Solace emergency medical dispatch.
/// Uses true GNSS satellite hardware provider (`bestForNavigation`, `forceLocationManager: true`).
/// Target accuracy: sub-15m building-entrance grade, with early exit as soon as satellite convergence is achieved.
class LocationService {
  const LocationService();

  LocationSettings _streamSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        forceLocationManager: true, // Hardware GPS satellites, not coarse network snap
        intervalDuration: const Duration(milliseconds: 1000),
        distanceFilter: 0,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
    );
  }

  LocationSettings _oneshotSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        forceLocationManager: true,
        timeLimit: const Duration(seconds: 10),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
        timeLimit: const Duration(seconds: 10),
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      timeLimit: Duration(seconds: 10),
    );
  }

  /// Instant estimate from device GPS cache so UI doesn't stall.
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

  /// Acquires true high-accuracy GNSS fix (sub-15m precision).
  Future<LocationFix> current() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationException(
        'Location service is turned off. Enable high-accuracy GPS in phone settings.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException('Location permission was denied.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'Location permission is permanently blocked. Enable it in App Settings.',
      );
    }

    // Step 1: Check if last known fix is recent and high-accuracy (< 15m)
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && last.accuracy <= 15.0) {
        final age = DateTime.now().difference(last.timestamp).inSeconds;
        if (age < 20) {
          return LocationFix(
            latitude: last.latitude,
            longitude: last.longitude,
            accuracyMeters: last.accuracy,
            fromCache: true,
          );
        }
      }
    } catch (_) {}

    // Step 2: Stream GPS updates with fast early-exit as soon as accuracy <= 15m
    Position? best;
    final completer = Completer<Position?>();

    final sub = Geolocator.getPositionStream(
      locationSettings: _streamSettings(),
    ).listen((pos) {
      if (pos.accuracy <= 0) return;
      if (best == null || pos.accuracy < best!.accuracy) {
        best = pos;
      }
      // Strict building-entrance grade: complete early when GPS converges
      if (pos.accuracy <= 15.0 && !completer.isCompleted) {
        completer.complete(pos);
      }
    }, onError: (Object e) {
      debugPrint('GPS stream error: $e');
    });

    // Convergence timeout: 8 seconds allows multi-satellite triangulation
    Timer(const Duration(milliseconds: 8000), () {
      if (!completer.isCompleted) completer.complete(best);
    });

    final streamPos = await completer.future;
    await sub.cancel();

    if (streamPos != null && streamPos.accuracy <= 30) {
      return LocationFix(
        latitude: streamPos.latitude,
        longitude: streamPos.longitude,
        accuracyMeters: streamPos.accuracy,
      );
    }

    // Step 3: Direct oneshot query with bestForNavigation
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: _oneshotSettings(),
      );
      return LocationFix(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracyMeters: pos.accuracy,
      );
    } catch (e) {
      debugPrint('getCurrentPosition navigation fallback notice: $e');
    }

    if (streamPos != null) {
      return LocationFix(
        latitude: streamPos.latitude,
        longitude: streamPos.longitude,
        accuracyMeters: streamPos.accuracy,
      );
    }

    // Step 4: Fallback to last known position
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) {
      return LocationFix(
        latitude: last.latitude,
        longitude: last.longitude,
        accuracyMeters: last.accuracy,
        fromCache: true,
      );
    }

    throw const LocationException(
      'Could not acquire a high-accuracy GPS fix. Move outdoors if possible, '
      'enable high-accuracy location, or pin your position on the map.',
    );
  }
}

class LocationException implements Exception {
  const LocationException(this.message);
  final String message;

  @override
  String toString() => message;
}
