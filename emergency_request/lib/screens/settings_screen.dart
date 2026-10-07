import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import 'profile_screen.dart';
import 'auth_screen.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onSwitchToSos;
  const SettingsScreen({super.key, this.onSwitchToSos});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _supabase = Supabase.instance.client;

  String? _displayName;
  String? _phone;
  String? _bloodGroup;
  String? _kinName;
  bool _loadingProfile = true;

  // Preferences
  bool _smsFallbackEnabled = true;
  bool _hapticFeedbackEnabled = true;
  bool _autoShareMedicalId = true;
  bool _highAccuracyGps = true;

  @override
  void initState() {
    super.initState();
    _loadProfileSnippet();
  }

  Future<void> _loadProfileSnippet() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _loadingProfile = false);
      return;
    }

    try {
      final res = await _supabase
          .from('profiles')
          .select('display_name, full_name, phone, blood_group, next_of_kin_name')
          .eq('user_id', uid)
          .maybeSingle();

      if (res != null && mounted) {
        setState(() {
          _displayName = res['display_name']?.toString() ??
              res['full_name']?.toString();
          _phone = res['phone']?.toString();
          _bloodGroup = res['blood_group']?.toString();
          _kinName = res['next_of_kin_name']?.toString();
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _callDesk(String phone) async {
    final uri = Uri.parse('tel:$phone');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _openWhatsApp(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$clean?text=Solace%20Emergency%20Inquiry');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _confirmSignOut() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark ? AppTheme.darkCardBorder : const Color(0xFFE2E8F0),
          ),
        ),
        title: Row(
          children: [
            const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 22),
            const SizedBox(width: 8),
            Text(
              'Sign Out?',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to log out of your Solace Emergency account?',
          style: TextStyle(
            color: isDark ? Colors.white70 : const Color(0xFF475569),
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7),
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _supabase.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const AuthScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userEmail = _supabase.auth.currentUser?.email ?? 'Solace User';

    final bgColor = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final cardColor = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final cardBorder = isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final textMuted = isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: isDark ? 0 : 0.5,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'SOLACE SETTINGS',
              style: TextStyle(
                color: textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 14.5,
                letterSpacing: 0.8,
              ),
            ),
            Text(
              'System Preferences & Medical ID',
              style: TextStyle(
                color: isDark ? const Color(0xFF81D4FA) : const Color(0xFF0284C7),
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. THEME MODE SELECTION
              _buildSectionHeader(
                title: 'APP APPEARANCE & THEME',
                icon: Icons.palette_outlined,
                color: textSecondary,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose Theme Mode',
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Switch between Tactical Night Mode for low-light emergencies or Clean Clinical Light Mode.',
                      style: TextStyle(color: textMuted, fontSize: 11, height: 1.3),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        // Dark Theme Choice
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              AppTheme.setTheme(ThemeMode.dark);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF061536),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF00D4FF)
                                      : const Color(0xFF1E3A8A),
                                  width: isDark ? 2.0 : 1.0,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.dark_mode_rounded,
                                    color: isDark ? const Color(0xFF00D4FF) : Colors.white60,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Dark Tactical',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  if (isDark)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF00D4FF).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'ACTIVE',
                                        style: TextStyle(
                                          color: Color(0xFF00D4FF),
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Light Theme Choice
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              AppTheme.setTheme(ThemeMode.light);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: !isDark
                                      ? const Color(0xFF0284C7)
                                      : const Color(0xFFCBD5E1),
                                  width: !isDark ? 2.0 : 1.0,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.light_mode_rounded,
                                    color: !isDark ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                                    size: 24,
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Light Clinical',
                                    style: TextStyle(
                                      color: Color(0xFF0F172A),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  if (!isDark)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'ACTIVE',
                                        style: TextStyle(
                                          color: Color(0xFF0284C7),
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
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
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 2. MEDICAL ID & HEALTH PROFILE CARD
              _buildSectionHeader(
                title: 'EMERGENCY MEDICAL ID',
                icon: Icons.health_and_safety_outlined,
                color: textSecondary,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF334B).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.bloodtype_rounded,
                            color: Color(0xFFFF334B),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _displayName ?? 'Clinical Profile',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Blood Group: ${_bloodGroup ?? "O+"} • Contact: ${_phone ?? "Verified"}',
                                style: TextStyle(
                                  color: textMuted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF334B).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFFFF334B).withValues(alpha: 0.4),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            _bloodGroup ?? 'O+',
                            style: const TextStyle(
                              color: Color(0xFFFF334B),
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 44,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: isDark
                              ? const Color(0xFF00D4FF)
                              : const Color(0xFF0284C7),
                          foregroundColor: isDark ? const Color(0xFF061536) : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ProfileScreen(isStandalone: true),
                            ),
                          );
                          _loadProfileSnippet();
                        },
                        icon: const Icon(Icons.edit_note_rounded, size: 18),
                        label: const Text(
                          'EDIT MEDICAL ID & NEXT OF KIN',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 3. EMERGENCY COMMUNICATIONS & HOTLINE
              _buildSectionHeader(
                title: 'DISPATCH COMMUNICATIONS & HOTLINE',
                icon: Icons.phone_in_talk_outlined,
                color: textSecondary,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.support_agent_rounded,
                            color: Color(0xFF00E676),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Central Rapid Desk Hotline',
                                style: TextStyle(
                                  color: textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                              const Text(
                                '+2348133355709 (24/7 Operations)',
                                style: TextStyle(
                                  color: Color(0xFF00E676),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF00E676),
                              side: const BorderSide(color: Color(0xFF00E676)),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _callDesk('+2348133355709'),
                            icon: const Icon(Icons.call, size: 15),
                            label: const Text('CALL HOTLINE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF25D366),
                              side: const BorderSide(color: Color(0xFF25D366)),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _openWhatsApp('+2348133355709'),
                            icon: const Icon(Icons.chat, size: 15),
                            label: const Text('WHATSAPP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24, thickness: 0.7),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _smsFallbackEnabled,
                      activeColor: isDark ? AppTheme.darkPrimary : AppTheme.lightPrimary,
                      title: Text(
                        'Offline SMS Dispatch Fallback',
                        style: TextStyle(
                          color: textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                      subtitle: Text(
                        'Automatically format SMS beacons with GPS coordinates if cellular data is offline.',
                        style: TextStyle(color: textMuted, fontSize: 11),
                      ),
                      onChanged: (val) => setState(() => _smsFallbackEnabled = val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 4. TACTICAL & MISSION PREFERENCES
              _buildSectionHeader(
                title: 'TACTICAL & SENSORY PREFERENCES',
                icon: Icons.tune_rounded,
                color: textSecondary,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _hapticFeedbackEnabled,
                      activeColor: isDark ? AppTheme.darkPrimary : AppTheme.lightPrimary,
                      title: Text(
                        'Haptic & Sound Dispatch Confirmation',
                        style: TextStyle(
                          color: textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                      subtitle: Text(
                        'Tactile feedback when ambulance is assigned or arrives at location.',
                        style: TextStyle(color: textMuted, fontSize: 11),
                      ),
                      onChanged: (val) => setState(() => _hapticFeedbackEnabled = val),
                    ),
                    const Divider(height: 16, thickness: 0.7),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _highAccuracyGps,
                      activeColor: isDark ? AppTheme.darkPrimary : AppTheme.lightPrimary,
                      title: Text(
                        'High-Precision GPS Lock (±10m)',
                        style: TextStyle(
                          color: textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                      subtitle: Text(
                        'Continuously stream real-time GPS fixes for faster paramedic navigation.',
                        style: TextStyle(color: textMuted, fontSize: 11),
                      ),
                      onChanged: (val) => setState(() => _highAccuracyGps = val),
                    ),
                    const Divider(height: 16, thickness: 0.7),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _autoShareMedicalId,
                      activeColor: isDark ? AppTheme.darkPrimary : AppTheme.lightPrimary,
                      title: Text(
                        'Auto-Share Medical ID with ER Bay',
                        style: TextStyle(
                          color: textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                      subtitle: Text(
                        'Transmit blood group, age, and allergies directly to the trauma team.',
                        style: TextStyle(color: textMuted, fontSize: 11),
                      ),
                      onChanged: (val) => setState(() => _autoShareMedicalId = val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 5. ACCOUNT & SESSION
              _buildSectionHeader(
                title: 'ACCOUNT & SYSTEM',
                icon: Icons.account_circle_outlined,
                color: textSecondary,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.email_outlined, size: 18, color: Colors.white60),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            userEmail,
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _confirmSignOut,
                        icon: const Icon(Icons.logout_rounded, size: 16),
                        label: const Text(
                          'SIGN OUT OF SOLACE',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // System footer
              Center(
                child: Column(
                  children: [
                    Text(
                      'SOLACE EMERGENCY NETWORK v2.5.0',
                      style: TextStyle(
                        color: textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Nationwide Ambulance & Trauma Bay Operations',
                      style: TextStyle(color: textMuted.withValues(alpha: 0.6), fontSize: 9.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 10.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}
