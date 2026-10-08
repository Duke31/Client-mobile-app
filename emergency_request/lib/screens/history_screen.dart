import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class PatientReviewData {
  final int rating;
  final String remark;
  final List<String> tags;
  final String? submittedAt;

  const PatientReviewData({
    required this.rating,
    required this.remark,
    this.tags = const [],
    this.submittedAt,
  });
}

PatientReviewData? parseReviewFromNotes(String? notes) {
  if (notes == null || notes.isEmpty) return null;

  // Matches [PATIENT REVIEW ★★★★★ (5/5)]: remark | TAGS: ...
  // or [PATIENT FEEDBACK: 5★ | Tags: ... | Note: ...]
  final starMatch = RegExp(
    r'PATIENT (?:REVIEW|FEEDBACK|RATING)[^:]*:\s*([1-5])(?:\/5)?(?:★|\s*stars?)?',
    caseSensitive: false,
  ).firstMatch(notes) ?? RegExp(r'([1-5])★').firstMatch(notes);

  if (starMatch == null) return null;
  final rating = int.tryParse(starMatch.group(1) ?? '5') ?? 5;

  String remark = '';
  final remarkMatch = RegExp(
    r'\[PATIENT REVIEW [^:]+:\s*([^|\]]+)',
    caseSensitive: false,
  ).firstMatch(notes) ?? RegExp(
    r'(?:REMARK|Note):\s*([^|\]\n\r]+)',
    caseSensitive: false,
  ).firstMatch(notes);

  if (remarkMatch != null) {
    remark = remarkMatch.group(1)?.trim() ?? '';
  }

  final tags = <String>[];
  final tagsMatch = RegExp(
    r'(?:Tags|TAGS):\s*([^|\]\n\r]+)',
    caseSensitive: false,
  ).firstMatch(notes);

  if (tagsMatch != null) {
    for (final t in (tagsMatch.group(1) ?? '').split(',')) {
      final tr = t.trim();
      if (tr.isNotEmpty && tr.toLowerCase() != 'none') {
        tags.add(tr);
      }
    }
  }

  return PatientReviewData(
    rating: rating,
    remark: remark.isNotEmpty ? remark : 'Emergency service completed.',
    tags: tags,
  );
}

