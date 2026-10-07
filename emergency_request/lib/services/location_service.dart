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

/// High-accuracy GPS for emergency dispatch.
/// Prefer satellite / navigation grade; do not silently fall back to coarse cell.
class LocationService {
  const LocationService();

  LocationSettings _navSettings({Duration? timeLimit}) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        forceLocationManager: true, // hardware GPS, not network snap
        intervalDuration: const Duration(milliseconds: 1000),
        distanceFilter: 0,
        timeLimit: timeLimit,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
        timeLimit: timeLimit,
      );
    }
    return LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      timeLimit: timeLimit,
    );
  }

  /// Fast UI hint only (map may paint). Never used as final dispatch coords alone
  /// if [current] can still improve.
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

    Position? best;
    final completer = Completer<Position?>();

    final sub = Geolocator.getPositionStream(
      locationSettings: _navSettings(),
    ).listen((pos) {
      if (pos.accuracy <= 0) return;
      debugPrint(
        'GPS sample ±${pos.accuracy.toStringAsFixed(1)}m '
        '${pos.latitude.toStringAsFixed(5)},${pos.longitude.toStringAsFixed(5)}',
      );
      if (best == null || pos.accuracy < best!.accuracy) {
        best = pos;
      }
      // Building-entrance grade — accept early (stricter than 30m)
      if (pos.accuracy <= 15.0 && !completer.isCompleted) {
        completer.complete(pos);
      }
    }, onError: (e) {
      debugPrint('GPS stream error: $e');
    });

    // Allow satellite lock time (was shortened to 4s and hurt accuracy)
    Timer(const Duration(seconds: 12), () {
      if (!completer.isCompleted) completer.complete(best);
    });

    final streamPos = await completer.future;
    await sub.cancel();

    if (streamPos != null && streamPos.accuracy <= 50) {
      return LocationFix(
        latitude: streamPos.latitude,
        longitude: streamPos.longitude,
        accuracyMeters: streamPos.accuracy,
      );
    }

    // One-shot still at navigation accuracy (not medium/high-only)
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: _navSettings(timeLimit: const Duration(seconds: 12)),
      );
      return LocationFix(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracyMeters: pos.accuracy,
      );
    } catch (e) {
      debugPrint('getCurrentPosition nav failed: $e');
    }

    if (streamPos != null) {
      return LocationFix(
        latitude: streamPos.latitude,
        longitude: streamPos.longitude,
        accuracyMeters: streamPos.accuracy,
      );
    }

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
