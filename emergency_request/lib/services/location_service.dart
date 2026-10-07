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

class LocationService {
  const LocationService();

  LocationSettings _navSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        forceLocationManager: true,
        intervalDuration: const Duration(milliseconds: 500),
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
    return const LocationSettings(accuracy: LocationAccuracy.bestForNavigation);
  }

  /// Instant fast path: returns last-known GPS location in <50ms so UI is immediate.
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

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 2),
        ),
      );
      return LocationFix(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracyMeters: pos.accuracy,
      );
    } catch (_) {
      return null;
    }
  }

  /// High-accuracy satellite GPS fix for precise dispatch.
  Future<LocationFix> current() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationException(
        'Location service is turned off. Please turn on GPS in phone settings.',
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

    final streamSettings = _navSettings();
    Position? bestPosition;
    final completer = Completer<Position?>();

    final subscription = Geolocator.getPositionStream(
      locationSettings: streamSettings,
    ).listen((pos) {
      if (pos.accuracy <= 0) return;
      if (bestPosition == null || pos.accuracy < bestPosition!.accuracy) {
        bestPosition = pos;
      }
      // Accurate enough for building entrance / street (<=30m) — complete fast
      if (pos.accuracy <= 30.0 && !completer.isCompleted) {
        completer.complete(pos);
      }
    }, onError: (_) {});

    // Cap acquisition wait to 4 seconds so UI never hangs
    Timer(const Duration(seconds: 4), () {
      if (!completer.isCompleted) completer.complete(bestPosition);
    });

    final accuratePos = await completer.future;
    await subscription.cancel();

    if (accuratePos != null) {
      return LocationFix(
        latitude: accuratePos.latitude,
        longitude: accuratePos.longitude,
        accuracyMeters: accuratePos.accuracy,
      );
    }

    // Direct one-shot fallback
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 4),
        ),
      );
      return LocationFix(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracyMeters: pos.accuracy,
      );
    } catch (_) {}

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
      'Could not acquire GPS fix. Turn on high-accuracy location, or tap the map to pin your position.',
    );
  }
}

class LocationException implements Exception {
  const LocationException(this.message);
  final String message;
  @override
  String toString() => message;
}
