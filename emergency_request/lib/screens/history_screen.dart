import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

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
  final Map<String, int> _ratedRequests = {};

  // ── Real-time subscription for completed/cancelled cases ─────────────────
  StreamSubscription<List<Map<String, dynamic>>>? _realtimeSub;

  // Only statuses that belong in History (terminal states)
  static const List<String> _terminalStatuses = [
    'Completed',
    'completed',
    'Cancelled / failed',
    'cancelled',
    'Canceled',
    'Failed',
  ];

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

  /// Subscribe to real-time changes on emergency_requests so the list
  /// updates automatically when a case is resolved/completed.
  void _subscribeRealtime() {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      _realtimeSub = _supabase
          .from('emergency_requests')
          .stream(primaryKey: ['id'])
          .listen((_) {
            // Re-fetch whenever any row changes for this user
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
              'created_at, client_user_id, contact_phone, hospital_id, driver_id, notes, priority',
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
            .eq('client_user_id', uid)
            .order('created_at', ascending: false)
            .limit(50);
      }

      final closed = <Map<String, dynamic>>[];
      for (final row in List<Map<String, dynamic>>.from(res)) {
        final st = (row['status']?.toString() ?? '').toLowerCase();
        if (st.contains('completed') ||
            st.contains('cancel') ||
            st.contains('failed')) {
          closed.add(row);
        }
      }

      if (mounted) {
        setState(() {
          _history = closed;
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
    final existingRating = _ratedRequests[reqId] ?? 5;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ArchivedMissionDetailSheet(
        request: req,
        initialRating: existingRating,
        onRatingUpdated: (rating, tags, comment) async {
          setState(() {
            _ratedRequests[reqId] = rating;
          });

          try {
            final oldNotes = req['notes']?.toString() ?? '';
            final feedbackPayload =
                '[PATIENT FEEDBACK: $rating★ | Tags: ${tags.join(', ')} | Note: $comment]';
            final newNotes = oldNotes.isNotEmpty
                ? '$oldNotes\n$feedbackPayload'
                : feedbackPayload;
            await _supabase
                .from('emergency_requests')
                .update({'notes': newNotes}).eq('id', reqId);
          } catch (_) {}

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Thank you! Your feedback helps optimise our emergency dispatch fleet.'),
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
    final cardBorder =
        isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder;
    final textPrimary =
        isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondary =
        isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final textMuted =
        isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted;
    final primaryColor =
        isDark ? AppTheme.darkPrimary : AppTheme.lightPrimary;

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
              'Closed Case Archive & Patient Service Reviews',
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
                                      border: Border.all(
                                          color: cardBorder, width: 1.5),
                                    ),
                                    child: Icon(
                                      Icons.history_toggle_off_rounded,
                                      size: 46,
                                      color: textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No Closed Cases Yet',
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Completed and closed emergency dispatch cases will appear here for your review.',
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
                                      backgroundColor:
                                          AppTheme.darkAccent,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 22, vertical: 12),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                    ),
                                    onPressed: widget.onSwitchToSos,
                                    icon: const Icon(
                                        Icons.emergency_rounded,
                                        size: 18),
                                    label: const Text(
                                      'Go to Emergency SOS',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold),
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
    final shortId =
        reqId.length > 8 ? reqId.substring(0, 8).toUpperCase() : reqId;
    final status = req['status']?.toString() ?? 'Completed';
    final isCompleted = status.toLowerCase().contains('complete');
    final isCancelled = status.toLowerCase().contains('cancel') ||
        status.toLowerCase().contains('fail');
    final emergencyType = req['emergency_type']?.toString() ?? 'Emergency';
    final address =
        req['patient_address']?.toString() ?? 'GPS Location Verified';
    final dateStr = _formatDate(req['created_at']?.toString());

    String? hospitalName;
    if (req['hospital'] is Map) {
      hospitalName = req['hospital']['name']?.toString();
    }

    String? driverName;
    String? vehicleLabel;
    if (req['driver'] is Map) {
      driverName = req['driver']['display_name']?.toString() ??
          req['driver']['full_name']?.toString();
      vehicleLabel = req['driver']['vehicle_label']?.toString();
    }

    final currentRating = _ratedRequests[reqId];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCompleted
              ? (isDark
                  ? const Color(0xFF00E676).withValues(alpha: 0.4)
                  : const Color(0xFF86EFAC))
              : (isCancelled
                  ? (isDark
                      ? Colors.red.withValues(alpha: 0.3)
                      : const Color(0xFFFECACA))
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
          // Only show review sheet for completed cases
          onTap: isCompleted
              ? () => _openMissionArchiveDetail(req)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Top row: Type chip, Date, Status Badge ────────────────
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF334B)
                            .withValues(alpha: isDark ? 0.15 : 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFFF334B)
                              .withValues(alpha: isDark ? 0.4 : 0.3),
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
                    _StatusBadge(
                      isCompleted: isCompleted,
                      isCancelled: isCancelled,
                      status: status,
                      isDark: isDark,
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ── Location ──────────────────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      size: 15,
                      color: isDark
                          ? AppTheme.darkPrimary
                          : AppTheme.lightPrimary,
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

                // ── Hospital & Driver row ──────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0D2559)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF1E3A8A)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.local_hospital_rounded,
                                size: 14, color: Color(0xFF00ACC1)),
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
                        color: isDark
                            ? Colors.white12
                            : const Color(0xFFCBD5E1),
                        margin:
                            const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.directions_car_rounded,
                                size: 14, color: Color(0xFF00E676)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                driverName ??
                                    (vehicleLabel ?? 'Solace Unit'),
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

                // ── Bottom: Ref ID + Rating (completed only) ──────────────
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
                    // Rating UI only for completed cases — never for active/pending
                    if (isCompleted) ...[
                      if (currentRating != null) ...[
                        Row(
                          children: List.generate(
                            5,
                            (i) => Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: i < currentRating
                                  ? Colors.amber
                                  : (isDark
                                      ? Colors.white24
                                      : Colors.grey.shade300),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Rated $currentRating★',
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ] else ...[
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark
                                ? AppTheme.darkPrimary
                                : AppTheme.lightPrimary,
                            side: BorderSide(
                              color: isDark
                                  ? AppTheme.darkPrimary
                                  : AppTheme.lightPrimary,
                              width: 0.9,
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => _openMissionArchiveDetail(req),
                          icon: const Icon(Icons.star_outline_rounded,
                              size: 14),
                          label: const Text(
                            'RATE & REVIEW',
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5),
                          ),
                        ),
                      ],
                    ] else ...[
                      // Cancelled case — no rating prompt
                      Text(
                        isCancelled ? 'CLOSED' : status.toUpperCase(),
                        style: TextStyle(
                          color: textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
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

// ── Status Badge widget ────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final bool isCompleted;
  final bool isCancelled;
  final String status;
  final bool isDark;

  const _StatusBadge({
    required this.isCompleted,
    required this.isCancelled,
    required this.status,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final Color fgColor;
    final IconData icon;
    final String label;

    if (isCompleted) {
      bgColor = isDark
          ? const Color(0xFF00E676).withValues(alpha: 0.15)
          : const Color(0xFFDCFCE7);
      fgColor = isDark ? const Color(0xFF00E676) : const Color(0xFF15803D);
      icon = Icons.check_circle_rounded;
      label = 'COMPLETED';
    } else if (isCancelled) {
      bgColor = isDark
          ? Colors.red.withValues(alpha: 0.15)
          : const Color(0xFFFEE2E2);
      fgColor = isDark ? Colors.redAccent : const Color(0xFF991B1B);
      icon = Icons.cancel_outlined;
      label = 'CANCELLED';
    } else {
      bgColor = isDark
          ? const Color(0xFF00D4FF).withValues(alpha: 0.15)
          : const Color(0xFFE0F2FE);
      fgColor =
          isDark ? const Color(0xFF00D4FF) : const Color(0xFF0369A1);
      icon = Icons.sync_rounded;
      label = status.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fgColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              color: fgColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ARCHIVED MISSION DETAIL & PATIENT FEEDBACK REPORT
// Strictly for completed cases only. No live-vibes, no tips, no radar.
// ---------------------------------------------------------------------------
class _ArchivedMissionDetailSheet extends StatefulWidget {
  final Map<String, dynamic> request;
  final int initialRating;
  final Function(int rating, List<String> tags, String comment)
      onRatingUpdated;

  const _ArchivedMissionDetailSheet({
    required this.request,
    required this.initialRating,
    required this.onRatingUpdated,
  });

  @override
  State<_ArchivedMissionDetailSheet> createState() =>
      _ArchivedMissionDetailSheetState();
}

class _ArchivedMissionDetailSheetState
    extends State<_ArchivedMissionDetailSheet> {
  late int _rating;
  final List<String> _selectedTags = [];
  final TextEditingController _commentController = TextEditingController();

  static const List<String> _availableTags = [
    'Fast Arrival',
    'Careful Driving',
    'Expert Paramedics',
    'Clean Vehicle',
    'Smooth ER Handover',
    'Clear Phone Routing',
  ];

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating;
  }

  @override
  void dispose() {
    _commentController.dispose();
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
    final cardColor = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final cardBorder =
        isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder;
    final textPrimary =
        isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textMuted =
        isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted;
    final inputBg = isDark
        ? const Color(0xFF0D2559)
        : const Color(0xFFF8FAFC);
    final primaryColor =
        isDark ? AppTheme.darkPrimary : AppTheme.lightPrimary;

    final req = widget.request;
    final reqId = req['id']?.toString() ?? '';
    final shortId =
        reqId.length > 8 ? reqId.substring(0, 8).toUpperCase() : reqId;
    final status = req['status']?.toString() ?? 'Completed';
    final isCompleted = status.toLowerCase().contains('complete');
    final emergencyType = req['emergency_type']?.toString() ?? 'Emergency';
    final address =
        req['patient_address']?.toString() ?? 'GPS Location Verified';

    String? hospitalName;
    String? hospitalAddress;
    if (req['hospital'] is Map) {
      hospitalName = req['hospital']['name']?.toString();
      hospitalAddress = req['hospital']['address']?.toString();
    }

    String? driverName;
    String? vehicleLabel;
    if (req['driver'] is Map) {
      driverName = req['driver']['display_name']?.toString() ??
          req['driver']['full_name']?.toString();
      vehicleLabel = req['driver']['vehicle_label']?.toString();
    }

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: primaryColor, width: 1.8),
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

              // ── Archive Header ────────────────────────────────────────────
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
                      isCompleted
                          ? Icons.check_circle_rounded
                          : Icons.folder_shared_rounded,
                      color: isCompleted
                          ? const Color(0xFF00E676)
                          : const Color(0xFFFF334B),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MISSION ARCHIVE REPORT',
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
              const SizedBox(height: 16),

              // ── Case Outcome Card ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0D2559)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isCompleted
                              ? Icons.verified_rounded
                              : Icons.info_outline_rounded,
                          size: 16,
                          color: isCompleted
                              ? const Color(0xFF00E676)
                              : Colors.redAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isCompleted
                              ? 'DISPATCH COMPLETED'
                              : 'DISPATCH CLOSED / CANCELLED',
                          style: TextStyle(
                            color: isCompleted
                                ? const Color(0xFF00E676)
                                : Colors.redAccent,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildArchiveRow(
                        'Pickup Location:', address, textPrimary, textMuted),
                    const SizedBox(height: 6),
                    _buildArchiveRow(
                        'Receiving Hospital:',
                        hospitalName ?? 'Regional ER Center',
                        textPrimary,
                        textMuted),
                    if (hospitalAddress != null) ...[
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(hospitalAddress,
                            style:
                                TextStyle(fontSize: 11, color: textMuted)),
                      ),
                    ],
                    const SizedBox(height: 6),
                    _buildArchiveRow(
                        'Assigned Responder:',
                        '${driverName ?? "Paramedic Unit"} (${vehicleLabel ?? "Solace Unit"})',
                        textPrimary,
                        textMuted),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ── Rating & Review (completed cases only) ────────────────────
              if (isCompleted) ...[
                Text(
                  'PATIENT SERVICE REVIEW',
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Rate your dispatch experience to help improve our emergency fleet.',
                  style: TextStyle(color: textMuted, fontSize: 11),
                ),
                const SizedBox(height: 12),

                // 5-star row
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(5, (index) {
                      final starNum = index + 1;
                      return IconButton(
                        iconSize: 34,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 3),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() => _rating = starNum);
                        },
                        icon: Icon(
                          starNum <= _rating
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: Colors.amber,
                        ),
                      );
                    }),
                  ),
                ),
                Center(
                  child: Text(
                    _rating == 5
                        ? 'Exceptional & Lifesaving'
                        : (_rating == 4
                            ? 'Very Professional & Fast'
                            : (_rating == 3
                                ? 'Standard Response'
                                : 'Needs Improvement')),
                    style: const TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5),
                  ),
                ),
                const SizedBox(height: 14),

                // Experience tags
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
                              ? (isDark
                                  ? AppTheme.darkBg
                                  : Colors.white)
                              : (isDark
                                  ? Colors.white70
                                  : AppTheme.lightTextSecondary),
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: primaryColor,
                      backgroundColor: isDark
                          ? const Color(0xFF0D2559)
                          : const Color(0xFFF1F5F9),
                      side: BorderSide(
                        color: isSelected
                            ? Colors.transparent
                            : cardBorder,
                      ),
                      onSelected: (_) => _toggleTag(tag),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),

                // Comment box
                TextField(
                  controller: _commentController,
                  maxLines: 2,
                  style: TextStyle(color: textPrimary, fontSize: 13),
                  cursorColor: primaryColor,
                  decoration: InputDecoration(
                    hintText:
                        'Optional note on paramedic conduct or triage...',
                    hintStyle:
                        TextStyle(color: textMuted, fontSize: 11.5),
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
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: primaryColor, width: 1.8),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 18),

                // Submit
                SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor:
                          isDark ? AppTheme.darkBg : Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      widget.onRatingUpdated(
                        _rating,
                        _selectedTags,
                        _commentController.text.trim(),
                      );
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text(
                      'SUBMIT EXPERIENCE REVIEW',
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                          letterSpacing: 0.5),
                    ),
                  ),
                ),
              ] else ...[
                // Cancelled — simple note, no review prompts
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'This dispatch was cancelled or closed without completion. '
                    'No service review is required.',
                    style:
                        TextStyle(color: textMuted, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArchiveRow(
      String label, String value, Color textPrimary, Color textMuted) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label,
              style: TextStyle(
                  color: textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
                color: textPrimary,
                fontSize: 11.5,
                fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

