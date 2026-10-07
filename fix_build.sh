#!/bin/bash
sed -i 's/patientLatitude: widget.latitude,/patientLocation: (widget.latitude != null \&\& widget.longitude != null) ? LatLng(widget.latitude!, widget.longitude!) : const LatLng(0, 0),/g' emergency_request/lib/screens/submitted_screen.dart
sed -i 's/patientLongitude: widget.longitude,//g' emergency_request/lib/screens/submitted_screen.dart
sed -i 's/destinationAddress: widget.address ?? widget.patientAddress ?? '\''Scene Location'\'',/patientAddress: widget.address ?? widget.patientAddress ?? '\''Scene Location'\'',/g' emergency_request/lib/screens/submitted_screen.dart
sed -i 's/import '\''home_screen.dart'\'';/import '\''home_screen.dart'\'';\nimport '\''package:latlong2\/latlong.dart'\'';/g' emergency_request/lib/screens/submitted_screen.dart
sed -i 's/$vehicleLabel/$_vehicleLabel/g' emergency_request/lib/screens/submitted_screen.dart
