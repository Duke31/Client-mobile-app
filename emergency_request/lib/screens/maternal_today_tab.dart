import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/member_profile.dart';
import '../services/maternal_care_service.dart';
import '../models/maternal_content_item.dart';
import '../services/maternal_content_service.dart';
import '../theme/app_theme.dart';

class MaternalTodayTab extends StatefulWidget {
  final MemberProfile profile;
  final VoidCallback onTriggerSos;
  final VoidCallback onOpenMissionTracker;
  final Function(String condition, int priority)? onTriggerFastPass;
  final Map<String, dynamic>? activeEmergency;
  final VoidCallback? onOpenShieldTab;
  final VoidCallback? onOpenInsightsTab;

  const MaternalTodayTab({
    super.key,
    required this.profile,
    required this.onTriggerSos,
    required this.onOpenMissionTracker,
    this.onTriggerFastPass,
    this.activeEmergency,
    this.onOpenShieldTab,
    this.onOpenInsightsTab,
  });

  @override
  State<MaternalTodayTab> createState() => _MaternalTodayTabState();
}

class _MaternalTodayTabState extends State<MaternalTodayTab> {
  final MaternalCareService _maternalService = MaternalCareService();
  final MaternalContentService _contentService = MaternalContentService();
  int _selectedDayIndex = 3; // Index in the 7-day strip (middle = Today)
  int _unreadAlertCount = 3; // Unread notification badge counter for daily 8:00 AM content drop
  String? _lastAcknowledgedCycleKey; // Tracks acknowledged 8:00 AM cycle
  Timer? _cycleRefreshTimer; // Automated timer scheduling 8:00 AM daily refresh
  List<MaternalContentItem> _dailyGuidanceCards = [];
  bool _loadingGuidance = true;

  @override
  void initState() {
    super.initState();
    _maternalService.addListener(_onServiceUpdate);
    _loadDailyGuidance();
    _scheduleNext8amRefreshTimer();
  }

