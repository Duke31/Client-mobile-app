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

  /// Fetch the 3-card daily stack for maternal care patients:
  /// 1. Safety Alert Card (urgent clinical warning signs with SOS CTA)
  /// 2. Daily Clinical Tip Card (gestational progress & recommendations)
  /// 3. Secondary Card (nutrition, comfort, prepare, mind, or review)
  ///
  /// Strictly checks active status and clamps gestational week to [1, 42].
  /// Weekday mapping: 0 = Sunday, 1 = Monday, ..., 6 = Saturday.
  Future<List<MaternalContentItem>> getDailyGuidanceCards({
    required int gestationalWeek,
    int? weekday,
  }) async {
    final clampedWeek = gestationalWeek.clamp(1, 42);
    final todayWeekday = weekday ?? (DateTime.now().weekday % 7);

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
    // Broad fallback if candidate list had no safety item for today's weekday
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
      // Prioritize explicit weekday match over null weekday
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
