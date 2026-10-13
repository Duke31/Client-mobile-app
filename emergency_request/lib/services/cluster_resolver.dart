import 'dart:math';

enum RegionCluster {
  ibadanPrivate,
  osunPilot,
  lagosMetro,
}

class ClusterResolver {
  static const Map<RegionCluster, Map<String, dynamic>> clusterMetadata = {
    RegionCluster.ibadanPrivate: {
      'id': 'ibadan_private',
      'name': 'Ibadan Private Hospital Network',
      'state': 'Oyo State',
      'centerLat': 7.3775,
      'centerLng': 3.9470,
      'tier1': 'LifeCare, Bodija Premier & Ring Road Private Surgical Clinics',
      'tier2': 'University College Hospital (UCH) Trauma Complex',
      'tier3Hotline': '+2348006963674',
    },
    RegionCluster.osunPilot: {
      'id': 'osun_pilot',
      'name': 'Osun State Pilot (OSEMSAS)',
      'state': 'Osun State',
      'centerLat': 7.7827,
      'centerLng': 4.5418,
      'tier1': 'Designated Osogbo & Ede Zonal Primary Health Centers',
      'tier2': 'UNIOSUN Teaching Hospital & Asubiaro State Hospital',
      'tier3Hotline': '+2348030006736',
    },
    RegionCluster.lagosMetro: {
      'id': 'lagos_metro',
      'name': 'Lagos Metropolitan Fleet',
      'state': 'Lagos State',
      'centerLat': 6.5244,
      'centerLng': 3.3792,
      'tier1': 'Accredited Ikeja & Lekki Corridor Private Maternal Units',
      'tier2': 'LASUTH Ikeja & LUTH Idi-Araba',
      'tier3Hotline': '112',
    },
  };

  /// Computes distance in kilometers between two GPS coordinates using Haversine formula.
  static double distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const double p = 0.017453292519943295; // Math.PI / 180
    final double a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
  }

  /// Classifies user coordinates to the closest operational cluster.
  static String resolveClusterId(double? lat, double? lng) {
    if (lat == null || lng == null) return 'ibadan_private';

    String closest = 'ibadan_private';
    double minDistance = double.infinity;

    for (final entry in clusterMetadata.entries) {
      final centerLat = entry.value['centerLat'] as double;
      final centerLng = entry.value['centerLng'] as double;
      final d = distanceKm(lat, lng, centerLat, centerLng);
      if (d < minDistance) {
        minDistance = d;
        closest = entry.value['id'] as String;
      }
    }
    return closest;
  }

  /// Formats clean standardized SBAR handover text with cluster header.
  static String formatSbarNote({
    required String clusterId,
    required String situation,
    required String background,
    required String assessment,
    required String recommendation,
    String? additionalNotes,
  }) {
    final sbar = '[CLUSTER: $clusterId] [SBAR: S: $situation | B: $background | A: $assessment | R: $recommendation]';
    if (additionalNotes != null && additionalNotes.trim().isNotEmpty) {
      return '$sbar Note: ${additionalNotes.trim()}';
    }
    return sbar;
  }
}
