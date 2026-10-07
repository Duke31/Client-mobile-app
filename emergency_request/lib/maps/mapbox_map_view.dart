import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'mapbox_tile_layer.dart';

/// Pure-Flutter map widget. Replaces GoogleMap / mapbox_maps_flutter.
class MapboxMapView extends StatelessWidget {
  const MapboxMapView({
    super.key,
    required this.center,
    this.zoom = 15,
    this.markers = const <Marker>[],
    this.onTap,
    this.mapController,
    this.interactive = true,
    this.showAttribution = true,
  });

  factory MapboxMapView.patientLocation({
    Key? key,
    required double latitude,
    required double longitude,
    double zoom = 16,
    bool interactive = true,
    MapController? mapController,
    void Function(TapPosition, LatLng)? onTap,
  }) {
    final point = LatLng(latitude, longitude);
    return MapboxMapView(
      key: key,
      center: point,
      zoom: zoom,
      interactive: interactive,
      mapController: mapController,
      onTap: onTap,
      markers: <Marker>[
        Marker(
          point: point,
          width: 44,
          height: 44,
          alignment: Alignment.topCenter,
          child: const Icon(
            Icons.location_on,
            color: Color(0xFFC62828),
            size: 40,
          ),
        ),
      ],
    );
  }

  final LatLng center;
  final double zoom;
  final List<Marker> markers;
  final void Function(TapPosition, LatLng)? onTap;
  final MapController? mapController;
  final bool interactive;
  final bool showAttribution;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        onTap: onTap,
        interactionOptions: InteractionOptions(
          flags: interactive ? InteractiveFlag.all : InteractiveFlag.none,
        ),
      ),
      children: <Widget>[
        mapboxStreetsTileLayer(),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
        if (showAttribution)
          const RichAttributionWidget(
            attributions: <SourceAttribution>[
              TextSourceAttribution(mapboxAttribution),
            ],
          ),
      ],
    );
  }
}
