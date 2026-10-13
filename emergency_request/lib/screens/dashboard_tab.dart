import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/member_profile.dart';
import '../services/maternal_care_service.dart';
import '../theme/app_theme.dart';

class DashboardTab extends StatefulWidget {
  final MemberProfile profile;
  final VoidCallback onTriggerSos;
  final Function(String condition, int priority)? onTriggerFastPass;

  const DashboardTab({
    super.key,
    required this.profile,
    required this.onTriggerSos,
    this.onTriggerFastPass,
  });

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  final MaternalCareService _maternalService = MaternalCareService();

  @override
  void initState() {
    super.initState();
    _maternalService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _maternalService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMaternal = widget.profile.isMaternal;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Top Header ──────────────────────────────────────────────
              _buildTopHeader(isDark, isMaternal),
              const SizedBox(height: 18),

              // ── Active Shield / Gestational Journey Card ────────────────
              if (isMaternal)
                _buildGestationalJourneyCard(isDark)
              else
                _buildStandardShieldCard(isDark),

              const SizedBox(height: 18),

              // ── Interactive Kick Counter (Maternal only) ────────────────
              if (isMaternal) ...[
                _buildFetalKickCounterCard(isDark),
                const SizedBox(height: 18),
                _buildDailyRoutineCard(isDark),
                const SizedBox(height: 18),
              ],

              // ── Curated Daily Guidelines (Role Adaptive) ─────────────────
              _buildCuratedGuidelines(isDark, isMaternal),

              const SizedBox(height: 24),

              // ── Quick SOS Banner ─────────────────────────────────────────
              _buildSosBanner(isDark),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(bool isDark, bool isMaternal) {
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted;

    return Row(
      mainAxisAlignment: MainAxisAlignment.between,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  widget.profile.fullName.isNotEmpty
                      ? 'Hello, ${widget.profile.fullName.split(' ').first}'
                      : 'Solace Member',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: textColor,
                    letterSpacing: -0.5,
                  ),
                ),
                if (widget.profile.isRareBlood) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade900.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.6)),
                    ),
                    child: const Text(
                      '🩸 Rare Blood Shield',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 3),
            Text(
              isMaternal ? 'Maternal & Obstetric Care Plan' : 'Standard Emergency Shield',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: subtitleColor,
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: isDark ? AppTheme.darkCardBorder : const Color(0xFFE2E8F0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
              ),
            ],
          ),
          child: Icon(
            isMaternal ? Icons.pregnant_woman_rounded : Icons.shield_rounded,
            color: isMaternal ? const Color(0xFFEC4899) : const Color(0xFF0284C7),
            size: 26,
          ),
        ),
      ],
    );
  }

  Widget _buildGestationalJourneyCard(bool isDark) {
    final comparison = widget.profile.babyFruitComparison;
    final cardBg = isDark ? const Color(0xFF1E1035) : const Color(0xFFFDF2F8);
    final borderColor = isDark ? const Color(0xFF4C1D95) : const Color(0xFFFBCFE8);
    final weeks = widget.profile.gestationalWeeks ?? 32;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEC4899).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.between,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEC4899).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFEC4899).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Text('🌸 ', style: TextStyle(fontSize: 12)),
                    Text(
                      widget.profile.gestationalSummary,
                      style: const TextStyle(
                        color: Color(0xFFEC4899),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.profile.edd != null)
                Text(
                  'EDD: ${widget.profile.edd}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFFD8B4FE) : const Color(0xFF9D174D),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                comparison['icon'] ?? '🍍',
                style: const TextStyle(fontSize: 48),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Baby is the size of a ${comparison['fruit']}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF831843),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Approx. ${comparison['weight']} • ${comparison['length']} long',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: isDark ? const Color(0xFFE9D5FF) : const Color(0xFF9D174D),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: (weeks / 40.0).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: isDark ? Colors.black26 : const Color(0xFFFCE7F3),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFEC4899)),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.between,
            children: [
              Text(
                'Week 1',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white38 : const Color(0xFFBE185D),
                ),
              ),
              Text(
                'Full Term (Week 40)',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white60 : const Color(0xFFBE185D),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStandardShieldCard(bool isDark) {
    final cardBg = isDark ? const Color(0xFF0F1E36) : const Color(0xFFF0F9FF);
    final borderColor = isDark ? const Color(0xFF1E3A8A) : const Color(0xFFBAE6FD);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.between,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Text('🛡️ ', style: TextStyle(fontSize: 12)),
                    Text(
                      'Direct-to-Bed Guaranteed Shield',
                      style: TextStyle(
                        color: Color(0xFF0284C7),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.emerald.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '● VIP Fast-Pass Active',
                  style: TextStyle(
                    color: Color(0xFF059669),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Zero Bureaucracy Emergency Coverage',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0369A1),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Instant dispatch to accredited private trauma and secondary surgical facilities across Ibadan, Osun, and Lagos networks.',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: isDark ? const Color(0xFFBAE6FD) : const Color(0xFF0C4A6E),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFetalKickCounterCard(bool isDark) {
    final count = _maternalService.kicksCount;
    final target = MaternalCareService.targetKicks;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final cardBorder = isDark ? AppTheme.darkCardBorder : const Color(0xFFE2E8F0);
    final isAlert = _maternalService.escalationAlertActive;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAlert ? Colors.redAccent : cardBorder,
          width: isAlert ? 2.0 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.between,
            children: [
              Row(
                children: [
                  const Text('🦶 ', style: TextStyle(fontSize: 18)),
                  Text(
                    'Daily Fetal Kick Counter',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              Text(
                'Target: $target kicks / 2 hrs',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Kick count display
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _maternalService.targetReached
                      ? Colors.emerald.withValues(alpha: 0.15)
                      : const Color(0xFFEC4899).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _maternalService.targetReached
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEC4899),
                    width: 2.0,
                  ),
                ),
                child: Center(
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: _maternalService.targetReached
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEC4899),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _maternalService.targetReached
                          ? 'Target achieved! Baby is active & responsive.'
                          : 'Tap every time you feel a distinct movement, kick, or roll.',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            _maternalService.recordKick();
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('+1 Kick', style: TextStyle(fontWeight: FontWeight.w800)),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFEC4899),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            minimumSize: Size.zero,
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            _maternalService.resetKickSession();
                          },
                          child: const Text('Reset', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Clinical Escalation Warning if reduced kicks
          if (isAlert) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade900.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Reduced Fetal Movement Alert',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Fewer than 10 kicks logged in 2 hours. Clinical review is advised to verify fetal heart rate.',
                    style: TextStyle(fontSize: 11.5, color: Colors.redAccent),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () {
                      if (widget.onTriggerFastPass != null) {
                        widget.onTriggerFastPass!('Reduced Fetal Movement Alert', 1);
                      } else {
                        widget.onTriggerSos();
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                    ),
                    child: const Text('Trigger Reduced Movement SOS', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDailyRoutineCard(bool isDark) {
    final taken = _maternalService.ironFolicTakenToday;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final cardBorder = isDark ? AppTheme.darkCardBorder : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.between,
        children: [
          Row(
            children: [
              const Text('💊 ', style: TextStyle(fontSize: 22)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Iron & Folic Acid Routine',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    taken ? 'Recorded taken for today' : 'Supports fetal hemoglobin & prevents anemia',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: taken ? const Color(0xFF10B981) : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                      fontWeight: taken ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Checkbox(
            value: taken,
            activeColor: const Color(0xFF10B981),
            onChanged: (val) {
              HapticFeedback.selectionClick();
              _maternalService.toggleIronFolic(val ?? false);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCuratedGuidelines(bool isDark, bool isMaternal) {
    final list = isMaternal
        ? MaternalCareService.maternalTips
        : MaternalCareService.standardFirstAidTips;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final cardBorder = isDark ? AppTheme.darkCardBorder : const Color(0xFFE2E8F0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('💡 ', style: TextStyle(fontSize: 16)),
            Text(
              isMaternal ? 'Daily Curated Maternal Guidelines' : 'First-Aid & Emergency Preparedness',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, idx) {
            final item = list[idx];
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.between,
                    children: [
                      Text(
                        item['title']!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item['tag']!,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item['summary']!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: isDark ? AppTheme.darkTextMuted : const Color(0xFF334155),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSosBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF991B1B), Color(0xFFDC2626)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFDC2626).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Text('🚨', style: TextStyle(fontSize: 32)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Immediate Medical Distress?',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '1-tap GPS dispatch with zero folder bottlenecks.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: () {
              HapticFeedback.heavyImpact();
              widget.onTriggerSos();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFFDC2626),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            child: const Text(
              'SOS NOW',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
