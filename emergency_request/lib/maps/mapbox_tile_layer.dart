import 'package:flutter_map/flutter_map.dart';

import '../config/env.dart';

/// Mapbox Streets v12 raster tiles (no native Mapbox SDK).
TileLayer mapboxStreetsTileLayer({String? accessToken}) {
  final token = accessToken ?? Env.mapboxAccessToken;

  return TileLayer(
    urlTemplate:
        'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}@2x?access_token={accessToken}',
    additionalOptions: <String, String>{
      'accessToken': token,
    },
    userAgentPackageName: 'com.example.emergency_request',
    tileSize: 512,
    zoomOffset: -1,
    maxNativeZoom: 22,
    maxZoom: 22,
  );
}

const String mapboxAttribution = '© Mapbox © OpenStreetMap';
