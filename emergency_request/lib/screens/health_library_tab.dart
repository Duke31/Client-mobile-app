import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/member_profile.dart';
import '../theme/app_theme.dart';

class HealthLibraryTab extends StatefulWidget {
  final Function(String condition, int priority) onDispatchCondition;
  final MemberProfile? profile;

  const HealthLibraryTab({
    super.key,
    required this.onDispatchCondition,
    this.profile,
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
  _InsightMode _currentMode = _InsightMode.wellnessTracker;
  _ChartViewMode _chartMode = _ChartViewMode.capsuleBars;

  // Selected mood today (1: Awful, 2: Bad, 3: Okay, 4: Good, 5: Great)
  int _todayMoodScore = 4; // Default to 'Good'
  int _selectedDayIndex = 2; // Wednesday by default

  // Daily maternal wellness counters
  int _fetalKicksToday = 12;
  int _waterGlassesToday = 8;
  bool _vitaminsTakenToday = true;

  // Simulated week data (Mon Oct 12 to Sun Oct 18)
  late List<_DailyMoodRecord> _weekData;

  @override
  void initState() {
    super.initState();
    _buildWeekData();
  }

  void _buildWeekData() {
    _weekData = [
      const _DailyMoodRecord(dayName: 'MON', dayNumber: 12, moodScore: 5, label: 'Great', emoji: '😄', color: Color(0xFF22C55E)),
      const _DailyMoodRecord(dayName: 'TUE', dayNumber: 13, moodScore: 2, label: 'Bad', emoji: '😔', color: Color(0xFFF43F5E)),
      _DailyMoodRecord(
        dayName: 'WED',
        dayNumber: 14,
        moodScore: _todayMoodScore,
        label: _getMoodLabel(_todayMoodScore),
        emoji: _getMoodEmoji(_todayMoodScore),
        color: _getMoodColor(_todayMoodScore),
      ),
      const _DailyMoodRecord(dayName: 'THU', dayNumber: 15, moodScore: 0, label: 'Unlogged', emoji: '', color: Colors.transparent),
      const _DailyMoodRecord(dayName: 'FRI', dayNumber: 16, moodScore: 3, label: 'Okay', emoji: '😐', color: Color(0xFFEAB308)),
      const _DailyMoodRecord(dayName: 'SAT', dayNumber: 17, moodScore: 4, label: 'Good', emoji: '🙂', color: Color(0xFF10B981)),
      const _DailyMoodRecord(dayName: 'SUN', dayNumber: 18, moodScore: 0, label: 'Unlogged', emoji: '', color: Colors.transparent),
    ];
  }

  void _setTodayMood(int score) {
    HapticFeedback.mediumImpact();
    setState(() {
      _todayMoodScore = score;
      _buildWeekData();
    });
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
      default: return '⚪';
    }
  }

  Color _getMoodColor(int score) {
    switch (score) {
      case 1: return const Color(0xFF8B5CF6); // Purple
      case 2: return const Color(0xFFF43F5E); // Soft coral / pink
      case 3: return const Color(0xFFEAB308); // Warm yellow
      case 4: return const Color(0xFF10B981); // Mint green
      case 5: return const Color(0xFF22C55E); // Bright emerald
      default: return Colors.grey;
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
              : 'Clinical Danger Signs & Red Flags',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        backgroundColor: cardBg,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Toggle View',
            icon: Icon(
              _currentMode == _InsightMode.wellnessTracker
                  ? Icons.local_hospital_outlined
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
            const SizedBox(height: 16),

            if (_currentMode == _InsightMode.wellnessTracker) ...[
              // ── 1. Daily Emotion Check-In (Image 5 & Image 3) ────────────
              _buildDailyCheckInCard(cardBg, cardBorder, textColor, isDark),
              const SizedBox(height: 16),

              // ── 2. Weekly Insights Capsule Bar Chart (Image 4 & Image 5) ─
              _buildWeeklyInsightsChartCard(cardBg, cardBorder, textColor, isDark),
              const SizedBox(height: 16),

              // ── 3. Daily Influences & Factors (Image 4 & Image 5) ────────
              _buildDailyInfluencesSection(cardBg, cardBorder, textColor, isDark),
              const SizedBox(height: 16),

              // ── 4. Monthly Behaviour & Emotion Calendar (Image 3) ────────
              _buildMonthlyCalendarCard(cardBg, cardBorder, textColor, isDark),
              const SizedBox(height: 20),
            ] else ...[
              // ── Clinical Danger Signs & Emergency Pre-Alert Desk ─────────
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
                    const Text('✨', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(
                      'Daily Wellness',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _currentMode == _InsightMode.wellnessTracker
                            ? const Color(0xFFFF8A65)
                            : (isDark ? Colors.white60 : const Color(0xFF64748B)),
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
                    const Text('🚨', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(
                      'Red Flags & SOS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _currentMode == _InsightMode.clinicalRedFlags
                            ? const Color(0xFFEF4444)
                            : (isDark ? Colors.white60 : const Color(0xFF64748B)),
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

  // ── 1. Daily Check-In Card (Matching Image 5) ──────────────────────────────
  Widget _buildDailyCheckInCard(Color cardBg, Color cardBorder, Color textColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8A65).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '5TH CHECK-IN • TODAY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFD84315),
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              Text(
                'Updated just now',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white54 : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'How are you today?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: textColor,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 16),

          // 5 Emotion Face Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildEmotionButton(1, 'Awful', '😫', const Color(0xFF8B5CF6), isDark),
              _buildEmotionButton(2, 'Bad', '😔', const Color(0xFF38BDF8), isDark),
              _buildEmotionButton(3, 'Okay', '😐', const Color(0xFFFACC15), isDark),
              _buildEmotionButton(4, 'Good', '🙂', const Color(0xFF4ADE80), isDark),
              _buildEmotionButton(5, 'Great', '😄', const Color(0xFF22C55E), isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmotionButton(int score, String label, String emoji, Color color, bool isDark) {
    final isSelected = _todayMoodScore == score;
    return InkWell(
      onTap: () => _setTodayMood(score),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(0.18)
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isSelected ? color : color.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                color: isSelected ? color : (isDark ? Colors.white70 : const Color(0xFF64748B)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 2. Weekly Insights Capsule Bar Chart (Matching Image 4) ────────────────
  Widget _buildWeeklyInsightsChartCard(Color cardBg, Color cardBorder, Color textColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Weekly Insights',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'This week • OCT 12 - OCT 18',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFFFF8A65) : const Color(0xFFD84315),
                    ),
                  ),
                ],
              ),
              // Chart View Mode Switcher: Capsule Bars vs Trend Curve
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    IconButton(
                      iconSize: 18,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        Icons.bar_chart_rounded,
                        color: _chartMode == _ChartViewMode.capsuleBars
                            ? const Color(0xFFFF8A65)
                            : (isDark ? Colors.white38 : Colors.black38),
                      ),
                      onPressed: () => setState(() => _chartMode = _ChartViewMode.capsuleBars),
                    ),
                    IconButton(
                      iconSize: 18,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        Icons.show_chart_rounded,
                        color: _chartMode == _ChartViewMode.trendCurve
                            ? const Color(0xFFFF8A65)
                            : (isDark ? Colors.white38 : Colors.black38),
                      ),
                      onPressed: () => setState(() => _chartMode = _ChartViewMode.trendCurve),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Render Selected Chart View
          _chartMode == _ChartViewMode.capsuleBars
              ? _buildCapsuleBarChart(textColor, isDark)
              : _buildTrendCurveChart(textColor, isDark),
        ],
      ),
    );
  }

  // Capsule Bar Chart (Image 4)
  Widget _buildCapsuleBarChart(Color textColor, bool isDark) {
    const double maxHeight = 120.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(_weekData.length, (idx) {
        final item = _weekData[idx];
        final isSelected = _selectedDayIndex == idx;
        final hasLog = item.moodScore > 0;
        final barHeight = hasLog ? (item.moodScore / 5.0) * maxHeight : 12.0;

        return InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _selectedDayIndex = idx);
          },
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Character Emoji on top of the bar
              if (hasLog)
                Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: item.color.withOpacity(0.25),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      item.emoji,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                )
              else
                const SizedBox(height: 34),

              // Animated Rounded Capsule Bar
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 22,
                height: barHeight,
                decoration: BoxDecoration(
                  color: hasLog
                      ? item.color
                      : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: isSelected && hasLog
                      ? [
                          BoxShadow(
                            color: item.color.withOpacity(0.5),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
              ),
              const SizedBox(height: 8),

              // Day Label (MON, TUE...)
              Text(
                item.dayName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                  color: isSelected
                      ? (isDark ? Colors.white : const Color(0xFF0F172A))
                      : (isDark ? Colors.white54 : const Color(0xFF94A3B8)),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // Trend Curve Graph (Image 5)
  Widget _buildTrendCurveChart(Color textColor, bool isDark) {
    return SizedBox(
      height: 160,
      width: double.infinity,
      child: CustomPaint(
        painter: _TrendCurvePainter(
          weekData: _weekData,
          isDark: isDark,
        ),
      ),
    );
  }

  // ── 3. Daily Influences & Impact Factors (Image 4 & Image 5) ───────────────
  Widget _buildDailyInfluencesSection(Color cardBg, Color cardBorder, Color textColor, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Mood Influences',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
            Text(
              'Daily Clinical Balance',
              style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : const Color(0xFF64748B)),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Two Hero Impact Cards (Positive vs Negative)
        Row(
          children: [
            // Positive Card
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.3)),
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
                            color: const Color(0xFF22C55E).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'POSITIVE',
                            style: TextStyle(
                              color: Color(0xFF16A34A),
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Hydration',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$_waterGlassesToday/8 glasses logged\nMost positive impact on energy',
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

            // Negative / Attention Card
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFF43F5E).withOpacity(0.3)),
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
                            color: const Color(0xFFF43F5E).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'ATTENTION',
                            style: TextStyle(
                              color: Color(0xFFE11D48),
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Rest & Sleep',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Lower back strain reported\nRecommended: elevate feet & rest',
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
        ),
        const SizedBox(height: 12),

        // Quick Daily Factor Loggers
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cardBorder),
          ),
          child: Column(
            children: [
              // Fetal Kicks Counter
              Row(
                children: [
                  const Text('👶', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Fetal Kicks (Active Baby)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor)),
                        Text('Goal: 10 movements in 2 hours', style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white54 : const Color(0xFF64748B))),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded, size: 22),
                    onPressed: () {
                      if (_fetalKicksToday > 0) {
                        HapticFeedback.selectionClick();
                        setState(() => _fetalKicksToday--);
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
                      HapticFeedback.selectionClick();
                      setState(() => _fetalKicksToday++);
                    },
                  ),
                ],
              ),
              const Divider(height: 14),

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
                        HapticFeedback.selectionClick();
                        setState(() => _waterGlassesToday--);
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
                      HapticFeedback.selectionClick();
                      setState(() => _waterGlassesToday++);
                    },
                  ),
                ],
              ),
              const Divider(height: 14),

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
                        Text('Folate, Calcium & Micronutrients', style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white54 : const Color(0xFF64748B))),
                      ],
                    ),
                  ),
                  Switch(
                    value: _vitaminsTakenToday,
                    activeColor: const Color(0xFF22C55E),
                    onChanged: (val) {
                      HapticFeedback.selectionClick();
                      setState(() => _vitaminsTakenToday = val);
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

  // ── 4. Monthly Behaviour & Emotion Calendar (Matching Image 3) ─────────────
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
                'October Wellness Calendar',
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
                child: const Row(
                  children: [
                    Text('OCT 2026', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    SizedBox(width: 4),
                    Icon(Icons.calendar_month_rounded, size: 12),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Day header (M T W T F S S)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((d) {
              return SizedBox(
                width: 32,
                child: Center(
                  child: Text(
                    d,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white54 : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),

          // Calendar Grid (31 days)
          Wrap(
            spacing: 8,
            runSpacing: 10,
            alignment: WrapAlignment.spaceAround,
            children: List.generate(31, (index) {
              final day = index + 1;
              final isToday = day == 14;
              Color dotColor;
              if (day % 4 == 0) {
                dotColor = const Color(0xFF22C55E); // Great
              } else if (day % 3 == 0) {
                dotColor = const Color(0xFF4ADE80); // Good
              } else if (day % 5 == 0) {
                dotColor = const Color(0xFFFACC15); // Okay
              } else if (day == 13) {
                dotColor = const Color(0xFFF43F5E); // Bad
              } else if (day > 14) {
                dotColor = Colors.transparent; // Upcoming
              } else {
                dotColor = const Color(0xFF22C55E);
              }

              return Container(
                width: 32,
                height: 38,
                decoration: BoxDecoration(
                  color: isToday
                      ? const Color(0xFFFF8A65).withOpacity(0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: isToday
                      ? Border.all(color: const Color(0xFFFF8A65), width: 1.5)
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$day',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isToday ? FontWeight.w900 : FontWeight.w600,
                        color: isToday
                            ? const Color(0xFFFF8A65)
                            : (day > 14 ? (isDark ? Colors.white24 : Colors.black26) : textColor),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── Clinical Danger Signs & Emergency Pre-Alert ────────────────────────────
  Widget _buildClinicalRedFlagsList(Color cardBg, Color cardBorder, Color textColor, bool isDark) {
    const dangerSigns = [
      _DangerSign(
        icon: '🩸',
        title: 'Vaginal Bleeding (Antepartum Hemorrhage)',
        subtitle: 'Bright red or dark bleeding with or without cramps',
        clinicalImplication: 'May indicate placental abruption or placenta previa. Immediate pre-alert initiates O-Neg blood reservation.',
        recommendedAction: 'Lie flat, do not insert tampons, request immediate transport.',
        severity: 'CRITICAL P1',
        conditionCode: 'Obstetric',
      ),
      _DangerSign(
        icon: '💧',
        title: 'Premature Rupture of Membranes (PROM)',
        subtitle: 'Sudden gush or continuous trickle of watery fluid',
        clinicalImplication: 'Risk of ascending intrauterine infection or umbilical cord prolapse.',
        recommendedAction: 'Note fluid color (clear/green) and initiate hospital transfer.',
        severity: 'CRITICAL P1',
        conditionCode: 'Obstetric',
      ),
      _DangerSign(
        icon: '⚡',
        title: 'Severe Preeclampsia / Convulsions (Eclampsia)',
        subtitle: 'Pounding headache, blurred vision, sudden facial edema',
        clinicalImplication: 'Risk of maternal seizure, intracranial hemorrhage, and fetal hypoxia.',
        recommendedAction: 'ALS ambulance dispatched with Magnesium Sulfate infusion capability.',
        severity: 'CRITICAL P1',
        conditionCode: 'Obstetric',
      ),
      _DangerSign(
        icon: '👶',
        title: 'Decreased / Absent Fetal Movement',
        subtitle: 'Fewer than 10 kicks over 2 hours during active maternal rest',
        clinicalImplication: 'Sign of chronic fetal distress or placental insufficiency.',
        recommendedAction: 'Requires immediate cardiotocography (CTG) and ultrasound biophysical profile.',
        severity: 'URGENT P2',
        conditionCode: 'Obstetric',
      ),
    ];

    return Column(
      children: dangerSigns.map((item) {
        final isP1 = item.severity.contains('P1');
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isP1 ? Colors.red.shade400.withOpacity(0.4) : cardBorder,
              width: isP1 ? 1.5 : 1.0,
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
                    'Dispatch for ${item.title.split('(').first.trim()} Now',
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

// Custom Painter for Smooth Trend Curve Graph (Image 5)
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
