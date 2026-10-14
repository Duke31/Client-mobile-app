import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/maternal_content_library_data.dart';
import '../models/maternal_content_item.dart';

class MaternalContentService {
  static final MaternalContentService _instance = MaternalContentService._internal();
  factory MaternalContentService() => _instance;
  MaternalContentService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Official educational disclaimer required on all clinical content cards.
  static const String educationalDisclaimer = kMaternalEducationDisclaimer;

  /// Clinical 8:00 AM Daily Cycle Anchor:
  /// Content refreshes daily at 8:00 AM.
  /// If current time is before 8:00 AM, the cycle belongs to yesterday's 8:00 AM drop.
  static DateTime getClinicalCycleDate([DateTime? target]) {
    final now = target ?? DateTime.now();
    if (now.hour < 8) {
      final yesterday = now.subtract(const Duration(days: 1));
      return DateTime(yesterday.year, yesterday.month, yesterday.day, 8, 0, 0);
    } else {
      return DateTime(now.year, now.month, now.day, 8, 0, 0);
    }
  }

  /// Exact timestamp of the next 8:00 AM content refresh.
  static DateTime getNextClinicalCycleRefresh([DateTime? target]) {
    final now = target ?? DateTime.now();
    if (now.hour < 8) {
      return DateTime(now.year, now.month, now.day, 8, 0, 0);
    } else {
      final tomorrow = now.add(const Duration(days: 1));
      return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 8, 0, 0);
    }
  }

  /// Unique daily cycle key for tracking unread status (e.g. "cycle_2026-10-14_08am").
  static String getClinicalCycleKey([DateTime? target]) {
    final c = getClinicalCycleDate(target);
    final m = c.month.toString().padLeft(2, '0');
    final d = c.day.toString().padLeft(2, '0');
    return 'cycle_${c.year}-${m}-${d}_08am';
  }

  /// Clinical weekday corresponding to the active 8:00 AM drop (0=Sunday, 1=Monday, ..., 6=Saturday).
  static int getClinicalCycleWeekday([DateTime? target]) {
    final c = getClinicalCycleDate(target);
    return c.weekday % 7;
  }

  /// Human-readable next refresh label.
  static String getNextRefreshDisplay([DateTime? target]) {
    final now = target ?? DateTime.now();
    final next = getNextClinicalCycleRefresh(now);
    final diff = next.difference(now);
    if (diff.inHours > 0) {
      return 'Refreshes in ${diff.inHours}h ${diff.inMinutes % 60}m (8:00 AM)';
    } else if (diff.inMinutes > 0) {
      return 'Refreshes in ${diff.inMinutes}m (8:00 AM)';
    } else {
      return 'Refreshes at 8:00 AM';
    }
  }

  /// Fetch the 3-card daily stack for maternal care patients:
  /// 1. Safety Alert Card (urgent clinical warning signs with SOS CTA)
  /// 2. Daily Clinical Tip Card (gestational progress & recommendations)
  /// 3. Secondary Card (nutrition, comfort, prepare, mind, or review)
  ///
  /// Content is synchronized to the 8:00 AM daily refresh cycle.
  /// Strictly checks active status and clamps gestational week to [1, 42].
  Future<List<MaternalContentItem>> getDailyGuidanceCards({
    required int gestationalWeek,
    int? weekday,
  }) async {
    final clampedWeek = gestationalWeek.clamp(1, 42);
    // Align to the 8:00 AM clinical cycle weekday by default
    final todayWeekday = weekday ?? getClinicalCycleWeekday();

    // 1. Attempt live fetch from Supabase table `maternal_content`
    try {
      final res = await _supabase
          .from('maternal_content')
          .select()
          .lte('week_start', clampedWeek)
          .gte('week_end', clampedWeek)
          .eq('active', true)
          .order('sort_order', ascending: true);

      if (res is List && res.isNotEmpty) {
        final liveItems = res
            .map((m) => MaternalContentItem.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList();
        final cards = selectDailyThreeCards(
          allItems: liveItems,
          gestationalWeek: clampedWeek,
          todayWeekday: todayWeekday,
        );
        if (cards.length == 3) {
          return cards;
        }
      }
    } catch (e) {
      debugPrint('Maternal content Supabase fetch notice (using bundled fallback): $e');
    }

    // 2. Seamless offline/bundled fallback using verified 139-card pre-written library
    final bundled = getBundledMaternalContentItems();
    return selectDailyThreeCards(
      allItems: bundled,
      gestationalWeek: clampedWeek,
      todayWeekday: todayWeekday,
    );
  }

  /// Curates the exact 3-card stack per LAB_PROMPT_maternal_library.md:
  /// Filter: week_start <= user_week <= week_end AND (weekday is null OR weekday = today).
  /// Output: safety + tip + one secondary card.
  List<MaternalContentItem> selectDailyThreeCards({
    required List<MaternalContentItem> allItems,
    required int gestationalWeek,
    required int todayWeekday,
  }) {
    final clampedWeek = gestationalWeek.clamp(1, 42);

    // Candidates matching week range and either today's weekday or any day (null)
    final candidates = allItems.where((it) {
      if (!it.active) return false;
      if (it.weekStart > clampedWeek || it.weekEnd < clampedWeek) return false;
      return it.weekday == null || it.weekday == todayWeekday;
    }).toList();

    // 1. Safety Card
    MaternalContentItem? safety = _pickBestCard(
      candidates: candidates,
      slotFilter: (s) => s == 'safety',
      todayWeekday: todayWeekday,
    );
    safety ??= _pickFallbackCard(
      allItems: allItems,
      gestationalWeek: clampedWeek,
      slotFilter: (s) => s == 'safety',
    );

    // 2. Daily Tip Card
    MaternalContentItem? tip = _pickBestCard(
      candidates: candidates,
      slotFilter: (s) => s == 'tip',
      todayWeekday: todayWeekday,
    );
    tip ??= _pickFallbackCard(
      allItems: allItems,
      gestationalWeek: clampedWeek,
      slotFilter: (s) => s == 'tip',
    );

    // 3. One Secondary Card (nutrition, comfort, prepare, mind, or review)
    const secondarySlots = {'nutrition', 'comfort', 'prepare', 'mind', 'review'};
    MaternalContentItem? secondary = _pickBestCard(
      candidates: candidates,
      slotFilter: (s) => secondarySlots.contains(s),
      todayWeekday: todayWeekday,
    );
    secondary ??= _pickFallbackCard(
      allItems: allItems,
      gestationalWeek: clampedWeek,
      slotFilter: (s) => secondarySlots.contains(s),
    );

    final result = <MaternalContentItem>[];
    if (safety != null) result.add(safety);
    if (tip != null) result.add(tip);
    if (secondary != null) result.add(secondary);

    return result;
  }

  MaternalContentItem? _pickBestCard({
    required List<MaternalContentItem> candidates,
    required bool Function(String slot) slotFilter,
    required int todayWeekday,
  }) {
    final matching = candidates.where((c) => slotFilter(c.slot)).toList();
    if (matching.isEmpty) return null;

    matching.sort((a, b) {
      final aDayMatch = a.weekday == todayWeekday ? 0 : 1;
      final bDayMatch = b.weekday == todayWeekday ? 0 : 1;
      if (aDayMatch != bDayMatch) return aDayMatch.compareTo(bDayMatch);
      return a.sortOrder.compareTo(b.sortOrder);
    });

    return matching.first;
  }

  MaternalContentItem? _pickFallbackCard({
    required List<MaternalContentItem> allItems,
    required int gestationalWeek,
    required bool Function(String slot) slotFilter,
  }) {
    final matches = allItems.where((it) {
      if (!it.active) return false;
      if (it.weekStart > gestationalWeek || it.weekEnd < gestationalWeek) return false;
      return slotFilter(it.slot);
    }).toList();

    if (matches.isEmpty) return null;
    matches.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return matches.first;
  }
}
