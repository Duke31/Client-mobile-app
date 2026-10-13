import 'dart:convert';
import 'package:flutter/foundation.dart';

class KickRecord {
  final DateTime timestamp;
  const KickRecord(this.timestamp);
}

class MaternalCareService extends ChangeNotifier {
  static final MaternalCareService _instance = MaternalCareService._internal();
  factory MaternalCareService() => _instance;
  MaternalCareService._internal();

  // Daily Kick Tracker
  int _kicksCount = 0;
  DateTime? _sessionStartTime;
  final List<DateTime> _kickTimestamps = [];
  bool _escalationAlertActive = false;

  int get kicksCount => _kicksCount;
  DateTime? get sessionStartTime => _sessionStartTime;
  List<DateTime> get kickTimestamps => List.unmodifiable(_kickTimestamps);
  bool get escalationAlertActive => _escalationAlertActive;

  // Clinical target: 10 kicks in 2 hours
  static const int targetKicks = 10;
  static const Duration sessionWindow = Duration(hours: 2);

  bool get targetReached => _kicksCount >= targetKicks;

  Duration get sessionElapsed {
    if (_sessionStartTime == null) return Duration.zero;
    return DateTime.now().difference(_sessionStartTime!);
  }

  bool get isSessionWindowExpired {
    if (_sessionStartTime == null) return false;
    return sessionElapsed > sessionWindow;
  }

  void recordKick() {
    final now = DateTime.now();
    if (_sessionStartTime == null || isSessionWindowExpired) {
      // Start or reset session
      _sessionStartTime = now;
      _kicksCount = 1;
      _kickTimestamps.clear();
      _kickTimestamps.add(now);
      _escalationAlertActive = false;
    } else {
      _kicksCount++;
      _kickTimestamps.add(now);
    }

    // Check if 2 hours passed with fewer than 10 kicks
    _checkEscalationCondition();
    notifyListeners();
  }

  void resetKickSession() {
    _kicksCount = 0;
    _sessionStartTime = null;
    _kickTimestamps.clear();
    _escalationAlertActive = false;
    notifyListeners();
  }

  void _checkEscalationCondition() {
    if (_sessionStartTime != null && isSessionWindowExpired && _kicksCount < targetKicks) {
      _escalationAlertActive = true;
    } else {
      _escalationAlertActive = false;
    }
  }

  // Daily Routine & Supplements
  bool _ironFolicTakenToday = false;
  DateTime? _lastIronFolicDate;

  bool get ironFolicTakenToday {
    if (_lastIronFolicDate == null) return false;
    final now = DateTime.now();
    return _lastIronFolicDate!.year == now.year &&
        _lastIronFolicDate!.month == now.month &&
        _lastIronFolicDate!.day == now.day;
  }

  void toggleIronFolic(bool value) {
    if (value) {
      _lastIronFolicDate = DateTime.now();
      _ironFolicTakenToday = true;
    } else {
      _lastIronFolicDate = null;
      _ironFolicTakenToday = false;
    }
    notifyListeners();
  }

  // Daily Evidence-Based Guidelines
  static const List<Map<String, String>> maternalTips = [
    {
      'title': 'Placental Blood Flow (Sleep Position)',
      'summary':
          'Resting on your left side optimizes oxygen and nutrient delivery through the inferior vena cava to the placenta and baby.',
      'tag': 'Clinical Best Practice',
    },
    {
      'title': 'Amniotic Fluid Volume & Hydration',
      'summary':
          'Aim for 2.5 to 3 liters of clean water daily. Proper hydration supports adequate amniotic fluid levels and reduces Braxton Hicks contractions.',
      'tag': 'Maternal Physiology',
    },
    {
      'title': 'Pre-Eclampsia Vigilance: Headaches & Vision',
      'summary':
          'Severe persistent frontal headache, visual spots/flashing, or sudden hand/facial swelling can indicate elevated blood pressure. Immediate clinical review is essential.',
      'tag': 'Red Flag Warning',
    },
    {
      'title': 'Iron & Vitamin C Synergism',
      'summary':
          'Take your ferrous sulfate supplement with citrus water or oranges to maximize intestinal absorption and prevent maternal anemia during rapid fetal growth.',
      'tag': 'Nutrition Guidance',
    },
  ];

  static const List<Map<String, String>> standardFirstAidTips = [
    {
      'title': 'FAST Stroke Recognition',
      'summary':
          'Face drooping, Arm weakness, Speech difficulty, Time to call Solace. Rapid intervention within the 3-hour golden window preserves brain tissue.',
      'tag': 'Neuro Emergency',
    },
    {
      'title': 'Arterial Bleeding: Direct Continuous Pressure',
      'summary':
          'Apply firm, unrelenting pressure with clean gauze directly on the wound. Do not remove saturated pads—layer fresh dressings on top and elevate the limb.',
      'tag': 'Trauma Protocol',
    },
    {
      'title': 'Acute Chest Pain: Rest & Aspirin Protocol',
      'summary':
          'Keep patient seated at a 45-degree angle. Restrict physical exertion immediately and trigger Solace EMS dispatch for direct Cardiac bay transfer.',
      'tag': 'Cardiovascular Alert',
    },
    {
      'title': 'Heat Exhaustion vs Heat Stroke',
      'summary':
          'Confusion, hot red dry skin, and vomiting signify life-threatening heat stroke. Cool immediately with wet cloths and fan the skin while awaiting ambulance response.',
      'tag': 'Environmental',
    },
  ];
}
