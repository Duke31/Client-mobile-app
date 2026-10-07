/// Maps UI labels to DB CHECK-allowed emergency_type values.
/// Allowed in database: Trauma, Cardiac, Stroke, Respiratory, Obstetric, Pediatric, Psychiatric, Other
class EmergencyTypeNormalizer {
  const EmergencyTypeNormalizer._();

  static const allowed = <String>{
    'Trauma',
    'Cardiac',
    'Stroke',
    'Respiratory',
    'Obstetric',
    'Pediatric',
    'Psychiatric',
    'Other',
  };

  /// Returns (dbType, extraClinicalNote).
  static (String type, String? note) normalize(String raw) {
    final t = raw.trim();
    if (allowed.contains(t)) return (t, null);

    switch (t.toLowerCase()) {
      case 'accident':
      case 'road accident':
      case 'road crash':
      case 'car crash':
      case 'road crash / fall':
      case 'trauma / bleeding':
        return ('Trauma', 'Incident: Vehicle Accident / Road Crash');

      case 'allergy':
      case 'allergic reaction':
      case 'severe allergy':
      case 'severe anaphylaxis':
      case 'anaphylaxis':
        return ('Other', 'Condition: Severe Anaphylaxis / Allergic Reaction');

      case 'cardiac':
      case 'cardiac / heart':
      case 'chest pain':
      case 'heart attack':
        return ('Cardiac', null);

      case 'breathing':
      case 'respiratory':
      case 'breathing / lungs':
      case 'asthma':
      case 'choking':
        return ('Respiratory', null);

      case 'stroke':
      case 'stroke / neuro':
        return ('Stroke', null);

      case 'maternity':
      case 'obstetric':
      case 'maternity / labor':
      case 'pregnancy':
        return ('Obstetric', null);

      case 'pediatric':
      case 'child emergency':
        return ('Pediatric', null);

      case 'general emergency':
      case 'other':
      default:
        return ('Other', 'Emergency: $t');
    }
  }
}
