class MemberProfile {
  final String userId;
  final String fullName;
  final String phone;
  final String profileType; // 'maternal' | 'standard'
  final bool isPregnant;
  final int? gestationalWeeks;
  final String? edd; // Estimated Due Date
  final String? lmpDate; // Last Menstrual Period Date
  final String? gravidaPara; // e.g. "G2P1"
  final String? bloodGroup;
  final String? genotype; // "AA", "AS", "SS", etc.
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

  /// Robust clinical sanitizer that strips legacy suffixes (e.g. "(Rare Blood Shield)")
  /// and normalizes strictly to canonical medical symbols (O-, O+, A-, A+, B-, B+, AB-, AB+).
  static String sanitizeBloodGroup(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    String cleaned = raw.trim();
    // Strip parenthesized suffixes like (Rare Blood Shield), (Rare Rh-Negative Reserve), etc.
    cleaned = cleaned.replaceAll(RegExp(r'\(.*?\)', caseSensitive: false), '').trim();
    // Strip redundant words
    cleaned = cleaned.replaceAll(RegExp(r'\b(Rare|Blood|Shield|Reserve|Rh-Negative|Rh-Positive|Standard)\b', caseSensitive: false), '').trim();
    // Match standard ABO/Rh combinations
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
    return cleaned.isNotEmpty ? cleaned : 'O-';
  }

  /// Cleaned canonical blood group without redundant parenthesized tags (e.g. "O-", "A+")
  String get cleanBloodGroup => sanitizeBloodGroup(bloodGroup);

  /// Clinical Rhesus status detection: Rh-negative patients require anti-D prophylaxis
  /// and verified O-Negative emergency blood reserves.
  bool get isRhesusNegative {
    final bg = cleanBloodGroup;
    return bg.contains('-') || bg.toLowerCase().contains('neg');
  }

  /// Backward-compatible alias for rare blood grouping
  bool get isRareBlood => isRhesusNegative;

  /// Standardized clinical status badge
  String get bloodRhesusStatusLabel {
    final bg = cleanBloodGroup;
    if (bg.isEmpty) return 'Blood Group Not Logged';
    if (isRhesusNegative) {
      return '$bg (Rare Rh-Negative Reserve)';
    }
    return '$bg (Universal Rh+ Reserve)';
  }

  /// Clean one-line display for emergency blood reserve desks
  String get emergencyBloodReserveDisplay {
    final bg = cleanBloodGroup;
    if (bg.isEmpty) return 'Reserve Not Logged';
    if (isRhesusNegative) {
      return '$bg • Rare Rh-Negative Reserve';
    }
    return '$bg • Universal Reserve';
  }

  /// Clean string of blood group for display
  String get bloodGroupDisplay => cleanBloodGroup.isNotEmpty ? cleanBloodGroup : (bloodGroup ?? 'Not Set');

  /// Total human pregnancy duration in obstetrics: 40 weeks = 280 days from LMP.
  /// Centralized calculation engine adhering to LAB_PROMPT_maternal_library.md:
  /// - From LMP: clamp(days_since_lmp / 7, 1, 42)
  /// - From EDD: clamp(40 - days_until_edd / 7, 1, 42)
  /// - From gestationalWeeks: clamp(weeks, 1, 42)
  /// Clamped strictly between 1 and 42 weeks (7 to 294 days).
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

    return 224; // Default clinical baseline: 32 weeks (224 days)
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
      return 'Auto-Select (Nearest Capable L&D Hub)';
    }
    return preferredHospitalName!.trim();
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
      'is_pregnant': isPregnant,
      'gestational_weeks': gestationalWeeks,
      'edd': edd,
      'lmp_date': lmpDate,
      'gravida_para': gravidaPara,
      'blood_group': cleanBloodGroup.isNotEmpty ? cleanBloodGroup : bloodGroup,
      'genotype': genotype,
      'preferred_hospital_id': preferredHospitalId,
      'preferred_hospital': preferredHospitalName,
      'known_risks': knownRisks,
      'allergies': allergies,
      'chronic_conditions': chronicConditions,
      'next_of_kin_name': nextOfKinName,
      'next_of_kin_phone': nextOfKinPhone,
    };
  }
}