class HistoryScreen extends StatefulWidget {
  final VoidCallback? onSwitchToSos;
  const HistoryScreen({super.key, this.onSwitchToSos});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _history = [];
  final Map<String, PatientReviewData> _reviews = {};
  StreamSubscription<List<Map<String, dynamic>>>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  void _subscribeRealtime() {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      _realtimeSub = _supabase
          .from('emergency_requests')
          .stream(primaryKey: ['id'])
          .listen((_) {
            _fetchHistory();
          }, onError: (_) {});
    } catch (_) {}
  }

  Future<void> _fetchHistory() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      List<dynamic> res = [];
      try {
        res = await _supabase
            .from('emergency_requests')
            .select(
              'id, status, emergency_type, patient_address, patient_lat, patient_lng, '
              'created_at, client_user_id, contact_phone, hospital_id, driver_id, notes, priority, '
              'hospital:hospitals(name, address), driver:drivers(display_name, full_name, vehicle_label)',
            )
            .or('client_user_id.eq.$uid,reported_by_user_id.eq.$uid')
            .order('created_at', ascending: false)
            .limit(50);
      } catch (_) {
        res = await _supabase
            .from('emergency_requests')
            .select(
              'id, status, emergency_type, patient_address, patient_lat, patient_lng, '
              'created_at, client_user_id, contact_phone, hospital_id, driver_id, notes, priority',
            )
            .or('client_user_id.eq.$uid,reported_by_user_id.eq.$uid')
            .order('created_at', ascending: false)
            .limit(50);
      }

      final closed = <Map<String, dynamic>>[];
      final Map<String, PatientReviewData> parsedReviews = {};

      for (final row in List<Map<String, dynamic>>.from(res)) {
        final st = (row['status']?.toString() ?? '').toLowerCase();
        if (st.contains('completed') ||
            st.contains('cancel') ||
            st.contains('failed')) {
          closed.add(row);
          final notes = row['notes']?.toString();
          final rId = row['id']?.toString() ?? '';
          final review = parseReviewFromNotes(notes);
          if (review != null && rId.isNotEmpty) {
            parsedReviews[rId] = review;
          }
        }
      }

      if (mounted) {
        setState(() {
          _history = closed;
          _reviews.addAll(parsedReviews);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('History fetch error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openMissionArchiveDetail(Map<String, dynamic> req) {
    HapticFeedback.lightImpact();
    final reqId = req['id']?.toString() ?? '';
    final existingReview = _reviews[reqId];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ArchivedMissionDetailSheet(
        request: req,
        existingReview: existingReview,
        onRatingUpdated: (rating, remark, tags) async {
          final reviewObj = PatientReviewData(
            rating: rating,
            remark: remark,
            tags: tags,
            submittedAt: DateTime.now().toIso8601String(),
          );

          setState(() {
            _reviews[reqId] = reviewObj;
          });

          final oldNotes = req['notes']?.toString() ?? '';
          final cleanNotes = oldNotes
              .replaceAll(RegExp(r'\[PATIENT (?:REVIEW|FEEDBACK|RATING)[^\]]*\]', caseSensitive: false), '')
              .trim();
          final dateStr = DateTime.now().toString().split('.').first;
          final payload =
              '[PATIENT REVIEW ${'★' * rating}${'☆' * (5 - rating)} ($rating/5)]: $remark | TAGS: ${tags.join(', ')} | SUBMITTED: $dateStr]';
          final newNotes = cleanNotes.isNotEmpty ? '$cleanNotes\n$payload' : payload;

          setState(() {
            _reviews[reqId] = reviewObj;
            req['notes'] = newNotes;
          });

          // 1. Save to Supabase via dedicated SECURITY DEFINER RPC
          try {
            await _supabase.rpc('client_submit_patient_review', params: {
              'p_request_id': reqId,
              'p_rating': rating,
              'p_remark': remark,
              'p_tags': tags,
            });
          } catch (rpcErr) {
            debugPrint('client_submit_patient_review RPC note: $rpcErr');
            try {
              await _supabase.from('emergency_requests').update({'notes': newNotes}).eq('id', reqId);
            } catch (err) {
              debugPrint('Supabase direct update notice: $err');
            }
          }

          // 2. Guaranteed server-side persist via Ops Dashboard /api/reviews (service role backed)
          try {
            final url = Uri.parse('https://ops-dashboard-eta-ten.vercel.app/api/reviews');
            final resp = await http.post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'requestId': reqId,
                'rating': rating,
                'remark': remark,
                'tags': tags,
              }),
            );
            if (resp.statusCode == 200) {
              final data = jsonDecode(resp.body);
              if (data is Map && data['notes'] != null) {
                req['notes'] = data['notes'];
              }
            }
          } catch (_) {}

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Thank you! Your rating and remarks have been logged for dispatch review.'),
                backgroundColor: Color(0xFF00E676),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return 'Recent';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final month = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][dt.month - 1];
      final hour = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$month ${dt.day}, ${dt.year} • $hour:$min';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final cardColor = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final cardBorder = isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final textMuted = isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted;
    final primaryColor = isDark ? AppTheme.darkPrimary : AppTheme.lightPrimary;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: isDark ? 0 : 0.5,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'EMERGENCY HISTORY',
              style: TextStyle(
                color: textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 14.5,
                letterSpacing: 0.8,
              ),
            ),
            Text(
              'Past Emergency Cases & Patient Service Reviews',
              style: TextStyle(
                color: textSecondary,
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: primaryColor),
            tooltip: 'Refresh History',
            onPressed: _fetchHistory,
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: primaryColor),
            )
          : RefreshIndicator(
              onRefresh: _fetchHistory,
              color: primaryColor,
              backgroundColor: cardColor,
              child: _history.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.7,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(28.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: cardColor,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: cardBorder, width: 1.5),
                                    ),
                                    child: Icon(
                                      Icons.history_toggle_off_rounded,
                                      size: 46,
                                      color: textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No Emergency History',
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Your previous emergency dispatch cases and patient feedback will appear here.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: textMuted,
                                      fontSize: 12.5,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFFD32F2F),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onPressed: widget.onSwitchToSos,
                                    icon: const Icon(Icons.emergency_rounded, size: 18),
                                    label: const Text(
                                      'Go to Emergency SOS',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        final req = _history[index];
                        return _buildHistoryCard(
                          req: req,
                          isDark: isDark,
                          cardColor: cardColor,
                          cardBorder: cardBorder,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                          textMuted: textMuted,
                        );
                      },
                    ),
            ),
    );
  }

  Widget _buildHistoryCard({
    required Map<String, dynamic> req,
    required bool isDark,
    required Color cardColor,
    required Color cardBorder,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
  }) {
    final reqId = req['id']?.toString() ?? '';
    final shortId = reqId.length > 8 ? reqId.substring(0, 8).toUpperCase() : reqId;
    final status = req['status']?.toString() ?? 'Closed';
    final isCompleted = status.toLowerCase().contains('complete');
    final isCancelled = status.toLowerCase().contains('cancel') || status.toLowerCase().contains('fail');
    final emergencyType = req['emergency_type']?.toString() ?? 'Emergency';
    final address = req['patient_address']?.toString() ?? 'GPS Location Verified';
    final dateStr = _formatDate(req['created_at']?.toString());

    // Responders extraction
    String? hospitalName;
    if (req['hospital'] is Map) {
      hospitalName = req['hospital']['name']?.toString();
    }
    String? driverName;
    String? vehicleLabel;
    if (req['driver'] is Map) {
      driverName = req['driver']['display_name']?.toString() ?? req['driver']['full_name']?.toString();
      vehicleLabel = req['driver']['vehicle_label']?.toString();
    }

    final review = _reviews[reqId];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCompleted
              ? (isDark ? const Color(0xFF00E676).withValues(alpha: 0.4) : const Color(0xFF86EFAC))
              : (isCancelled
                  ? (isDark ? Colors.red.withValues(alpha: 0.3) : const Color(0xFFFECACA))
                  : cardBorder),
          width: 1.0,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openMissionArchiveDetail(req),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Type chip, Date, Status Badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF334B).withValues(alpha: isDark ? 0.15 : 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFFF334B).withValues(alpha: isDark ? 0.4 : 0.3),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        emergencyType.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFFFF334B),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        dateStr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? (isDark ? const Color(0xFF00E676).withValues(alpha: 0.15) : const Color(0xFFDCFCE7))
                            : (isCancelled
                                ? (isDark ? Colors.red.withValues(alpha: 0.15) : const Color(0xFFFEE2E2))
                                : (isDark ? const Color(0xFF00D4FF).withValues(alpha: 0.15) : const Color(0xFFE0F2FE))),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isCompleted
                                ? Icons.check_circle_rounded
                                : (isCancelled ? Icons.cancel_outlined : Icons.sync_rounded),
                            size: 12,
                            color: isCompleted
                                ? (isDark ? const Color(0xFF00E676) : const Color(0xFF15803D))
                                : (isCancelled
                                    ? (isDark ? Colors.redAccent : const Color(0xFF991B1B))
                                    : (isDark ? const Color(0xFF00D4FF) : const Color(0xFF0369A1))),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isCompleted ? 'COMPLETED' : (isCancelled ? 'CANCELLED' : status),
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              color: isCompleted
                                  ? (isDark ? const Color(0xFF00E676) : const Color(0xFF15803D))
                                  : (isCancelled
                                      ? (isDark ? Colors.redAccent : const Color(0xFF991B1B))
                                      : (isDark ? const Color(0xFF00D4FF) : const Color(0xFF0369A1))),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Location line
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      size: 15,
                      color: isDark ? AppTheme.darkPrimary : AppTheme.lightPrimary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Responders involved
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0D2559) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.local_hospital_rounded, size: 14, color: Color(0xFF00ACC1)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                hospitalName ?? 'Regional ER Bay',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 16,
                        width: 1,
                        color: isDark ? Colors.white12 : const Color(0xFFCBD5E1),
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.directions_car_rounded, size: 14, color: Color(0xFF00E676)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                driverName ?? (vehicleLabel ?? 'Solace Unit'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // ── DEDICATED RATING & REMARK SECTION ──────────────────
                if (review != null) ...[
                  Container(
                    margin: const EdgeInsets.only(top: 2, bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF0A1E46)
                          : const Color(0xFFFEF9C3).withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.35)
                            : const Color(0xFFFDE047),
                        width: 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Row(
                              children: List.generate(
                                5,
                                (i) => Icon(
                                  Icons.star_rounded,
                                  size: 15,
                                  color: i < review.rating
                                      ? Colors.amber
                                      : (isDark ? Colors.white24 : Colors.grey.shade300),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${review.rating}.0 / 5.0',
                              style: const TextStyle(
                                color: Colors.amber,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            InkWell(
                              onTap: () => _openMissionArchiveDetail(req),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.edit_note_rounded,
                                    size: 14,
                                    color: isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7),
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    'Edit Remark',
                                    style: TextStyle(
                                      color: isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (review.remark.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            '“${review.remark}”',
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 11.5,
                              fontStyle: FontStyle.italic,
                              height: 1.3,
                            ),
                          ),
                        ],
                        if (review.tags.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: review.tags.map((t) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF0D2559) : Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFCBD5E1),
                                  ),
                                ),
                                child: Text(
                                  '✓ $t',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? const Color(0xFF81D4FA) : const Color(0xFF0284C7),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                // Ref ID + Action Trigger
                Row(
                  children: [
                    Text(
                      'Ref #$shortId',
                      style: TextStyle(
                        color: textMuted,
                        fontSize: 10.5,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    if (review == null)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? AppTheme.darkPrimary : AppTheme.lightPrimary,
                          side: BorderSide(
                            color: isDark ? AppTheme.darkPrimary : AppTheme.lightPrimary,
                            width: 0.9,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _openMissionArchiveDetail(req),
                        icon: const Icon(Icons.star_outline_rounded, size: 14),
                        label: const Text(
                          '★ ADD RATING & REMARK',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 0.4),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ARCHIVED MISSION DETAIL & PATIENT REMARK SHEET
// Clean archival case report with star rating and remark text input
// ---------------------------------------------------------------------------
class _ArchivedMissionDetailSheet extends StatefulWidget {
  final Map<String, dynamic> request;
  final PatientReviewData? existingReview;
  final Function(int rating, String remark, List<String> tags) onRatingUpdated;

  const _ArchivedMissionDetailSheet({
    required this.request,
    this.existingReview,
    required this.onRatingUpdated,
  });

  @override
  State<_ArchivedMissionDetailSheet> createState() => _ArchivedMissionDetailSheetState();
}

class _ArchivedMissionDetailSheetState extends State<_ArchivedMissionDetailSheet> {
  late int _rating;
  late final List<String> _selectedTags;
  late final TextEditingController _remarkController;

  static const List<String> _availableTags = [
    'Fast Arrival',
    'Careful Driving',
    'Expert Paramedics',
    'Clean Vehicle',
    'Smooth ER Handover',
    'Clear Communications',
    'Empathetic Care',
  ];

  @override
  void initState() {
    super.initState();
    _rating = widget.existingReview?.rating ?? 5;
    _selectedTags = List<String>.from(widget.existingReview?.tags ?? []);
    _remarkController = TextEditingController(text: widget.existingReview?.remark ?? '');
  }

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  void _toggleTag(String tag) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF07193F) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF1E3A8A) : const Color(0xFFCBD5E1);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? Colors.white60 : const Color(0xFF64748B);
    final inputBg = isDark ? const Color(0xFF0D2559) : const Color(0xFFF8FAFC);

    final req = widget.request;
    final reqId = req['id']?.toString() ?? '';
    final shortId = reqId.length > 8 ? reqId.substring(0, 8).toUpperCase() : reqId;
    final status = req['status']?.toString() ?? 'Closed';
    final isCompleted = status.toLowerCase().contains('complete');
    final isCancelled = status.toLowerCase().contains('cancel') || status.toLowerCase().contains('fail');
    final emergencyType = req['emergency_type']?.toString() ?? 'Emergency';
    final address = req['patient_address']?.toString() ?? 'GPS Location Verified';

    String? hospitalName;
    if (req['hospital'] is Map) {
      hospitalName = req['hospital']['name']?.toString();
    }
    String? driverName;
    String? vehicleLabel;
    if (req['driver'] is Map) {
      driverName = req['driver']['display_name']?.toString() ?? req['driver']['full_name']?.toString();
      vehicleLabel = req['driver']['vehicle_label']?.toString();
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(
              color: isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7),
              width: 1.8,
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Archive Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? const Color(0xFF00E676).withValues(alpha: 0.15)
                          : const Color(0xFFFF334B).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isCompleted ? Icons.check_circle_rounded : Icons.folder_shared_rounded,
                      color: isCompleted ? const Color(0xFF00E676) : const Color(0xFFFF334B),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MISSION ARCHIVE & REMARKS',
                          style: TextStyle(
                            color: textPrimary,
                            fontWeight: FontWeight.w900,
                            fontSize: 14.5,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          'Case Reference: #$shortId • $emergencyType',
                          style: TextStyle(color: textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Case Summary
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0D2559) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  children: [
                    _buildArchiveRow('Pickup Location:', address, textPrimary, textMuted),
                    const SizedBox(height: 6),
                    _buildArchiveRow('Hospital ER:', hospitalName ?? 'Regional ER Center', textPrimary, textMuted),
                    const SizedBox(height: 6),
                    _buildArchiveRow('Ambulance Crew:', '${driverName ?? "Paramedic Unit"} (${vehicleLabel ?? "Solace Unit"})', textPrimary, textMuted),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // RATING SECTION
              Text(
                'RATE DISPATCH & EMS EXPERIENCE',
                style: TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Tap stars to score the response speed and medical bedside care.',
                style: TextStyle(color: textMuted, fontSize: 11),
              ),
              const SizedBox(height: 10),

              // 5 Stars row
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (index) {
                    final starNum = index + 1;
                    return IconButton(
                      iconSize: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() => _rating = starNum);
                      },
                      icon: Icon(
                        starNum <= _rating ? Icons.star_rounded : Icons.star_border_rounded,
                        color: Colors.amber,
                      ),
                    );
                  }),
                ),
              ),
              Center(
                child: Text(
                  _rating == 5
                      ? '5.0 ★ Exceptional & Lifesaving'
                      : (_rating == 4
                          ? '4.0 ★ Very Professional & Fast'
                          : (_rating == 3
                              ? '3.0 ★ Standard Response'
                              : (_rating == 2 ? '2.0 ★ Needs Dispatch Follow-up' : '1.0 ★ Critical Concern'))),
                  style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              const SizedBox(height: 16),

              // PATIENT REMARK TEXT FIELD
              Text(
                'YOUR REMARK & FEEDBACK',
                style: TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'This remark is audited by Solace Emergency Dispatchers and Admins.',
                style: TextStyle(color: textMuted, fontSize: 11),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _remarkController,
                maxLines: 3,
                style: TextStyle(color: textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Enter your remarks regarding the ambulance arrival time, paramedic care, or hospital intake...',
                  hintStyle: TextStyle(color: textMuted, fontSize: 11.5),
                  filled: true,
                  fillColor: inputBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cardBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cardBorder),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 14),

              // Experience Tags
              Text(
                'SERVICE HIGHLIGHTS (OPTIONAL)',
                style: TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableTags.map((tag) {
                  final isSelected = _selectedTags.contains(tag);
                  return FilterChip(
                    label: Text(
                      tag,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? (isDark ? const Color(0xFF061536) : Colors.white)
                            : (isDark ? Colors.white70 : const Color(0xFF334155)),
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7),
                    backgroundColor: isDark ? const Color(0xFF0D2559) : const Color(0xFFF1F5F9),
                    side: BorderSide(
                      color: isSelected
                          ? Colors.transparent
                          : (isDark ? const Color(0xFF1E3A8A) : const Color(0xFFCBD5E1)),
                    ),
                    onSelected: (_) => _toggleTag(tag),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // SUBMIT BUTTON
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7),
                    foregroundColor: isDark ? const Color(0xFF061536) : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    widget.onRatingUpdated(
                      _rating,
                      _remarkController.text.trim(),
                      _selectedTags,
                    );
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text(
                    'SUBMIT RATING & REMARK',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArchiveRow(String label, String value, Color textPrimary, Color textMuted) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: TextStyle(color: textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
