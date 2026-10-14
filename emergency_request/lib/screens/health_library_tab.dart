import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/member_profile.dart';
import '../models/maternal_content_item.dart';
import '../services/maternal_content_service.dart';
import '../theme/app_theme.dart';

class HealthLibraryTab extends StatefulWidget {
  final Function(String condition, int priority) onDispatchCondition;
  final MemberProfile? profile;
  final VoidCallback? onTriggerSos;

  const HealthLibraryTab({
    super.key,
    required this.onDispatchCondition,
    this.profile,
    this.onTriggerSos,
  });

  @override
  State<HealthLibraryTab> createState() => _HealthLibraryTabState();
}

enum _InsightMode { wellnessTracker, clinicalRedFlags }
enum _ChartViewMode { capsuleBars, trendCurve }

class _DailyMoodRecord {
  final String dayName;
  final int dayNumber;
  final int moodScore; // 1 to 5 (0 = unlogged)
  final String label;
  final String emoji;
  final Color color;

  const _DailyMoodRecord({
    required this.dayName,
    required this.dayNumber,
    required this.moodScore,
    required this.label,
    required this.emoji,
    required this.color,
  });
}

class _HealthLibraryTabState extends State<HealthLibraryTab> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final MaternalContentService _contentService = MaternalContentService();

  _InsightMode _currentMode = _InsightMode.wellnessTracker;
  _ChartViewMode _chartMode = _ChartViewMode.capsuleBars;

  // Selected mood today (1: Awful, 2: Bad, 3: Okay, 4: Good, 5: Great, 0: Unlogged)
  int _todayMoodScore = 0;
  int _selectedDayIndex = 0;

  // Daily maternal wellness counters
  int _fetalKicksToday = 0;
  int _waterGlassesToday = 0;
  int _sleepHoursToday = 8;
  bool _vitaminsTakenToday = false;

  // Canonical Daily Clinical Tip loaded from single source library
  List<MaternalContentItem> _dailyGuidanceCards = [];
  bool _loadingGuidance = true;

  // Real saved records map keyed by YYYY-MM-DD
  final Map<String, Map<String, dynamic>> _savedDailyRecords = {};
  bool _recordsLoaded = false;

  late List<_DailyMoodRecord> _weekData;

  String _dateKey(DateTime dt) {
    final m = dt.month < 10 ? '0${dt.month}' : '${dt.month}';
    final d = dt.day < 10 ? '0${dt.day}' : '${dt.day}';
    return '${dt.year}-$m-$d';
  }

  List<DateTime> get _currentWeekDates {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return List.generate(7, (i) => DateTime(monday.year, monday.month, monday.day + i));
  }

  String get _weekRangeLabel {
    final dates = _currentWeekDates;
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    final start = dates.first;
    final end = dates.last;
    return 'This week • ${months[start.month - 1]} ${start.day} - ${months[end.month - 1]} ${end.day}';
  }

  String get _currentMonthName {
    final now = DateTime.now();
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[now.month - 1];
  }

  String get _currentMonthYearAbbr {
    final now = DateTime.now();
    const m = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    return '${m[now.month - 1]} ${now.year}';
  }

  @override
  void initState() {
    super.initState();
    _selectedDayIndex = DateTime.now().weekday - 1;
    _buildWeekData();
    _loadSavedRecords();
    _loadDailyTip();
  }

  @override
  void didUpdateWidget(covariant HealthLibraryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile?.computedWeeks != widget.profile?.computedWeeks) {
      _loadDailyTip();
    }
  }

  Future<void> _loadDailyTip() async {
    final weeks = widget.profile?.computedWeeks ?? 28;
    try {
      final cards = await _contentService.getDailyGuidanceCards(
        gestationalWeek: weeks,
      );
      if (mounted) {
        setState(() {
          _dailyGuidanceCards = cards;
          _loadingGuidance = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingGuidance = false);
      }
    }
  }

  Future<void> _loadSavedRecords() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final meta = user.userMetadata;
      if (meta != null && meta['maternal_checkins'] is Map) {
        final recs = Map<String, dynamic>.from(meta['maternal_checkins'] as Map);
        recs.forEach((k, v) {
          if (v is Map) {
            _savedDailyRecords[k] = Map<String, dynamic>.from(v);
          }
        });
      }

      final res = await _supabase
          .from('profiles')
          .select('maternal_records')
          .eq('user_id', user.id)
          .maybeSingle();

      if (res != null && res['maternal_records'] is Map) {
        final recs = Map<String, dynamic>.from(res['maternal_records'] as Map);
        recs.forEach((k, v) {
          if (v is Map) {
            _savedDailyRecords[k] = Map<String, dynamic>.from(v);
          }
        });
      }
    } catch (_) {}

    if (mounted) {
      _applyCurrentDaySelection();
    }
  }

  void _applyCurrentDaySelection() {
    final todayKey = _dateKey(DateTime.now());
    final todayRec = _savedDailyRecords[todayKey];
    if (todayRec != null) {
      _todayMoodScore = (todayRec['mood'] as num?)?.toInt() ?? 0;
      _fetalKicksToday = (todayRec['kicks'] as num?)?.toInt() ?? 0;
      _waterGlassesToday = (todayRec['water'] as num?)?.toInt() ?? 0;
      _sleepHoursToday = (todayRec['sleep'] as num?)?.toInt() ?? 8;
      _vitaminsTakenToday = todayRec['vitamins'] == true;
    } else {
      _todayMoodScore = 0;
      _fetalKicksToday = 0;
      _waterGlassesToday = 0;
      _sleepHoursToday = 8;
      _vitaminsTakenToday = false;
    }
    _recordsLoaded = true;
    _buildWeekData();
    setState(() {});
  }

  void _buildWeekData() {
    final weekDates = _currentWeekDates;
    const dayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

    _weekData = List.generate(7, (i) {
      final dt = weekDates[i];
      final key = _dateKey(dt);
      final rec = _savedDailyRecords[key];
      final score = (rec?['mood'] as num?)?.toInt() ?? 0;

      return _DailyMoodRecord(
        dayName: dayNames[i],
        dayNumber: dt.day,
        moodScore: score,
        label: _getMoodLabel(score),
        emoji: _getMoodEmoji(score),
        color: _getMoodColor(score),
      );
    });
  }

  Future<void> _saveCheckin({int? mood, int? kicks, int? water, int? sleep, bool? vitamins}) async {
    HapticFeedback.mediumImpact();
    final now = DateTime.now();
    final todayKey = _dateKey(now);

    final updated = {
      'mood': mood ?? _todayMoodScore,
      'kicks': kicks ?? _fetalKicksToday,
      'water': water ?? _waterGlassesToday,
      'sleep': sleep ?? _sleepHoursToday,
      'vitamins': vitamins ?? _vitaminsTakenToday,
      'timestamp': DateTime.now().toIso8601String(),
    };

    setState(() {
      _savedDailyRecords[todayKey] = updated;
      if (mood != null) _todayMoodScore = mood;
      if (kicks != null) _fetalKicksToday = kicks;
      if (water != null) _waterGlassesToday = water;
      if (sleep != null) _sleepHoursToday = sleep;
      if (vitamins != null) _vitaminsTakenToday = vitamins;
      _buildWeekData();
    });

    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    try {
      await _supabase.auth.updateUser(
        UserAttributes(
          data: {
            'maternal_checkins': _savedDailyRecords,
            'last_maternal_checkin': todayKey,
          },
        ),
      );
      await _supabase.from('profiles').update({
        'maternal_records': _savedDailyRecords,
      }).eq('user_id', uid);

      // Upsert into maternal_wellness_logs with owner-only RLS
      await _supabase.from('maternal_wellness_logs').upsert({
        'user_id': uid,
        'log_date': todayKey,
        'mood_score': mood ?? _todayMoodScore,
        'kicks_count': kicks ?? _fetalKicksToday,
        'water_glasses': water ?? _waterGlassesToday,
        'sleep_hours': sleep ?? _sleepHoursToday,
        'vitamins_taken': vitamins ?? _vitaminsTakenToday,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  String _getMoodLabel(int score) {
    switch (score) {
      case 1: return 'Awful';
      case 2: return 'Bad';
      case 3: return 'Okay';
      case 4: return 'Good';
      case 5: return 'Great';
      default: return 'Unlogged';
    }
  }

  String _getMoodEmoji(int score) {
    switch (score) {
      case 1: return '😫';
      case 2: return '😔';
      case 3: return '😐';
      case 4: return '🙂';
      case 5: return '😄';
      default: return '';
    }
  }

  Color _getMoodColor(int score) {
    switch (score) {
      case 1: return const Color(0xFF8B5CF6);
      case 2: return const Color(0xFF38BDF8);
      case 3: return const Color(0xFFFACC15);
      case 4: return const Color(0xFF4ADE80);
      case 5: return const Color(0xFF22C55E);
      default: return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppTheme.darkBg : const Color(0xFFF8FAFC);
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final cardBorder = isDark ? AppTheme.darkCardBorder : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          _currentMode == _InsightMode.wellnessTracker
              ? 'Maternal Wellness & Insights'
              : 'Danger Protocols & Red Flags',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        backgroundColor: cardBg,
        elevation: 0,
        actions: [
          // Emergency SOS Action (Patient-facing, always reachable from Insights)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              onPressed: () {
                HapticFeedback.heavyImpact();
                if (widget.onTriggerSos != null) {
                  widget.onTriggerSos!();
                } else {
                  widget.onDispatchCondition('OBSTETRIC_EMERGENCY', 1);
                }
              },
              icon: const Icon(Icons.emergency_rounded, size: 14),
              label: const Text(
                'SOS',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Toggle View',
            icon: Icon(
              _currentMode == _InsightMode.wellnessTracker
                  ? Icons.warning_amber_rounded
                  : Icons.auto_graph_rounded,
              color: const Color(0xFFFF8A65),
            ),
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() {
                _currentMode = _currentMode == _InsightMode.wellnessTracker
                    ? _InsightMode.clinicalRedFlags
                    : _InsightMode.wellnessTracker;
              });
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Top Segmented Mode Switcher ────────────────────────────────
            _buildModeSwitcher(isDark),
            const SizedBox(height: 14),

            if (_currentMode == _InsightMode.wellnessTracker) ...[
              // Week / Baby Size Header
              if (widget.profile != null && widget.profile!.isMaternal) ...[
                _buildWeekProgressHeader(cardBg, textColor, isDark),
                const SizedBox(height: 14),
              ],

              // ── "When to get help" Row (Points to Danger Protocols) ───────
              _buildWhenToGetHelpRow(cardBg, textColor, isDark),
              const SizedBox(height: 14),

              // ── Canonical Read: Today's Clinical Tip & Library Guidance ────
              _buildCanonicalTipSection(cardBg, cardBorder, textColor, isDark),
              const SizedBox(height: 16),

              // ── 1. Daily Emotion Check-In ─────────────────────────────────
              _buildDailyCheckInCard(cardBg, cardBorder, textColor, isDark),
              const SizedBox(height: 16),

              // ── 2. Weekly Insights Capsule Bar Chart (Last 7 Days) ────────
              _buildWeeklyInsightsChartCard(cardBg, cardBorder, textColor, isDark),
              const SizedBox(height: 16),

              // ── 3. Today's Habits (Progress vs Goal, Zero Fabricated Risk) ─
              _buildDailyInfluencesSection(cardBg, cardBorder, textColor, isDark),
              const SizedBox(height: 16),

              // ── 4. Monthly Behaviour & Emotion Calendar ───────────────────
              _buildMonthlyCalendarCard(cardBg, cardBorder, textColor, isDark),
              const SizedBox(height: 20),
            ] else ...[
              // ── Danger Protocols: Clinical Red Flags & Emergency Dispatch ──
              _buildClinicalRedFlagsList(cardBg, cardBorder, textColor, isDark),
            ],
          ],
        ),
      ),
    );
  }

  // ── Segmented Mode Switcher ────────────────────────────────────────────────
  Widget _buildModeSwitcher(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _currentMode = _InsightMode.wellnessTracker);
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: _currentMode == _InsightMode.wellnessTracker
                      ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _currentMode == _InsightMode.wellnessTracker && !isDark
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('✨', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 5),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Daily Wellness',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: _currentMode == _InsightMode.wellnessTracker
                                ? const Color(0xFFFF8A65)
                                : (isDark ? Colors.white60 : const Color(0xFF64748B)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _currentMode = _InsightMode.clinicalRedFlags);
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: _currentMode == _InsightMode.clinicalRedFlags
                      ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _currentMode == _InsightMode.clinicalRedFlags && !isDark
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('🚨', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 5),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Danger Protocols',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: _currentMode == _InsightMode.clinicalRedFlags
                                ? const Color(0xFFDC2626)
                                : (isDark ? Colors.white60 : const Color(0xFF64748B)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Week Progress Header ───────────────────────────────────────────────────
  Widget _buildWeekProgressHeader(Color cardBg, Color textColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF8A65).withOpacity(0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Color(0xFFFF8A65),
              shape: BoxShape.circle,
            ),
            child: Text(
              widget.profile!.babyFruitComparison['icon'] ?? '👶',
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Week ${widget.profile!.computedWeeks}, Day ${widget.profile!.computedDays} • ${widget.profile!.trimesterLabel}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: textColor,
                  ),
                ),
                Text(
                  'Baby size: ${widget.profile!.babyFruitComparison['fruit']} (${widget.profile!.babyFruitComparison['weight']}) • Day ${widget.profile!.pregnancyDay} of 280',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── "When to get help" Row ─────────────────────────────────────────────────
  Widget _buildWhenToGetHelpRow(Color cardBg, Color textColor, bool isDark) {
    return InkWell(
      onTap: () {
        HapticFeedback.mediumImpact();
        setState(() => _currentMode = _InsightMode.clinicalRedFlags);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF261214) : const Color(0xFFFFF1F2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF881337) : const Color(0xFFFDA4AF),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFE11D48).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFE11D48),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'When to get help',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFE11D48),
                    ),
                  ),
                  Text(
                    'Bleeding, fluid leak, reduced movements, severe headache → Danger Protocols',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Color(0xFFE11D48),
              size: 13,
            ),
          ],
        ),
      ),
    );
  }

  // ── Canonical Read: Today's Clinical Guidance (Single Source Library) ─────
  Widget _buildCanonicalTipSection(Color cardBg, Color cardBorder, Color textColor, bool isDark) {
    if (_loadingGuidance) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cardBorder),
        ),
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A65))),
        ),
      );
    }

    if (_dailyGuidanceCards.isEmpty) return const SizedBox.shrink();

    // Prefer 1 tip; if safety matches today, show safety first or alongside tip
    final safetyCard = _dailyGuidanceCards.where((c) => c.isSafety).firstOrNull;
    final tipCard = _dailyGuidanceCards.where((c) => c.isTip).firstOrNull ?? _dailyGuidanceCards.firstOrNull;

    final cardsToShow = <MaternalContentItem>[];
    if (safetyCard != null) cardsToShow.add(safetyCard);
    if (tipCard != null && tipCard != safetyCard) cardsToShow.add(tipCard);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.menu_book_rounded, size: 16, color: Color(0xFFFF8A65)),
            const SizedBox(width: 6),
            Text(
              "Today's Guidance",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
            const Spacer(),
            Text(
              'Week ${widget.profile?.computedWeeks ?? 28} Protocol',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        for (final item in cardsToShow) ...[
          _buildFullTipCard(item, cardBg, textColor, isDark),
          const SizedBox(height: 10),
        ],

        // Educational Disclaimer Container
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cardBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF64748B)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  MaternalContentService.educationalDisclaimer,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFullTipCard(MaternalContentItem item, Color cardBg, Color textColor, bool isDark) {
    final isSafety = item.isSafety;
    final bg = isSafety
        ? (isDark ? const Color(0xFF261214) : const Color(0xFFFFF1F2))
        : cardBg;
    final border = isSafety
        ? (isDark ? const Color(0xFF881337) : const Color(0xFFFDA4AF))
        : (isDark ? AppTheme.darkCardBorder : const Color(0xFFE2E8F0));
    final tagBg = isSafety
        ? const Color(0xFFE11D48).withOpacity(0.15)
        : const Color(0xFF0D9488).withOpacity(0.12);
    final tagColor = isSafety ? const Color(0xFFE11D48) : const Color(0xFF0D9488);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border, width: isSafety ? 1.4 : 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tagBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isSafety ? Icons.warning_amber_rounded : Icons.lightbulb_outline_rounded, size: 12, color: tagColor),
                    const SizedBox(width: 4),
                    Text(
                      item.slotDisplayLabel,
                      style: TextStyle(
                        color: tagColor,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (item.weekday != null)
                Text(
                  _weekdayName(item.weekday!),
                  style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.title,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.body,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: isDark ? Colors.white70 : const Color(0xFF334155),
            ),
          ),
          if (item.ctaType != 'none' && item.ctaLabel != null && item.ctaLabel!.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: isSafety ? const Color(0xFFE11D48) : const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  HapticFeedback.heavyImpact();
                  if (item.ctaType == 'sos' || item.ctaType == 'red_flag') {
                    if (widget.onTriggerSos != null) {
                      widget.onTriggerSos!();
                    } else {
                      widget.onDispatchCondition('OBSTETRIC_EMERGENCY', 1);
                    }
                  } else if (item.ctaType == 'profile') {
                    // Profile/Medical ID action
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Open Medical ID tab to review emergency card')),
                    );
                  }
                },
                icon: Icon(isSafety ? Icons.emergency_rounded : Icons.arrow_forward_rounded, size: 16),
                label: Text(
                  item.ctaLabel!,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 1. Daily Emotion Check-In ──────────────────────────────────────────────
  Widget _buildDailyCheckInCard(Color cardBg, Color cardBorder, Color textColor, bool isDark) {
    final subText = isDark ? Colors.white60 : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'How are you feeling today?',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _todayMoodScore > 0 ? _getMoodLabel(_todayMoodScore) : 'Not logged',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _todayMoodScore > 0 ? _getMoodColor(_todayMoodScore) : subText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'One log per day. Track changes across your week.',
            style: TextStyle(fontSize: 11, color: subText),
          ),
          const SizedBox(height: 16),

          // 5 Mood Emoji Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (index) {
              final score = index + 1;
              final isSelected = _todayMoodScore == score;
              final emoji = _getMoodEmoji(score);
              final label = _getMoodLabel(score);
              final moodCol = _getMoodColor(score);

              return Expanded(
                child: GestureDetector(
                  onTap: () => _saveCheckin(mood: score),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? moodCol.withOpacity(isDark ? 0.35 : 0.18)
                          : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? moodCol : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                        width: isSelected ? 2.0 : 1.0,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(emoji, style: const TextStyle(fontSize: 22)),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500,
                            color: isSelected ? (isDark ? Colors.white : moodCol) : subText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),

          // Soft Prompt for Awful (1) or Bad (2) Mood (Strictly supportive, never auto-diagnosing)
          if (_todayMoodScore == 1 || _todayMoodScore == 2) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFF8A65).withOpacity(0.4),
                ),
              ),
              child: Row(
                children: [
                  const Text('💛', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Having a difficult day? If you feel physically unwell, experience severe pain, or something feels wrong, check Danger Protocols or reach emergency care.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white70 : const Color(0xFF475569),
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      setState(() => _currentMode = _InsightMode.clinicalRedFlags);
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text(
                      'Protocols',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 2. Weekly Insights Capsule Bar Chart (Last 7 Points Only) ──────────────
  Widget _buildWeeklyInsightsChartCard(Color cardBg, Color cardBorder, Color textColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Weekly Mood Trend',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
              // Capsule Bars vs Trend Curve Mode Switcher
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _chartMode = _ChartViewMode.capsuleBars);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _chartMode == _ChartViewMode.capsuleBars
                              ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.bar_chart_rounded,
                          size: 15,
                          color: _chartMode == _ChartViewMode.capsuleBars
                              ? const Color(0xFFFF8A65)
                              : Colors.grey,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _chartMode = _ChartViewMode.trendCurve);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _chartMode == _ChartViewMode.trendCurve
                              ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.show_chart_rounded,
                          size: 15,
                          color: _chartMode == _ChartViewMode.trendCurve
                              ? const Color(0xFFFF8A65)
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _weekRangeLabel,
            style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : const Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),

          _chartMode == _ChartViewMode.capsuleBars
              ? _buildCapsuleBarChart(textColor, isDark)
              : _buildTrendCurveChart(textColor, isDark),
        ],
      ),
    );
  }

  // Capsule Bar Chart: Last 7 days
  Widget _buildCapsuleBarChart(Color textColor, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(7, (idx) {
        final item = _weekData[idx];
        final isSelected = _selectedDayIndex == idx;
        final isToday = idx == (DateTime.now().weekday - 1);
        final heightRatio = item.moodScore > 0 ? (item.moodScore / 5.0) : 0.15;
        final barHeight = 85.0 * heightRatio;

        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _selectedDayIndex = idx);
          },
          child: Column(
            children: [
              if (item.moodScore > 0)
                Text(item.emoji, style: const TextStyle(fontSize: 14))
              else
                const SizedBox(height: 18),
              const SizedBox(height: 4),

              // Bar Pill
              Container(
                width: 26,
                height: 90,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(16),
                  border: isSelected
                      ? Border.all(color: const Color(0xFFFF8A65), width: 2)
                      : null,
                ),
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: 26,
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: item.moodScore > 0 ? item.color : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              Text(
                item.dayName,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isToday ? FontWeight.w900 : FontWeight.w600,
                  color: isToday
                      ? const Color(0xFFFF8A65)
                      : (isDark ? Colors.white60 : const Color(0xFF64748B)),
                ),
              ),
              Text(
                '${item.dayNumber}',
                style: TextStyle(
                  fontSize: 9.5,
                  color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // Trend Curve Graph
  Widget _buildTrendCurveChart(Color textColor, bool isDark) {
    return SizedBox(
      height: 140,
      width: double.infinity,
      child: CustomPaint(
        painter: _TrendCurvePainter(
          weekData: _weekData,
          isDark: isDark,
        ),
      ),
    );
  }

  // ── 3. Today's Habits (Progress vs Goal, Zero Fabricated Clinical Claims) ───
  Widget _buildDailyInfluencesSection(Color cardBg, Color cardBorder, Color textColor, bool isDark) {
    final weeks = widget.profile?.computedWeeks ?? 28;
    final isThirdTrimester = weeks >= 28;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Habits & Influences',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
            Text(
              'Today’s habits',
              style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : const Color(0xFF64748B)),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Hydration & Sleep Status Cards (Progress vs Target, No Diagnostic Overclaims)
        Builder(
          builder: (context) {
            // Hydration Status (Encourage fluids, no amniotic index claims)
            final String waterTag;
            final Color waterTagColor;
            final String waterTitle;
            final String waterDesc;
            if (_waterGlassesToday < 4) {
              waterTag = 'ENCOURAGE';
              waterTagColor = const Color(0xFFE11D48);
              waterTitle = 'Increase Fluids';
              waterDesc = '$_waterGlassesToday/8 glasses. Aim for steady fluid intake today. If experiencing severe vomiting or pain, check Danger Protocols or trigger SOS.';
            } else if (_waterGlassesToday < 8) {
              waterTag = 'IN PROGRESS';
              waterTagColor = const Color(0xFFD97706);
              waterTitle = 'Moderate Hydration';
              waterDesc = '$_waterGlassesToday/8 glasses. Keep sipping water toward your daily 8-glass goal.';
            } else {
              waterTag = 'ON TARGET';
              waterTagColor = const Color(0xFF16A34A);
              waterTitle = 'Hydration On Target';
              waterDesc = '$_waterGlassesToday/8 glasses logged. Daily hydration goal achieved for you and baby.';
            }

            // Sleep Status (Rest target for late pregnancy, no perfusion claims)
            final String sleepTag;
            final Color sleepTagColor;
            final String sleepTitle;
            final String sleepDesc;
            if (_sleepHoursToday < 6) {
              sleepTag = 'REST TARGET';
              sleepTagColor = const Color(0xFFE11D48);
              sleepTitle = 'Rest Below Target';
              sleepDesc = '$_sleepHoursToday hrs logged. The rest target for late pregnancy is 8-9 hours. Take restful pauses during the day.';
            } else if (_sleepHoursToday < 8) {
              sleepTag = 'MODERATE';
              sleepTagColor = const Color(0xFFD97706);
              sleepTitle = 'Moderate Rest';
              sleepDesc = '$_sleepHoursToday hrs logged. Close to the recommended rest target for late pregnancy (8-9h).';
            } else {
              sleepTag = 'RESTED';
              sleepTagColor = const Color(0xFF16A34A);
              sleepTitle = 'Rest Target Met';
              sleepDesc = '$_sleepHoursToday hrs logged. Met the rest target for late pregnancy. Rest comfortably on your side.';
            }

            return Row(
              children: [
                // Hydration Card
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: waterTagColor.withOpacity(0.35), width: 1.2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('💧', style: TextStyle(fontSize: 18)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: waterTagColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                waterTag,
                                style: TextStyle(
                                  color: waterTagColor,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          waterTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          waterDesc,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark ? Colors.white60 : const Color(0xFF64748B),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Sleep Card
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: sleepTagColor.withOpacity(0.35), width: 1.2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('💤', style: TextStyle(fontSize: 18)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: sleepTagColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                sleepTag,
                                style: TextStyle(
                                  color: sleepTagColor,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          sleepTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          sleepDesc,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark ? Colors.white60 : const Color(0xFF64748B),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),

        // Quick Daily Habit Loggers
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cardBorder),
          ),
          child: Column(
            children: [
              // Fetal Kicks Counter (Emphasize third trimester, no pass/fail shame)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('👶', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isThirdTrimester ? 'Fetal Kicks (Baby Movements)' : 'Fetal Movements',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
                            ),
                            Text(
                              'Know your baby’s usual pattern. If movements feel clearly less than normal → Danger Protocols or SOS.',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: isDark ? Colors.white54 : const Color(0xFF64748B),
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded, size: 22),
                        onPressed: () {
                          if (_fetalKicksToday > 0) {
                            _saveCheckin(kicks: _fetalKicksToday - 1);
                          }
                        },
                      ),
                      Text(
                        '$_fetalKicksToday',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: textColor),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline_rounded, size: 22, color: Color(0xFFFF8A65)),
                        onPressed: () {
                          _saveCheckin(kicks: _fetalKicksToday + 1);
                        },
                      ),
                    ],
                  ),

                  // First session educational empty state
                  if (_fetalKicksToday == 0) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Counting kicks helps you learn your baby’s normal daily pattern of movement. Set aside quiet time when baby is usually active. If movements feel clearly less than normal, do not wait — check Danger Protocols or trigger SOS.',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isDark ? Colors.white60 : const Color(0xFF64748B),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],

                  if (!isThirdTrimester) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Third-trimester focus (Week $weeks) • Movement tracking becomes regular after week 28.',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ],
              ),
              const Divider(height: 16),

              // Water Intake Counter
              Row(
                children: [
                  const Text('💧', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hydration (Water Glasses)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor)),
                        Text('8 glasses recommended per day', style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white54 : const Color(0xFF64748B))),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded, size: 22),
                    onPressed: () {
                      if (_waterGlassesToday > 0) {
                        _saveCheckin(water: _waterGlassesToday - 1);
                      }
                    },
                  ),
                  Text(
                    '$_waterGlassesToday',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: textColor),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 22, color: Color(0xFF00B0FF)),
                    onPressed: () {
                      _saveCheckin(water: _waterGlassesToday + 1);
                    },
                  ),
                ],
              ),
              const Divider(height: 16),

              // Rest & Sleep Counter
              Row(
                children: [
                  const Text('💤', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Rest & Sleep (Hours)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor)),
                        Text('8-9 hours rest target for late pregnancy', style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white54 : const Color(0xFF64748B))),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded, size: 22),
                    onPressed: () {
                      if (_sleepHoursToday > 4) {
                        _saveCheckin(sleep: _sleepHoursToday - 1);
                      }
                    },
                  ),
                  Text(
                    '$_sleepHoursToday hrs',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: textColor),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 22, color: Color(0xFF8B5CF6)),
                    onPressed: () {
                      if (_sleepHoursToday < 14) {
                        _saveCheckin(sleep: _sleepHoursToday + 1);
                      }
                    },
                  ),
                ],
              ),
              const Divider(height: 16),

              // Prenatal Vitamins Toggle
              Row(
                children: [
                  const Text('💊', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Prenatal Vitamins & Iron', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor)),
                        Text('Daily recommended maternal supplements', style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white54 : const Color(0xFF64748B))),
                      ],
                    ),
                  ),
                  Switch(
                    value: _vitaminsTakenToday,
                    activeColor: const Color(0xFF22C55E),
                    onChanged: (val) {
                      _saveCheckin(vitamins: val);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 4. Monthly Behaviour & Emotion Calendar ────────────────────────────────
  Widget _buildMonthlyCalendarCard(Color cardBg, Color cardBorder, Color textColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$_currentMonthName Wellness Calendar',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Text(_currentMonthYearAbbr, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 4),
                    const Icon(Icons.calendar_month_rounded, size: 12),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Daily logs for emotion and habit tracking',
            style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : const Color(0xFF64748B)),
          ),
          const SizedBox(height: 14),

          _buildCalendarMonthGrid(cardBg, textColor, isDark),
        ],
      ),
    );
  }

  Widget _buildCalendarMonthGrid(Color cardBg, Color textColor, bool isDark) {
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final startingWeekday = firstDayOfMonth.weekday; // 1 = Mon, 7 = Sun

    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: dayLabels.map((lbl) => Text(
            lbl,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white38 : const Color(0xFF94A3B8)),
          )).toList(),
        ),
        const SizedBox(height: 8),

        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1.0,
          ),
          itemCount: (startingWeekday - 1) + daysInMonth,
          itemBuilder: (context, index) {
            if (index < startingWeekday - 1) {
              return const SizedBox.shrink();
            }

            final day = index - (startingWeekday - 2);
            final dt = DateTime(now.year, now.month, day);
            final key = _dateKey(dt);
            final isToday = day == now.day;
            final rec = _savedDailyRecords[key];
            final moodScore = (rec?['mood'] as num?)?.toInt() ?? 0;
            final moodColor = _getMoodColor(moodScore);

            return Container(
              decoration: BoxDecoration(
                color: moodScore > 0
                    ? moodColor.withOpacity(isDark ? 0.35 : 0.2)
                    : (isToday
                        ? (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))
                        : Colors.transparent),
                shape: BoxShape.circle,
                border: isToday
                    ? Border.all(color: const Color(0xFFFF8A65), width: 1.5)
                    : null,
              ),
              child: Center(
                child: Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isToday ? FontWeight.w900 : FontWeight.w500,
                    color: isToday
                        ? const Color(0xFFFF8A65)
                        : (moodScore > 0
                            ? (isDark ? Colors.white : textColor)
                            : (isDark ? Colors.white60 : const Color(0xFF64748B))),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ── Clinical Danger Signs & Emergency Pre-Alert Desk (Danger Protocols) ────
  Widget _buildClinicalRedFlagsList(Color cardBg, Color cardBorder, Color textColor, bool isDark) {
    const dangerSigns = [
      _DangerSign(
        icon: '🩸',
        title: 'Vaginal Bleeding',
        subtitle: 'Fresh red bleeding, heavy clots, or persistent dark spotting',
        clinicalImplication: 'Risk of placental abruption, placenta praevia, or cervical changes.',
        recommendedAction: 'Immediate non-ambulatory rest. Do not insert tampons. Solace SOS dispatch initiated.',
        severity: 'PRIORITY 1 (CRITICAL)',
        conditionCode: 'VAGINAL_BLEEDING',
      ),
      _DangerSign(
        icon: '💧',
        title: 'Amniotic Fluid Leak',
        subtitle: 'Sudden gush or continuous clear / green-tinged fluid draining',
        clinicalImplication: 'Pre-labour rupture of membranes (PROM); cord prolapse or ascending infection risk.',
        recommendedAction: 'Note fluid colour, time, and odour. Avoid baths. Immediate sterile obstetric admission.',
        severity: 'PRIORITY 1 (CRITICAL)',
        conditionCode: 'WATERS_BROKE',
      ),
      _DangerSign(
        icon: '⚡',
        title: 'Severe Headache & Vision Changes',
        subtitle: 'Unrelenting pounding frontal headache, blurred vision, flashes, epigastric pain',
        clinicalImplication: 'Severe pre-eclampsia / impending eclamptic convulsion.',
        recommendedAction: 'Sit calmly in low light. Check blood pressure immediately if cuff available. Dispatch urgent obstetric triage.',
        severity: 'PRIORITY 1 (CRITICAL)',
        conditionCode: 'SEVERE_PREECLAMPSIA',
      ),
      _DangerSign(
        icon: '👶',
        title: 'Reduced Fetal Movements',
        subtitle: 'Noticeably fewer kicks or complete absence of normal active movement patterns',
        clinicalImplication: 'Possible fetal compromise, placental insufficiency, or oligohydramnios.',
        recommendedAction: 'Lie on left side for 30 min and drink cold water. If still quiet, immediate CTG assessment required.',
        severity: 'PRIORITY 2 (HIGH)',
        conditionCode: 'REDUCED_FETAL_MOVEMENTS',
      ),
      _DangerSign(
        icon: '⏱️',
        title: 'Regular Painful Contractions',
        subtitle: 'Tightenings lasting >40s occurring every 3-5 minutes, especially before term',
        clinicalImplication: 'Active labour or preterm labour requiring urgent maternal-fetal delivery readiness.',
        recommendedAction: 'Prepare birth bag. Keep hydration sip. Engage Solace dispatch to designated maternity centre.',
        severity: 'PRIORITY 1 (CRITICAL)',
        conditionCode: 'PRETERM_LABOUR',
      ),
    ];

    return Column(
      children: dangerSigns.map((item) {
        final isP1 = item.severity.contains('PRIORITY 1');
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isP1
                  ? (isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA))
                  : (isDark ? const Color(0xFF78350F) : const Color(0xFFFDE68A)),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.icon, style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                item.title,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: textColor,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: isP1
                                    ? Colors.red.shade900.withOpacity(0.2)
                                    : Colors.amber.shade900.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isP1 ? Colors.redAccent : Colors.amber,
                                ),
                              ),
                              child: Text(
                                item.severity,
                                style: TextStyle(
                                  color: isP1 ? Colors.redAccent : Colors.amber,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.subtitle,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Clinical Risk: ${item.clinicalImplication}',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Guidance: ${item.recommendedAction}',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    HapticFeedback.heavyImpact();
                    widget.onDispatchCondition(item.conditionCode, isP1 ? 1 : 2);
                  },
                  icon: const Icon(Icons.flash_on_rounded, size: 16),
                  label: Text(
                    'Dispatch for ${item.title.split(RegExp(r"\(")).first.trim()} Now',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: isP1 ? const Color(0xFFDC2626) : const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _weekdayName(int weekday) {
    switch (weekday) {
      case 0: return 'Sunday';
      case 1: return 'Monday';
      case 2: return 'Tuesday';
      case 3: return 'Wednesday';
      case 4: return 'Thursday';
      case 5: return 'Friday';
      case 6: return 'Saturday';
      default: return 'Daily';
    }
  }
}

class _DangerSign {
  final String icon;
  final String title;
  final String subtitle;
  final String clinicalImplication;
  final String recommendedAction;
  final String severity;
  final String conditionCode;

  const _DangerSign({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.clinicalImplication,
    required this.recommendedAction,
    required this.severity,
    required this.conditionCode,
  });
}

// Custom Painter for Smooth Trend Curve Graph
class _TrendCurvePainter extends CustomPainter {
  final List<_DailyMoodRecord> weekData;
  final bool isDark;

  _TrendCurvePainter({required this.weekData, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    if (weekData.isEmpty) return;

    final paintLine = Paint()
      ..color = const Color(0xFFFF8A65)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final paintFill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFFF8A65).withOpacity(0.3),
          const Color(0xFFFF8A65).withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final points = <Offset>[];
    final stepX = size.width / (weekData.length - 1);

    for (int i = 0; i < weekData.length; i++) {
      final score = weekData[i].moodScore > 0 ? weekData[i].moodScore : 3;
      final x = i * stepX;
      // Invert Y: score 5 is top (small y), score 1 is bottom (large y)
      final y = size.height - (score / 5.0) * (size.height - 30) - 15;
      points.add(Offset(x, y));
    }

    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlX = (p0.dx + p1.dx) / 2;
      path.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
    }

    // Draw area under curve
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fillPath, paintFill);

    // Draw main curve line
    canvas.drawPath(path, paintLine);

    // Draw nodes with emotion colors
    for (int i = 0; i < points.length; i++) {
      final item = weekData[i];
      final p = points[i];
      final nodePaint = Paint()
        ..color = item.moodScore > 0 ? item.color : Colors.grey
        ..style = PaintingStyle.fill;

      canvas.drawCircle(p, 5.0, nodePaint);
      canvas.drawCircle(p, 5.0, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendCurvePainter oldDelegate) => true;
}
