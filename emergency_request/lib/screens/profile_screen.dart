import '../utils/error_sanitizer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'auth_screen.dart';

class ProfileScreen extends StatefulWidget {
  final bool isStandalone;
  const ProfileScreen({super.key, this.isStandalone = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _conditionsController = TextEditingController();
  final _kinNameController = TextEditingController();
  final _kinPhoneController = TextEditingController();

  String _selectedBloodGroup = 'Unknown';
  String _selectedAgeBand = '18-39';
  bool _isLoading = true;
  bool _isSaving = false;
  String _currentRole = 'client';

  static const List<String> _bloodGroups = [
    'Unknown',
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  static const List<String> _ageBands = [
    '0-1',
    '2-12',
    '13-17',
    '18-39',
    '40-64',
    '65+',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _allergiesController.dispose();
    _conditionsController.dispose();
    _kinNameController.dispose();
    _kinPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final res = await _supabase
          .from('profiles')
          .select('*')
          .eq('user_id', userId)
          .maybeSingle();

      if (res != null && mounted) {
        setState(() {
          _currentRole = res['role']?.toString() ?? 'client';
          _nameController.text = res['display_name']?.toString() ??
              res['full_name']?.toString() ??
              res['name']?.toString() ??
              '';
          _phoneController.text = res['phone']?.toString() ??
              res['phone_number']?.toString() ??
              '';
          _allergiesController.text = res['allergies']?.toString() ?? '';
          _conditionsController.text = res['chronic_conditions']?.toString() ?? '';
          _kinNameController.text = res['next_of_kin_name']?.toString() ?? '';
          _kinPhoneController.text = res['next_of_kin_phone']?.toString() ?? '';

          final bg = res['blood_group']?.toString();
          if (bg != null && _bloodGroups.contains(bg)) {
            _selectedBloodGroup = bg;
          }

          final ab = res['age_band']?.toString();
          if (ab != null && _ageBands.contains(ab)) {
            _selectedAgeBand = ab;
          }
        });
      }
    } catch (e) {
      debugPrint('Profile fetch error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isSaving = true);

    try {
      final name = _nameController.text.trim();
      final phone = _phoneController.text.trim();

      final payload = <String, dynamic>{
        'user_id': userId,
        'role': _currentRole,
        'display_name': name.isNotEmpty ? name : 'Solace Client',
        'full_name': name.isNotEmpty ? name : null,
        'phone': phone.isNotEmpty ? phone : null,
        'blood_group': _selectedBloodGroup != 'Unknown' ? _selectedBloodGroup : null,
        'age_band': _selectedAgeBand,
        'allergies': _allergiesController.text.trim().isNotEmpty ? _allergiesController.text.trim() : null,
        'chronic_conditions': _conditionsController.text.trim().isNotEmpty ? _conditionsController.text.trim() : null,
        'next_of_kin_name': _kinNameController.text.trim().isNotEmpty ? _kinNameController.text.trim() : null,
        'next_of_kin_phone': _kinPhoneController.text.trim().isNotEmpty ? _kinPhoneController.text.trim() : null,
      };

      await _supabase.from('profiles').upsert(payload, onConflict: 'user_id');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Medical ID saved & synced with dispatch!'),
          backgroundColor: Color(0xFF00E676),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorSanitizer.sanitize(e, fallback: 'Failed to save Medical ID. Please try again.')),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppTheme.darkCard
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out of Solace?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
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
    final userEmail = _supabase.auth.currentUser?.email ?? 'Client';

    final bgColor = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final cardColor = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final cardBorder = isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final textMuted = isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted;
    final inputBg = isDark ? const Color(0xFF0D2559) : const Color(0xFFF1F5F9);
    final inputBorder = isDark ? const Color(0xFF20458C) : const Color(0xFF94A3B8);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: isDark ? 0 : 0.5,
        title: Text(
          'Emergency Medical ID',
          style: TextStyle(
            color: textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 15,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(Icons.logout_rounded, color: textMuted),
            tooltip: 'Sign Out',
            onPressed: _signOut,
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: isDark ? AppTheme.darkPrimary : AppTheme.lightPrimary,
              ),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Medical ID Banner
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E293B).withValues(alpha: 0.8)
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFFFF334B).withValues(alpha: 0.4)
                                : Colors.red.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF334B).withValues(alpha: 0.18),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.health_and_safety_rounded,
                                color: Color(0xFFFF334B),
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    userEmail,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'This clinical data is auto-attached to emergency requests to inform trauma bays and dispatched paramedics.',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: textMuted,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Section 1: Personal & Contact
                      _buildSectionHeader(
                        title: 'PERSONAL & CONTACT',
                        icon: Icons.person_rounded,
                        textColor: textSecondary,
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cardBorder),
                        ),
                        child: Column(
                          children: [
                            _buildTextField(
                              controller: _nameController,
                              label: 'Full Name',
                              icon: Icons.badge_outlined,
                              hint: 'e.g. Goodness Godwill',
                              inputBg: inputBg,
                              inputBorder: inputBorder,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Name is required for emergency dispatch';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            _buildTextField(
                              controller: _phoneController,
                              label: 'Emergency Contact Phone',
                              icon: Icons.phone_outlined,
                              hint: 'e.g. 09136653735',
                              keyboardType: TextInputType.phone,
                              inputBg: inputBg,
                              inputBorder: inputBorder,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Phone number is required for paramedic call';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Section 2: Clinical Profile
                      _buildSectionHeader(
                        title: 'CLINICAL PROFILE',
                        icon: Icons.local_hospital_rounded,
                        textColor: textSecondary,
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cardBorder),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                // Blood group dropdown
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _selectedBloodGroup,
                                    dropdownColor: cardColor,
                                    style: TextStyle(color: textPrimary, fontSize: 14),
                                    decoration: InputDecoration(
                                      labelText: 'Blood Group',
                                      labelStyle: TextStyle(color: textMuted, fontSize: 12),
                                      prefixIcon: const Icon(
                                        Icons.bloodtype_rounded,
                                        color: Color(0xFFFF334B),
                                        size: 20,
                                      ),
                                      filled: true,
                                      fillColor: inputBg,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: inputBorder),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: inputBorder),
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                    ),
                                    items: _bloodGroups.map((bg) {
                                      return DropdownMenuItem<String>(
                                        value: bg,
                                        child: Text(
                                          bg,
                                          style: TextStyle(
                                            color: textPrimary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => _selectedBloodGroup = val);
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Age group dropdown
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _selectedAgeBand,
                                    dropdownColor: cardColor,
                                    style: TextStyle(color: textPrimary, fontSize: 14),
                                    decoration: InputDecoration(
                                      labelText: 'Age Band',
                                      labelStyle: TextStyle(color: textMuted, fontSize: 12),
                                      prefixIcon: Icon(
                                        Icons.calendar_today_rounded,
                                        color: isDark ? AppTheme.darkPrimary : AppTheme.lightPrimary,
                                        size: 18,
                                      ),
                                      filled: true,
                                      fillColor: inputBg,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: inputBorder),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: inputBorder),
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                    ),
                                    items: _ageBands.map((ab) {
                                      return DropdownMenuItem<String>(
                                        value: ab,
                                        child: Text(
                                          '$ab yrs',
                                          style: TextStyle(
                                            color: textPrimary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => _selectedAgeBand = val);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _buildTextField(
                              controller: _allergiesController,
                              label: 'Known Allergies (Optional)',
                              icon: Icons.warning_amber_rounded,
                              hint: 'e.g. Penicillin, Latex, Peanuts',
                              inputBg: inputBg,
                              inputBorder: inputBorder,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                            ),
                            const SizedBox(height: 14),
                            _buildTextField(
                              controller: _conditionsController,
                              label: 'Chronic Conditions (Optional)',
                              icon: Icons.medical_services_outlined,
                              hint: 'e.g. Asthma, Hypertension, Diabetes',
                              inputBg: inputBg,
                              inputBorder: inputBorder,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Section 3: Next of Kin
                      _buildSectionHeader(
                        title: 'EMERGENCY NEXT OF KIN',
                        icon: Icons.people_alt_rounded,
                        textColor: textSecondary,
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cardBorder),
                        ),
                        child: Column(
                          children: [
                            _buildTextField(
                              controller: _kinNameController,
                              label: 'Next of Kin Name',
                              icon: Icons.person_outline_rounded,
                              hint: 'e.g. Segun Josephine',
                              inputBg: inputBg,
                              inputBorder: inputBorder,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                            ),
                            const SizedBox(height: 14),
                            _buildTextField(
                              controller: _kinPhoneController,
                              label: 'Next of Kin Phone',
                              icon: Icons.phone_in_talk_rounded,
                              hint: 'e.g. 08133355709',
                              keyboardType: TextInputType.phone,
                              inputBg: inputBg,
                              inputBorder: inputBorder,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),

                      // Save Button
                      SizedBox(
                        height: 50,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: isDark
                                ? const Color(0xFF00D4FF)
                                : const Color(0xFF0284C7),
                            foregroundColor: isDark ? const Color(0xFF061536) : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _isSaving ? null : _saveProfile,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_rounded, size: 20),
                          label: Text(
                            _isSaving ? 'SAVING MEDICAL ID...' : 'SAVE & SYNC MEDICAL ID',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13.5,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
    required Color textColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: textColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: textColor,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
    required Color inputBg,
    required Color inputBorder,
    required Color textPrimary,
    required Color textMuted,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: textMuted, fontSize: 12),
        hintText: hint,
        hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.6), fontSize: 13),
        prefixIcon: Icon(icon, color: textMuted, size: 20),
        filled: true,
        fillColor: inputBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: inputBorder),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}
