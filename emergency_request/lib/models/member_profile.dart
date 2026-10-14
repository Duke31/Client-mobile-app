class MemberProfile {
  final String userId;
  final String fullName;
  final String phone;
  final String profileType; // 'maternal' | 'standard'
  final bool isPregnant;
  final int? gestationalWeeks;
  final String? edd; // Estimated Due Date (YYYY-MM-DD)
  final String? lmpDate; // Last Menstrual Period Date (YYYY-MM-DD)
  final String? gravidaPara; // e.g. "G2P1"
  final String? bloodGroup; // Plain ABO/Rh symbol: "A+", "O-", etc.
  final String? genotype; // Optional: "AA", "AS", "SS", etc.
  final String? dateOfBirth; // ISO date string (YYYY-MM-DD)
  final String? ageBand; // '0-1', '2-12', '13-17', '18-39', '40-64', '65+'
  final String? preferredHospitalId;
  final String? preferredHospitalName;
  final List<String> knownRisks;
  final String? allergies;
  final String? chronicConditions;
  final String? nextOfKinName;
  final String? nextOfKinPhone;

  const MemberProfile({
    required this.userId,
    this.fullName = '',
    this.phone = '',
    this.profileType = 'standard',
    this.isPregnant = false,
    this.gestationalWeeks,
    this.edd,
    this.lmpDate,
    this.gravidaPara,
    this.bloodGroup,
    this.genotype,
    this.dateOfBirth,
    this.ageBand,
    this.preferredHospitalId,
    this.preferredHospitalName,
    this.knownRisks = const [],
    this.allergies,
    this.chronicConditions,
    this.nextOfKinName,
    this.nextOfKinPhone,
  });

  bool get isMaternal => profileType == 'maternal' || isPregnant;
  String get carePlan => isMaternal ? 'maternal' : 'standard';

  /// Plain ABO/Rh blood groups supported in the clinical emergency network
  static const List<String> validBloodGroups = [
    'Unknown',
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  /// Standard emergency age bands matching backend constraints
  static const List<Map<String, String>> ageBandOptions = [
    {'value': '0-1', 'label': '0–1 yr (Infant)'},
    {'value': '2-12', 'label': '2–12 yrs (Child)'},
    {'value': '13-17', 'label': '13–17 yrs (Teen)'},
    {'value': '18-39', 'label': '18–39 yrs (Adult)'},
    {'value': '40-64', 'label': '40–64 yrs (Mature)'},
    {'value': '65+', 'label': '65+ yrs (Senior)'},
  ];

  /// Common user-declared maternal risk factors (for paramedic awareness, not clinical diagnoses)
  static const List<String> maternalRiskOptions = [
    'Previous C-Section',
    'Gestational Hypertension',
    'Gestational Diabetes',
    'Multiple Gestation (Twins)',
    'History of Pre-Eclampsia',
    'Previous Preterm Birth',
    'Anemia in Pregnancy',
  ];

  /// Robust sanitizer that strips legacy suffixes (e.g. "(Rare Blood Shield)")
  /// and normalizes strictly to canonical medical symbols (O-, O+, A-, A+, B-, B+, AB-, AB+).
  static String sanitizeBloodGroup(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    String cleaned = raw.trim();
    cleaned = cleaned.replaceAll(RegExp(r'\(.*?\)', caseSensitive: false), '').trim();
    cleaned = cleaned.replaceAll(
      RegExp(r'\b(Rare|Blood|Shield|Reserve|Rh-Negative|Rh-Positive|Standard|Universal)\b', caseSensitive: false),
      '',
    ).trim();
    final match = RegExp(r'^(AB|A|B|O)[\+\-]?$', caseSensitive: false).firstMatch(cleaned);
    if (match != null) {
      return match.group(0)!.toUpperCase();
    }
    if (cleaned.contains('-') || cleaned.toLowerCase().contains('neg')) {
      final base = RegExp(r'(AB|A|B|O)', caseSensitive: false).firstMatch(cleaned);
      if (base != null) return '${base.group(0)!.toUpperCase()}-';
    } else if (cleaned.contains('+') || cleaned.toLowerCase().contains('pos')) {
      final base = RegExp(r'(AB|A|B|O)', caseSensitive: false).firstMatch(cleaned);
      if (base != null) return '${base.group(0)!.toUpperCase()}+';
    }
    return cleaned.isNotEmpty ? cleaned : '';
  }

  /// Cleaned canonical blood group without marketing suffixes (e.g. "O-", "A+")
  String get cleanBloodGroup => sanitizeBloodGroup(bloodGroup);

  /// Plain string of blood group for display
  String get bloodGroupDisplay => cleanBloodGroup.isNotEmpty ? cleanBloodGroup : (bloodGroup ?? 'Unknown');

  /// Honest clinical status label (plain symbol only)
  String get bloodRhesusStatusLabel {
    final bg = cleanBloodGroup;
    if (bg.isEmpty || bg == 'Unknown') return 'Not Logged';
    return bg;
  }

  /// Clean display for emergency dispatch
  String get emergencyBloodReserveDisplay {
    final bg = cleanBloodGroup;
    if (bg.isEmpty || bg == 'Unknown') return 'Not Logged';
    return bg;
  }

  /// Derive patient age in complete years from date_of_birth
  int? get derivedAge {
    if (dateOfBirth == null || dateOfBirth!.trim().isEmpty) return null;
    final dob = DateTime.tryParse(dateOfBirth!.trim());
    if (dob == null) return null;
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age >= 0 ? age : null;
  }

  /// Derive dispatch age band ('0-1', '2-12', '13-17', '18-39', '40-64', '65+')
  String get effectiveAgeBand {
    final age = derivedAge;
    if (age != null) {
      if (age <= 1) return '0-1';
      if (age <= 12) return '2-12';
      if (age <= 17) return '13-17';
      if (age <= 39) return '18-39';
      if (age <= 64) return '40-64';
      return '65+';
    }
    if (ageBand != null && ageBand!.trim().isNotEmpty) {
      return ageBand!.trim();
    }
    return '18-39';
  }

  /// Total human pregnancy duration in obstetrics: 40 weeks = 280 days from LMP.
  /// Centralized calculation engine:
  /// - From LMP: clamp(days_since_lmp, 7, 294)
  /// - From EDD: clamp(280 - days_until_edd, 7, 294)
  /// - Fallback: gestationalWeeks * 7 or 224 (32 weeks baseline)
  int get computedElapsedDays {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (lmpDate != null && lmpDate!.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(lmpDate!.trim());
      if (parsed != null) {
        final lmpDay = DateTime(parsed.year, parsed.month, parsed.day);
        final elapsed = today.difference(lmpDay).inDays;
        return elapsed.clamp(7, 294);
      }
    }

    if (edd != null && edd!.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(edd!.trim());
      if (parsed != null) {
        final eddDay = DateTime(parsed.year, parsed.month, parsed.day);
        final daysUntilDue = eddDay.difference(today).inDays;
        final elapsed = 280 - daysUntilDue;
        return elapsed.clamp(7, 294);
      }
    }

    if (gestationalWeeks != null && gestationalWeeks! > 0) {
      return (gestationalWeeks! * 7).clamp(7, 294);
    }

    return 224; // Default clinical baseline: 32 weeks
  }

  int get computedWeeks => (computedElapsedDays ~/ 7).clamp(1, 42);
  int get computedDays => (computedElapsedDays % 7).clamp(0, 6);
  int get pregnancyDay => computedElapsedDays;
  int get daysRemainingToEdd => (280 - computedElapsedDays).clamp(0, 280);

  String get trimesterLabel {
    final w = computedWeeks;
    if (w <= 13) return '1st Trimester';
    if (w <= 27) return '2nd Trimester';
    return '3rd Trimester';
  }

  String get gestationalSummary {
    if (!isMaternal) return 'Standard Emergency Care';
    return 'Week $computedWeeks, Day $computedDays • $trimesterLabel';
  }

  String get preferredHospitalDisplay {
    if (preferredHospitalName == null || preferredHospitalName!.trim().isEmpty) {
      return 'Auto-Select (Nearest Capable Facility)';
    }
    return '${preferredHospitalName!.trim()} (Preference only)';
  }

  Map<String, String> get babyFruitComparison {
    final weeks = computedWeeks;
    if (weeks <= 8) {
      return {'fruit': 'Raspberry', 'weight': '~1 g', 'length': '1.6 cm', 'icon': '🫐'};
    } else if (weeks <= 12) {
      return {'fruit': 'Plum', 'weight': '~14 g', 'length': '5.4 cm', 'icon': '🍑'};
    } else if (weeks <= 16) {
      return {'fruit': 'Avocado', 'weight': '~100 g', 'length': '11.6 cm', 'icon': '🥑'};
    } else if (weeks <= 20) {
      return {'fruit': 'Banana', 'weight': '~300 g', 'length': '25 cm', 'icon': '🍌'};
    } else if (weeks <= 24) {
      return {'fruit': 'Cantaloupe Melon', 'weight': '~600 g', 'length': '30 cm', 'icon': '🍈'};
    } else if (weeks <= 28) {
      return {'fruit': 'Eggplant', 'weight': '~1.0 kg', 'length': '37 cm', 'icon': '🍆'};
    } else if (weeks <= 32) {
      return {'fruit': 'Sweet Pineapple', 'weight': '~1.8 kg', 'length': '42 cm', 'icon': '🍍'};
    } else if (weeks <= 36) {
      return {'fruit': 'Honeydew Papaya', 'weight': '~2.6 kg', 'length': '47 cm', 'icon': '🥭'};
    } else {
      return {'fruit': 'Watermelon', 'weight': '~3.4 kg', 'length': '51 cm', 'icon': '🍉'};
    }
  }

  factory MemberProfile.fromMap(Map<String, dynamic> map, String fallbackUserId) {
    final rawType = (map['care_plan']?.toString() ??
            map['profile_type']?.toString() ??
            map['subscription_tier']?.toString() ??
            map['plan']?.toString() ??
            map['tier']?.toString() ??
            '')
        .toLowerCase();
    final isPreg = map['is_pregnant'] == true || rawType.contains('maternal');
    final pType = isPreg ? 'maternal' : 'standard';

    List<String> parseRisks(dynamic raw) {
      if (raw == null) return [];
      if (raw is List) return raw.map((e) => e.toString()).toList();
      if (raw is String && raw.trim().isNotEmpty) {
        return raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
      return [];
    }

    final rawHosp = map['preferred_hospital']?.toString() ??
        map['preferred_hospital_name']?.toString();
    final cleanHosp = (rawHosp == null ||
            rawHosp.trim().isEmpty ||
            rawHosp.toLowerCase().contains('auto-select') ||
            rawHosp.toLowerCase().contains('none /') ||
            rawHosp.toLowerCase().contains('nearest capable'))
        ? null
        : rawHosp.trim();

    return MemberProfile(
      userId: map['user_id']?.toString() ?? fallbackUserId,
      fullName: map['full_name']?.toString() ?? map['display_name']?.toString() ?? '',
      phone: map['phone']?.toString() ?? map['phone_number']?.toString() ?? '',
      profileType: pType,
      isPregnant: isPreg,
      gestationalWeeks: (map['gestational_weeks'] as num?)?.toInt(),
      edd: map['edd']?.toString(),
      lmpDate: map['lmp_date']?.toString() ?? map['lmp']?.toString(),
      gravidaPara: map['gravida_para']?.toString() ?? map['parity']?.toString(),
      bloodGroup: sanitizeBloodGroup(map['blood_group']?.toString()),
      genotype: map['genotype']?.toString(),
      dateOfBirth: map['date_of_birth']?.toString() ?? map['dob']?.toString(),
      ageBand: map['age_band']?.toString(),
      preferredHospitalId: map['preferred_hospital_id']?.toString(),
      preferredHospitalName: cleanHosp,
      knownRisks: parseRisks(map['known_risks']),
      allergies: map['allergies']?.toString(),
      chronicConditions: map['chronic_conditions']?.toString(),
      nextOfKinName: map['next_of_kin_name']?.toString(),
      nextOfKinPhone: map['next_of_kin_phone']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'full_name': fullName,
      'display_name': fullName,
      'phone': phone,
      'profile_type': profileType,
      'care_plan': carePlan,
      'is_pregnant': isMaternal,
      'gestational_weeks': isMaternal ? computedWeeks : null,
      'edd': isMaternal ? edd : null,
      'lmp_date': isMaternal ? lmpDate : null,
      'gravida_para': isMaternal ? gravidaPara : null,
      'blood_group': cleanBloodGroup.isNotEmpty ? cleanBloodGroup : null,
      'genotype': genotype,
      'date_of_birth': dateOfBirth,
      'age_band': effectiveAgeBand,
      'preferred_hospital_id': preferredHospitalId,
      'preferred_hospital': preferredHospitalName,
      'known_risks': isMaternal ? knownRisks : null,
      'allergies': allergies,
      'chronic_conditions': chronicConditions,
      'next_of_kin_name': nextOfKinName,
      'next_of_kin_phone': nextOfKinPhone,
    };
  }

  /// Strictly filtered map containing only columns known to exist in public.profiles table
  Map<String, dynamic> toProfilesDbMap() {
    return {
      'user_id': userId,
      'display_name': fullName.isNotEmpty ? fullName : 'Solace Member',
      'full_name': fullName.isNotEmpty ? fullName : 'Solace Member',
      'phone': phone.isNotEmpty ? phone : null,
      'role': 'client',
      'profile_type': isMaternal ? 'maternal' : 'standard',
      'is_pregnant': isMaternal,
      'gestational_weeks': isMaternal ? computedWeeks : null,
      'edd': isMaternal ? edd : null,
      'gravida_para': isMaternal ? gravidaPara : null,
      'blood_group': cleanBloodGroup.isNotEmpty ? cleanBloodGroup : null,
      'genotype': genotype,
      'age_band': effectiveAgeBand,
      'preferred_hospital': preferredHospitalName,
      'known_risks': isMaternal ? knownRisks : null,
      'allergies': allergies,
      'chronic_conditions': chronicConditions,
      'next_of_kin_name': nextOfKinName,
      'next_of_kin_phone': nextOfKinPhone,
    };
  }
}