  @override
  void dispose() {
    _cycleRefreshTimer?.cancel();
    _maternalService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MaternalTodayTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.computedWeeks != widget.profile.computedWeeks ||
        oldWidget.profile.edd != widget.profile.edd ||
        oldWidget.profile.lmpDate != widget.profile.lmpDate) {
      _loadDailyGuidance();
    }
  }

  /// Automatically schedules a refresh at 8:00 AM sharp the next day
  void _scheduleNext8amRefreshTimer() {
    _cycleRefreshTimer?.cancel();
    final next8am = MaternalContentService.getNextClinicalCycleRefresh();
    final diff = next8am.difference(DateTime.now());
    final waitDuration = diff.isNegative
        ? const Duration(seconds: 1)
        : diff + const Duration(seconds: 1);

    _cycleRefreshTimer = Timer(waitDuration, () {
      if (mounted) {
        _loadDailyGuidance();
        _scheduleNext8amRefreshTimer();
      }
    });
  }

  bool _isNegativeOrPanicNotification(MaternalContentItem item) {
    if (item.isSafety || item.slot.toLowerCase() == 'safety') return true;
    final text = '${item.title} ${item.body}'.toLowerCase();
    return text.contains('bleeding') ||
        text.contains('miscarriage') ||
        text.contains('severe pain') ||
        text.contains('ectopic') ||
        text.contains('fainting') ||
        text.contains('danger') ||
        text.contains('warning');
  }

  /// Fetches the daily maternal guidance aligned to the active 8:00 AM drop
  Future<void> _loadDailyGuidance() async {
    final currentCycleKey = MaternalContentService.getClinicalCycleKey();
    final cards = await _contentService.getDailyGuidanceCards(
      gestationalWeek: widget.profile.computedWeeks,
    );
    if (mounted) {
      final safeCards = cards.where((c) => !_isNegativeOrPanicNotification(c)).toList();
      setState(() {
        _dailyGuidanceCards = cards;
        _loadingGuidance = false;
        // If a new 8:00 AM cycle has dropped that hasn't been acknowledged, activate notification count
        if (_lastAcknowledgedCycleKey != currentCycleKey) {
          _unreadAlertCount = safeCards.isNotEmpty ? safeCards.length : 1;
        }
      });
    }
  }

  void _markAlertsAsAcknowledged() {
    final currentCycleKey = MaternalContentService.getClinicalCycleKey();
    setState(() {
      _lastAcknowledgedCycleKey = currentCycleKey;
      _unreadAlertCount = 0;
    });
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  int get _computedElapsedDays => widget.profile.computedElapsedDays;
  int get _weeks => widget.profile.computedWeeks;
  int get _days => widget.profile.computedDays;
  int get _pregnancyDay => widget.profile.pregnancyDay;
  String get _trimesterLabel => widget.profile.trimesterLabel;
  bool get _isLateTrimester => _weeks >= 28;

  Widget _buildGreetingGesture(bool isDark) {
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final hour = DateTime.now().hour;
    String greeting;
    String icon;
    if (hour < 12) {
      greeting = 'Good morning';
      icon = '☀️';
    } else if (hour < 17) {
      greeting = 'Good afternoon';
      icon = '🌤️';
    } else {
      greeting = 'Good evening';
      icon = '🌙';
    }

    final rawName = widget.profile.fullName;
    final firstName = rawName.trim().isNotEmpty
        ? rawName.trim().split(' ').first
        : '';
    final title = firstName.isNotEmpty ? '$greeting, $firstName $icon' : '$greeting $icon';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFFFE0D2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFFFF8A65).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Text('🌸', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  'Wishing you and your baby a restful, healthy day.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: subColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _monthName {
    final now = DateTime.now();
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[now.month - 1];
  }

  List<DateTime> _getCurrentWeekDates() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return List.generate(7, (i) => monday.add(Duration(days: i)));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F172A), Color(0xFF0B1120)],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF9F5), Color(0xFFFFF1EB), Color(0xFFFFFFFF)],
          );

    final hasActive = widget.activeEmergency != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: bgGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 1. Top Header Bar ────────────────────────────────────────
                _buildTopAppBar(isDark),
                const SizedBox(height: 12),

                // ── Welcome & Time-of-Day Greeting Gesture ───────────────────
                _buildGreetingGesture(isDark),

                // ── 2. Horizontal Weekly Calendar Strip with 'TODAY' Marker ──
                _buildWeeklyCalendarStrip(isDark),
                const SizedBox(height: 18),

                // ── Active Emergency Mission Banner (If Ambulance is En Route) ─
                if (hasActive) ...[
                  _buildActiveMissionBanner(isDark),
                  const SizedBox(height: 18),
                ],

                // ── 3. Centerpiece: Soft Glowing Amniotic Sphere ─────────────
                _buildAmnioticCenterpiece(isDark),
                const SizedBox(height: 24),

                // ── 4. My Daily Insights • Today ─────────────────────────────
                _buildDailyInsightsSection(isDark),
                const SizedBox(height: 20),

                // ── 5. Care Alerts & Notifications Section (Refreshes Daily at 8:00 AM) ──
                _buildCareAlertsAndNotificationsSection(isDark),
                const SizedBox(height: 20),

                // ── 6. Dedicated Obstetric Emergency 1-Tap SOS Shield ────────
                _buildObstetricSosBanner(isDark),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Top Header Bar (Interactive Roles: Profile, Month, Alerts, Support) ───
  Widget _buildTopAppBar(bool isDark) {
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 1. Bear Avatar: Opens Member Quick Medical Shield Sheet
        InkWell(
          onTap: () => _showQuickProfileSheet(context, isDark),
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFE8DC),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFFF8A65).withOpacity(0.6),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.person_rounded,
                  size: 22,
                  color: isDark ? Colors.white : const Color(0xFFFF8A65),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF4081),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 2. Month Title & Calendar Icon: Opens Month Calendar Overview
        InkWell(
          onTap: () => _showMonthPickerSheet(context, isDark),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _monthName,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.calendar_today_rounded,
                  size: 16,
                  color: isDark ? const Color(0xFFFF8A65) : const Color(0xFFD84315),
                ),
              ],
            ),
          ),
        ),

        // 3. Notification Bell (with unread badge) & Support Options Menu
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => _showNotificationsSheet(context, isDark),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      Icons.notifications_none_rounded,
                      size: 24,
                      color: textColor,
                    ),
                    if (_unreadAlertCount > 0)
                      Positioned(
                        top: -3,
                        right: -3,
                        child: Container(
                          padding: const EdgeInsets.all(3.5),
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF4081),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$_unreadAlertCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: () => _showSupportOptionsSheet(context, isDark),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.more_horiz_rounded,
                  size: 24,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Weekly Calendar Strip with Pointer to Amniotic Sphere ─────────────────
  Widget _buildWeeklyCalendarStrip(bool isDark) {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final weekDates = _getCurrentWeekDates();
    final today = DateTime.now();

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(7, (i) {
            final date = weekDates[i];
            final isToday = date.day == today.day && date.month == today.month;
            final dayLetter = days[i];

            return Expanded(
              child: Column(
                children: [
                  Text(
                    isToday ? 'TODAY' : dayLetter,
                    style: TextStyle(
                      fontSize: isToday ? 9.5 : 11,
                      fontWeight: isToday ? FontWeight.w900 : FontWeight.w600,
                      color: isToday
                          ? (isDark ? const Color(0xFFFF8A65) : const Color(0xFFD84315))
                          : (isDark ? Colors.white54 : const Color(0xFF94A3B8)),
                      letterSpacing: isToday ? 0.3 : 0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (isToday)
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF8A65).withValues(alpha: 0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                        border: Border.all(
                          color: const Color(0xFFFF8A65),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${date.day}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFD84315),
                          ),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        '${date.day}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),

        // Gentle connector pointer line to center amniotic sphere
        Center(
          child: Container(
            width: 2,
            height: 12,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFFFF8A65),
                  const Color(0xFFFF8A65).withValues(alpha: 0.1),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Active Mission Banner ──────────────────────────────────────────────────
  Widget _buildActiveMissionBanner(bool isDark) {
    return GestureDetector(
      onTap: widget.onOpenMissionTracker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE11D48), Color(0xFFBE123C)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE11D48).withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.emergency_rounded, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🚨 AMBULANCE EN ROUTE • LIVE TRACKING',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    ),
                  ),
                  Text(
                    'Emergency dispatch active • Tap to view ETA & Driver Radar',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 14),
          ],
        ),
      ),
    );
  }

  // ── Centerpiece: Glowing Amniotic Sphere with 3D Baby Render ──────────────
  Widget _buildAmnioticCenterpiece(bool isDark) {
    final sphereSize = MediaQuery.of(context).size.width * 0.76;
    const fetusAsset = 'assets/images/fetus_37_weeks.jpg';

    return Center(
      child: Container(
        width: sphereSize,
        height: sphereSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: isDark
                ? [
                    const Color(0xFFFFCCBC),
                    const Color(0xFFFFAB91),
                    const Color(0xFFFF8A65),
                    const Color(0xFF3E2723),
                  ]
                : [
                    const Color(0xFFFFF3E0),
                    const Color(0xFFFFE0B2),
                    const Color(0xFFFFCC80),
                    const Color(0xFFFFAB91),
                  ],
            stops: const [0.0, 0.45, 0.75, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF8A65).withValues(alpha: isDark ? 0.35 : 0.28),
              blurRadius: 36,
              spreadRadius: 6,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipOval(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // High-resolution 3D Fetus Image Asset
              Positioned.fill(
                child: Image.asset(
                  fetusAsset,
                  key: const ValueKey('maternal_fetus_hero'),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => Center(
                    child: Icon(
                      Icons.child_care_rounded,
                      size: 96,
                      color: const Color(0xFFD84315).withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),

              // Soft ambient translucent overlay ensuring text readability
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.32),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.28),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),

              // Top Gestational Age Badge inside sphere
              Positioned(
                top: 24,
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$_weeks Weeks',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                            shadows: [
                              Shadow(
                                color: Colors.black45,
                                blurRadius: 6,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.info_outline_rounded,
                          color: Colors.white70,
                          size: 15,
                        ),
                      ],
                    ),
                    Text(
                      '$_days Days',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        shadows: const [
                          Shadow(
                            color: Colors.black45,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom 'Details' Pill Button inside sphere
              Positioned(
                bottom: 22,
                child: GestureDetector(
                  onTap: _showGestationalDetailsSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      'Details',
                      style: TextStyle(
                        color: Color(0xFF8D4315),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Daily Insights Row (3 Vibrant Cards Matching Reference Screenshot) ────
  Widget _buildDailyInsightsSection(bool isDark) {
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'My daily insights • Today',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: titleColor,
                letterSpacing: -0.2,
              ),
            ),
            GestureDetector(
              onTap: _showGestationalDetailsSheet,
              child: const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 3 Cards Row (Lavender, Mint, Yellow)
        Row(
          children: [
            // Card 1: Lavender (Pregnancy Day)
            Expanded(
              child: _buildInsightCard(
                isDark: isDark,
                borderColor: const Color(0xFFC4B5FD),
                headerBg: const Color(0xFFDDD6FE),
                tagText: 'Pregnancy day',
                tagTextColor: const Color(0xFF5B21B6),
                mainContent: Text(
                  '$_pregnancyDay',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF4C1D95),
                    letterSpacing: -1.0,
                  ),
                ),
                bottomLabel: 'Day of 280',
                onTap: _showGestationalDetailsSheet,
              ),
            ),
            const SizedBox(width: 10),

            // Card 2: Mint (Your Baby)
            Expanded(
              child: _buildInsightCard(
                isDark: isDark,
                borderColor: const Color(0xFFA7F3D0),
                headerBg: const Color(0xFFD1FAE5),
                tagText: '$_weeks weeks',
                tagTextColor: const Color(0xFF065F46),
                mainContent: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Color(0xFF059669),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.child_care_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                bottomLabel: 'Your baby',
                onTap: _showGestationalDetailsSheet,
              ),
            ),
            const SizedBox(width: 10),

            // Card 3: Late Trimester Watch-outs OR Gentle Daily Care (for early/mid trimesters)
            Expanded(
              child: _isLateTrimester
                  ? _buildInsightCard(
                      isDark: isDark,
                      borderColor: const Color(0xFFFDE68A),
                      headerBg: const Color(0xFFFEF3C7),
                      tagText: _trimesterLabel,
                      tagTextColor: const Color(0xFF92400E),
                      mainContent: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Color(0xFFD97706),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      bottomLabel: 'Watch-outs',
                      onTap: _showMaternalWatchoutsSheet,
                    )
                  : _buildInsightCard(
                      isDark: isDark,
                      borderColor: const Color(0xFFBAE6FD),
                      headerBg: const Color(0xFFF0F9FF),
                      tagText: _trimesterLabel,
                      tagTextColor: const Color(0xFF0284C7),
                      mainContent: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Color(0xFF0284C7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.spa_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      bottomLabel: 'Daily care',
                      onTap: _showDailyCareSheet,
                    ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInsightCard({
    required bool isDark,
    required Color borderColor,
    required Color headerBg,
    required String tagText,
    required Color tagTextColor,
    required Widget mainContent,
    required String bottomLabel,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 122),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Tag
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              decoration: BoxDecoration(
                color: headerBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    tagText,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: TextStyle(
                      color: tagTextColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),

            // Center Widget
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: mainContent,
                ),
              ),
            ),

            // Bottom Label
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    bottomLabel,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : const Color(0xFF334155),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Dedicated Obstetric 1-Tap SOS Emergency Shield ─────────────────────────
  Widget _buildObstetricSosBanner(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFBE123C), Color(0xFF9F1239)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFBE123C).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.heavyImpact();
            widget.onTriggerSos();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.emergency_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🌸 1-TAP OBSTETRIC EMERGENCY DISPATCH',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Rapid obstetric ambulance & certified maternity team',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Modal Sheet: Gestational Details ───────────────────────────────────────
  void _showGestationalDetailsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('🌸 ', style: TextStyle(fontSize: 22)),
                  Text(
                    'Gestational Journey: $_weeks Weeks',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildDetailMetricRow('Estimated Due Date', widget.profile.edd ?? 'Dec 15, 2026', isDark),
              _buildDetailMetricRow('Clinical Trimester', _trimesterLabel, isDark),
              _buildDetailMetricRow('Baby Size Comparison', '${widget.profile.babyFruitComparison['fruit']} (${widget.profile.babyFruitComparison['weight']})', isDark),
              _buildDetailMetricRow('Blood Group', widget.profile.cleanBloodGroup, isDark),
              _buildDetailMetricRow('Preferred Hospital', widget.profile.preferredHospitalDisplay, isDark),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD84315),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('CLOSE DETAILS', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailMetricRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? Colors.white70 : const Color(0xFF64748B),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  // ── Modal Sheet: Maternal Red Flag Watch-outs (Late Trimester Only) ────────
  void _showMaternalWatchoutsSheet() {
    if (!_isLateTrimester) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Text('⚠️ ', style: TextStyle(fontSize: 22)),
                  Text(
                    'Maternal Red Flags & Watch-outs',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildRedFlagItem('Heavy Vaginal Bleeding', 'Fresh red soaking blood indicates placenta issues. Immediate P1 dispatch.', isDark),
              _buildRedFlagItem('Sudden Fluid Gush', 'Water broke with green/brown meconium or cord prolapse risk.', isDark),
              _buildRedFlagItem('Severe Constant Headache / Blurred Vision', 'Preeclampsia warning. Immediate blood pressure triage needed.', isDark),
              _buildRedFlagItem('Absence of Fetal Movement', 'Fewer than 10 kicks in 2 hours requires rapid medical assessment.', isDark),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE11D48),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  widget.onTriggerSos();
                },
                icon: const Icon(Icons.emergency_rounded),
                label: const Text('DISPATCH RAPID OBSTETRIC AMBULANCE', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRedFlagItem(String title, String desc, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF0F172A))),
                Text(desc, style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : const Color(0xFF64748B))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Modal Sheet: Gentle Daily Care & Wellness (Early/Mid Trimesters) ───────
  void _showDailyCareSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
        final subColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('🌱 ', style: TextStyle(fontSize: 22)),
                  Expanded(
                    child: Text(
                      'Daily Care & Wellness • $_trimesterLabel',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Simple, calming daily habits to keep you and your baby feeling comfortable and nurtured.',
                style: TextStyle(fontSize: 12, color: subColor),
              ),
              const SizedBox(height: 16),
              _buildDailyCareTipTile(
                icon: Icons.water_drop_rounded,
                iconColor: const Color(0xFF0284C7),
                title: 'Gentle Hydration',
                desc: 'Drink water regularly throughout the day. Staying well-hydrated supports your natural energy and comfort.',
                isDark: isDark,
              ),
              _buildDailyCareTipTile(
                icon: Icons.bedtime_rounded,
                iconColor: const Color(0xFF7C3AED),
                title: 'Rest & Comfort',
                desc: 'Take brief rests whenever you feel fatigued. Resting comfortably on your left side optimizes circulation.',
                isDark: isDark,
              ),
              _buildDailyCareTipTile(
                icon: Icons.restaurant_rounded,
                iconColor: const Color(0xFF059669),
                title: 'Nourishing Snacks',
                desc: 'Small, frequent nutrient-rich meals help keep your blood sugar steady and reduce mild pregnancy fatigue.',
                isDark: isDark,
              ),
              _buildDailyCareTipTile(
                icon: Icons.favorite_rounded,
                iconColor: const Color(0xFFEC4899),
                title: '24/7 Specialist Support',
                desc: 'Have questions or feel uncertain? You can reach Solace obstetric specialists anytime with one tap.',
                isDark: isDark,
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Understood • Feeling Good', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDailyCareTipTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String desc,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 1. Bear Avatar: Member Quick Medical Shield Sheet ──────────────────────
  void _showQuickProfileSheet(BuildContext context, bool isDark) {
    HapticFeedback.mediumImpact();
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE8DC),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFFF8A65), width: 2),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.person_rounded,
                        size: 28,
                        color: Color(0xFFFF8A65),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.profile.fullName.isNotEmpty ? widget.profile.fullName : 'Solace Member',
                          style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: textColor),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEC4899).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '🌸 Maternal Care Plan • Active',
                            style: TextStyle(
                              color: Color(0xFFEC4899),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _buildDetailMetricRow('Gestational Age', '$_weeks Weeks $_days Days', isDark),
                    _buildDetailMetricRow('Blood Group', widget.profile.cleanBloodGroup, isDark),
                    _buildDetailMetricRow('Genotype', widget.profile.genotype ?? 'AA', isDark),
                    _buildDetailMetricRow('Preferred Hospital', widget.profile.preferredHospitalDisplay, isDark),
                    _buildDetailMetricRow('Emergency Phone', widget.profile.phone.isNotEmpty ? widget.profile.phone : '+2348133355709', isDark),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  widget.onOpenShieldTab?.call();
                },
                icon: const Icon(Icons.badge_outlined, size: 18),
                label: const Text('Open Medical ID & Care Plan', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 2. Notification Bell: Maternal Care Notifications Center ─────────────
  void _showNotificationsSheet(BuildContext context, bool isDark) {
    HapticFeedback.mediumImpact();
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final nextRefreshDisplay = MaternalContentService.getNextRefreshDisplay();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                border: Border(
                  top: BorderSide(
                    color: const Color(0xFFFF8A65).withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header with badge counter & Mark All Read
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF8A65).withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.notifications_active_rounded,
                              color: Color(0xFFFF8A65),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Care Notifications',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: textColor,
                                ),
                              ),
                              Text(
                                _unreadAlertCount > 0
                                    ? '$_unreadAlertCount new updates • $nextRefreshDisplay'
                                    : 'All notifications caught up • $nextRefreshDisplay',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (_unreadAlertCount > 0)
                        TextButton(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            _markAlertsAsAcknowledged();
                            setModalState(() {});
                          },
                          child: const Text(
                            'Mark all read',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0284C7),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Scrollable Alert Cards
                  Flexible(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. Daily Guidance & Supportive Care Tips (Filtered to remove panic/alarming cards)
                          () {
                            final safeCards = _dailyGuidanceCards.where((it) => !_isNegativeOrPanicNotification(it)).toList();
                            if (safeCards.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _buildNotificationTile(
                                  icon: '🌱',
                                  iconBg: const Color(0xFFEFF6FF),
                                  tag: 'DAILY CARE & WELLNESS',
                                  tagColor: const Color(0xFF0284C7),
                                  title: 'Daily Care Guidance',
                                  body: 'Rest well, drink plenty of water, and keep up with your daily prenatal vitamins today.',
                                  time: 'Refreshed 8:00 AM',
                                  actionLabel: 'Dismiss',
                                  onAction: () => Navigator.of(ctx).pop(),
                                  isDark: isDark,
                                ),
                              );
                            }
                            return Column(
                              children: [
                                for (final item in safeCards) ...[
                                  _buildNotificationTileFromItem(item, ctx, isDark),
                                  const SizedBox(height: 10),
                                ],
                              ],
                            );
                          }(),

                          // 2. 24/7 Obstetric Specialist Triage Line
                          _buildNotificationTile(
                            icon: '📞',
                            iconBg: const Color(0xFFDCFCE7),
                            tag: '24/7 OBSTETRIC HOTLINE',
                            tagColor: const Color(0xFF16A34A),
                            title: 'Obstetric Specialist Emergency Line',
                            body: 'Direct verbal triage line with verified obstetric coordinators at Solace Central Desk (+2348133355709).',
                            time: 'Live 24/7',
                            actionLabel: 'Call Hotline',
                            onAction: () async {
                              Navigator.of(ctx).pop();
                              final uri = Uri.parse('tel:+2348133355709');
                              try {
                                await launchUrl(uri);
                              } catch (_) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                            isDark: isDark,
                          ),
                          const SizedBox(height: 12),

                          // 3. Strict Rule 2: Educational Disclaimer Container
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 1),
                                  child: Icon(
                                    Icons.info_outline_rounded,
                                    size: 15,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    MaternalContentService.educationalDisclaimer,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildNotificationTileFromItem(
    MaternalContentItem item,
    BuildContext ctx,
    bool isDark,
  ) {
    String icon;
    Color iconBg;
    Color tagColor;

    if (item.isSafety) {
      icon = '🚨';
      iconBg = const Color(0xFFFFE4E6);
      tagColor = const Color(0xFFE11D48);
    } else if (item.isTip) {
      icon = '💡';
      iconBg = const Color(0xFFCCFBF1);
      tagColor = const Color(0xFF0D9488);
    } else {
      switch (item.slot) {
        case 'nutrition':
          icon = '🥗';
          iconBg = const Color(0xFFD1FAE5);
          tagColor = const Color(0xFF059669);
          break;
        case 'comfort':
          icon = '🌿';
          iconBg = const Color(0xFFE0F2FE);
          tagColor = const Color(0xFF0284C7);
          break;
        case 'prepare':
          icon = '📋';
          iconBg = const Color(0xFFEDE9FE);
          tagColor = const Color(0xFF7C3AED);
          break;
        case 'mind':
          icon = '🧘';
          iconBg = const Color(0xFFFCE7F3);
          tagColor = const Color(0xFFDB2777);
          break;
        case 'review':
        default:
          icon = '📑';
          iconBg = const Color(0xFFFEF3C7);
          tagColor = const Color(0xFFD97706);
          break;
      }
    }

    final hasCta = item.ctaType != 'none' && item.ctaLabel != null && item.ctaLabel!.isNotEmpty;
    final actionLabel = hasCta ? item.ctaLabel! : 'Acknowledge';

    VoidCallback onAction;
    if (item.ctaType == 'sos' || item.ctaType == 'red_flag') {
      onAction = () {
        Navigator.of(ctx).pop();
        widget.onTriggerSos();
      };
    } else if (item.ctaType == 'profile') {
      onAction = () {
        Navigator.of(ctx).pop();
        widget.onOpenShieldTab?.call();
      };
    } else {
      onAction = () {
        Navigator.of(ctx).pop();
      };
    }

    return _buildNotificationTile(
      icon: icon,
      iconBg: iconBg,
      tag: item.slotDisplayLabel,
      tagColor: tagColor,
      title: item.title,
      body: item.body,
      time: '8:00 AM Drop',
      actionLabel: actionLabel,
      onAction: onAction,
      isDark: isDark,
    );
  }
  Widget _buildNotificationTile({
    required String icon,
    required Color iconBg,
    required String tag,
    required Color tagColor,
    required String title,
    required String body,
    required String time,
    required String actionLabel,
    required VoidCallback onAction,
    required bool isDark,
  }) {
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final bodyColor = isDark ? Colors.white70 : const Color(0xFF475569);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
                child: Text(icon, style: const TextStyle(fontSize: 15)),
              ),
              const SizedBox(width: 9),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: tagColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    color: tagColor,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                time,
                style: const TextStyle(fontSize: 10.5, color: Colors.grey, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: TextStyle(fontSize: 11.5, color: bodyColor, height: 1.35),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      actionLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: tagColor,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.arrow_forward_rounded, size: 13, color: tagColor),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 3. Month Title: Month Calendar Picker Sheet ───────────────────────────
  void _showMonthPickerSheet(BuildContext context, bool isDark) {
    HapticFeedback.selectionClick();
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.calendar_month_rounded, color: Color(0xFFFF8A65), size: 22),
                  const SizedBox(width: 8),
                  Text('Gestational Timeline Overview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: textColor)),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _buildDetailMetricRow('Active Month', 'October 2026', isDark),
                    _buildDetailMetricRow('Current Progress', 'Week $_weeks • $_trimesterLabel', isDark),
                    _buildDetailMetricRow('Estimated Delivery Date', widget.profile.edd ?? 'Dec 15, 2026', isDark),
                    _buildDetailMetricRow('Days Remaining', '18 Days to full term (Day 280)', isDark),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 4. Options Menu: Quick Support & Emergency Handover ────────────────────
  void _showSupportOptionsSheet(BuildContext context, bool isDark) {
    HapticFeedback.mediumImpact();
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text('Quick Support & Assistance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: textColor)),
              const SizedBox(height: 14),
              ListTile(
                leading: const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF10B981)),
                title: const Text('24/7 Obstetric Specialist Triage Line', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                subtitle: const Text('Direct verbal handover (+2348133355709)', style: TextStyle(fontSize: 11)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final uri = Uri.parse('tel:+2348133355709');
                  try {
                    await launchUrl(uri);
                  } catch (_) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_location_rounded, color: Color(0xFF0284C7)),
                title: const Text('Share Live GPS with Next-of-Kin', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                subtitle: const Text('Broadcast realtime location to family contacts', style: TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Live GPS tracking link copied to clipboard!')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.local_hospital_rounded, color: Color(0xFFFF8A65)),
                title: const Text('Hospital Intake Center Hotline', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                subtitle: Text((widget.profile.preferredHospitalName?.isNotEmpty == true ? widget.profile.preferredHospitalName! : 'Nearest Capable Facility (Auto-Select)'), style: const TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.of(ctx).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Maternal Pre-written Daily Clinical Library Stack (Strict Rules 1-4) ───
  Widget _buildCareAlertsAndNotificationsSection(bool isDark) {
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? Colors.white60 : const Color(0xFF64748B);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section Header with Clinical Badge
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE8DC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.medical_services_outlined,
                color: Color(0xFFD84315),
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Care Notifications',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Text(
                    'Refreshes daily at 8:00 AM • ${MaternalContentService.getNextRefreshDisplay()}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: subColor,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF8A65).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFF8A65).withValues(alpha: 0.4),
                  width: 1.0,
                ),
              ),
              child: Text(
                'Week $_weeks',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFD84315),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Supportive Guidance Cards (Filtered: safe, uplifting, non-panic guidance)
        if (_loadingGuidance && _dailyGuidanceCards.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A65)),
              ),
            ),
          )
        else ...[
          () {
            final safeCards = _dailyGuidanceCards.where((c) => !_isNegativeOrPanicNotification(c)).toList();
            return Column(
              children: [
                for (int i = 0; i < safeCards.length; i++) ...[
                  _buildGuidanceCard(safeCards[i], isDark),
                  if (i < safeCards.length - 1) const SizedBox(height: 12),
                ],
              ],
            );
          }(),
        ],

        // Strict Rule 2: Educational Disclaimer Container
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  MaternalContentService.educationalDisclaimer,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGuidanceCard(MaternalContentItem item, bool isDark) {
    // Style configurations based on slot
    Color cardBg;
    Color borderColor;
    Color tagColor;
    Color tagBg;
    IconData headerIcon;

    if (item.isSafety) {
      // Urgent Safety Red/Rose Alert Card
      cardBg = isDark ? const Color(0xFF261214) : const Color(0xFFFFF1F2);
      borderColor = isDark ? const Color(0xFF881337) : const Color(0xFFFDA4AF);
      tagColor = const Color(0xFFE11D48);
      tagBg = const Color(0xFFE11D48).withValues(alpha: 0.12);
      headerIcon = Icons.warning_amber_rounded;
    } else if (item.isTip) {
      // Clinical Daily Tip Card
      cardBg = isDark ? const Color(0xFF0C2427) : const Color(0xFFF0FDFA);
      borderColor = isDark ? const Color(0xFF134E4A) : const Color(0xFF99F6E4);
      tagColor = const Color(0xFF0D9488);
      tagBg = const Color(0xFF0D9488).withValues(alpha: 0.12);
      headerIcon = Icons.lightbulb_outline_rounded;
    } else {
      // Secondary Slots (nutrition, comfort, prepare, mind, review)
      switch (item.slot) {
        case 'nutrition':
          cardBg = isDark ? const Color(0xFF0A2619) : const Color(0xFFECFDF5);
          borderColor = isDark ? const Color(0xFF064E3B) : const Color(0xFFA7F3D0);
          tagColor = const Color(0xFF059669);
          tagBg = const Color(0xFF059669).withValues(alpha: 0.12);
          headerIcon = Icons.restaurant_rounded;
          break;
        case 'comfort':
          cardBg = isDark ? const Color(0xFF0A2233) : const Color(0xFFF0F9FF);
          borderColor = isDark ? const Color(0xFF075985) : const Color(0xFFBAE6FD);
          tagColor = const Color(0xFF0284C7);
          tagBg = const Color(0xFF0284C7).withValues(alpha: 0.12);
          headerIcon = Icons.spa_outlined;
          break;
        case 'prepare':
          cardBg = isDark ? const Color(0xFF1E1436) : const Color(0xFFF5F3FF);
          borderColor = isDark ? const Color(0xFF5B21B6) : const Color(0xFFDDD6FE);
          tagColor = const Color(0xFF7C3AED);
          tagBg = const Color(0xFF7C3AED).withValues(alpha: 0.12);
          headerIcon = Icons.fact_check_outlined;
          break;
        case 'mind':
          cardBg = isDark ? const Color(0xFF2C101F) : const Color(0xFFFDF2F8);
          borderColor = isDark ? const Color(0xFF831843) : const Color(0xFFFBCFE8);
          tagColor = const Color(0xFFDB2777);
          tagBg = const Color(0xFFDB2777).withValues(alpha: 0.12);
          headerIcon = Icons.favorite_border_rounded;
          break;
        case 'review':
        default:
          cardBg = isDark ? const Color(0xFF2A1F0D) : const Color(0xFFFFFBEB);
          borderColor = isDark ? const Color(0xFF78350F) : const Color(0xFFFDE68A);
          tagColor = const Color(0xFFD97706);
          tagBg = const Color(0xFFD97706).withValues(alpha: 0.12);
          headerIcon = Icons.checklist_rounded;
          break;
      }
    }

    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final bodyColor = isDark ? Colors.white.withValues(alpha: 0.85) : const Color(0xFF334155);

    final hasCta = item.ctaType != 'none' && item.ctaLabel != null && item.ctaLabel!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Card Tag & Slot Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tagBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(headerIcon, size: 13, color: tagColor),
                    const SizedBox(width: 5),
                    Text(
                      item.slotDisplayLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: tagColor,
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
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Title
          Text(
            item.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: titleColor,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),

          // Body text
          Text(
            item.body,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w400,
              color: bodyColor,
              height: 1.45,
            ),
          ),

          // Action CTA Button
          if (hasCta) ...[
            const SizedBox(height: 12),
            _buildCardCtaButton(item, isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildCardCtaButton(MaternalContentItem item, bool isDark) {
    if (item.ctaType == 'sos' || item.ctaType == 'red_flag') {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE11D48),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
          ),
          onPressed: () {
            HapticFeedback.heavyImpact();
            widget.onTriggerSos();
          },
          icon: const Icon(Icons.emergency_rounded, size: 18),
          label: Text(
            item.ctaLabel ?? 'Trigger Solace SOS',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ),
      );
    }

    if (item.ctaType == 'profile') {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
            side: BorderSide(
              color: isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
              width: 1.5,
            ),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () {
            HapticFeedback.mediumImpact();
            widget.onOpenShieldTab?.call();
          },
          icon: const Icon(Icons.badge_rounded, size: 17),
          label: Text(
            item.ctaLabel ?? 'Open Medical ID',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  String _weekdayName(int weekday) {
    switch (weekday) {
      case 0:
        return 'Sunday';
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      default:
        return 'Daily';
    }
  }
}
