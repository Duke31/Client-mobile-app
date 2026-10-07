import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/env.dart';

/// Reverse-geocode via Mapbox Geocoding v5.
///
/// On timeout, HTTP error, or missing token, returns `"$lat, $lng"`
/// so emergency submission is never blocked.
class MapboxGeocoding {
  MapboxGeocoding({
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
    String? accessToken,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _accessToken = accessToken ?? Env.mapboxAccessToken;

  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;
  final String _accessToken;

  static const _endpoint = 'https://api.mapbox.com/geocoding/v5/mapbox.places';

  Future<String> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    final fallback = '$latitude, $longitude';

    if (_accessToken.isEmpty || _accessToken == 'YOUR_TOKEN') {
      return fallback;
    }

    final uri = Uri.parse(
      '$_endpoint/$longitude,$latitude.json',
    ).replace(queryParameters: <String, String>{
      'access_token': _accessToken,
      'limit': '1',
    });

    try {
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return fallback;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return fallback;

      final features = decoded['features'];
      if (features is! List || features.isEmpty) return fallback;

      final first = features.first;
      if (first is! Map<String, dynamic>) return fallback;

      final placeName = first['place_name'];
      if (placeName is String && placeName.trim().isNotEmpty) {
        return placeName.trim();
      }
      return fallback;
    } on TimeoutException {
      return fallback;
    } on Object {
      return fallback;
    }
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
