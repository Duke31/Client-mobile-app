import '../utils/error_sanitizer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/member_profile.dart';
import '../theme/app_theme.dart';
import 'auth_screen.dart';

class ProfileScreen extends StatefulWidget {
  final bool isStandalone;
  final VoidCallback? onProfileUpdated;

  const ProfileScreen({
    super.key,
    this.isStandalone = false,
    this.onProfileUpdated,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  // Personal controllers
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _conditionsController = TextEditingController();
  final _kinNameController = TextEditingController();
  final _kinPhoneController = TextEditingController();

  // Maternal controllers
  final _gravidaParaController = TextEditingController();
  final _eddController = TextEditingController();
  final _lmpController = TextEditingController();

  String _carePlan = 'standard'; // 'standard' | 'maternal'
  String _selectedBloodGroup = 'Unknown';
  String _selectedGenotype = 'AA';
  String _selectedAgeBand = '18-39';
  String _preferredHospital = 'None / Auto-Select (Nearest Capable Facility)';
  final List<String> _selectedRisks = [];

  bool _isLoading = true;
  bool _isSaving = false;
  String _currentRole = 'client';

  static const List<String> _bloodGroups = MemberProfile.validBloodGroups;
  static const List<String> _genotypes = ['AA', 'AS', 'SS', 'AC', 'SC'];
  static const List<Map<String, String>> _ageBands = MemberProfile.ageBandOptions;
  static const List<String> _maternalRiskOptions = MemberProfile.maternalRiskOptions;

  static const List<String> _hospitals = [
    'None / Auto-Select (Nearest Capable Facility)',
    'LifeCare Private Clinic (Ring Road, Ibadan)',
    'Bodija Premier Medical Center (Ibadan)',
    'University College Hospital - UCH Private Wing (Ibadan)',
    'Asubiaro State Hospital (Osogbo, Osun State)',
    'UNIOSUN Teaching Hospital (Osun State)',
    'Lagos University Teaching Hospital - LUTH (Lagos)',
    'First Cardiology / Lekki Medical Center (Lagos)',
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
    _dobController.dispose();
    _allergiesController.dispose();
    _conditionsController.dispose();
    _kinNameController.dispose();
    _kinPhoneController.dispose();
    _gravidaParaController.dispose();
    _eddController.dispose();
    _lmpController.dispose();
    super.dispose();
  }

  /// Derived age in complete years from DOB
  int? get _derivedAge {
    final text = _dobController.text.trim();
    if (text.isEmpty) return null;
    final dob = DateTime.tryParse(text);
    if (dob == null) return null;
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age >= 0 ? age : null;
  }

  /// Effective age band
  String get _effectiveAgeBand {
    final age = _derivedAge;
    if (age != null) {
      if (age <= 1) return '0-1';
      if (age <= 12) return '2-12';
      if (age <= 17) return '13-17';
      if (age <= 39) return '18-39';
      if (age <= 64) return '40-64';
      return '65+';
    }
    return _selectedAgeBand;
  }

  /// Centralized read-only gestational age calculation strictly from EDD or LMP
  int get _computedElapsedDays {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (_lmpController.text.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(_lmpController.text.trim());
      if (parsed != null) {
        final lmpDay = DateTime(parsed.year, parsed.month, parsed.day);
        final elapsed = today.difference(lmpDay).inDays;
        return elapsed.clamp(7, 294);
      }
    }

    if (_eddController.text.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(_eddController.text.trim());
      if (parsed != null) {
        final eddDay = DateTime(parsed.year, parsed.month, parsed.day);
        final daysUntilDue = eddDay.difference(today).inDays;
        final elapsed = 280 - daysUntilDue;
        return elapsed.clamp(7, 294);
      }
    }

    return 224; // Baseline default: 32 weeks
  }

  int get _computedWeeks => (_computedElapsedDays ~/ 7).clamp(1, 42);
  int get _computedDays => (_computedElapsedDays % 7).clamp(0, 6);

  String get _trimesterLabel {
    final w = _computedWeeks;
    if (w <= 13) return '1st Trimester';
    if (w <= 27) return '2nd Trimester';
    return '3rd Trimester';
  }

  Future<void> _pickDate({
    required TextEditingController controller,
    required String title,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
    VoidCallback? onSelected,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: title,
    );
    if (picked != null) {
      final iso = "${picked.year.toString().padLeft(4, '0')}-"
          "${picked.month.toString().padLeft(2, '0')}-"
          "${picked.day.toString().padLeft(2, '0')}";
      setState(() {
        controller.text = iso;
        onSelected?.call();
      });
    }
  }

  Future<void> _loadProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final res = await _supabase
          .from('profiles')
          .select('*')
          .eq('user_id', user.id)
          .maybeSingle();

      final meta = user.userMetadata ?? {};

      if (mounted) {
        setState(() {
          if (res != null) {
            _currentRole = res['role']?.toString() ?? 'client';
            _nameController.text = res['display_name']?.toString() ??
                res['full_name']?.toString() ??
                meta['full_name']?.toString() ??
                '';
            _phoneController.text = res['phone']?.toString() ??
                meta['phone']?.toString() ??
                '';
            _allergiesController.text = res['allergies']?.toString() ??
                meta['allergies']?.toString() ??
                '';
            _conditionsController.text = res['chronic_conditions']?.toString() ??
                meta['chronic_conditions']?.toString() ??
                '';
            _kinNameController.text = res['next_of_kin_name']?.toString() ??
                meta['next_of_kin_name']?.toString() ??
                '';
            _kinPhoneController.text = res['next_of_kin_phone']?.toString() ??
                meta['next_of_kin_phone']?.toString() ??
                '';

            final rawType = (res['care_plan']?.toString() ??
                    res['profile_type']?.toString() ??
                    meta['care_plan']?.toString() ??
                    (res['is_pregnant'] == true ? 'maternal' : 'standard'))
                .toLowerCase();
            _carePlan = rawType.contains('maternal') ? 'maternal' : 'standard';

            _gravidaParaController.text = res['gravida_para']?.toString() ??
                meta['gravida_para']?.toString() ??
                '';
            _eddController.text = res['edd']?.toString() ??
                meta['edd']?.toString() ??
                '';
            _lmpController.text = meta['lmp_date']?.toString() ?? '';

            final bg = res['blood_group']?.toString() ?? meta['blood_group']?.toString();
            if (bg != null) {
              final clean = MemberProfile.sanitizeBloodGroup(bg);
              _selectedBloodGroup = _bloodGroups.contains(clean) ? clean : 'Unknown';
            }

            final geno = res['genotype']?.toString() ?? meta['genotype']?.toString();
            if (geno != null && _genotypes.contains(geno)) {
              _selectedGenotype = geno;
            }

            final ab = res['age_band']?.toString() ?? meta['age_band']?.toString();
            if (ab != null && _ageBands.any((e) => e['value'] == ab)) {
              _selectedAgeBand = ab;
            }

            final dob = meta['date_of_birth']?.toString();
            if (dob != null && dob.isNotEmpty) {
              _dobController.text = dob;
            }

            final hosp = res['preferred_hospital']?.toString();
            if (hosp != null && hosp.isNotEmpty && _hospitals.contains(hosp)) {
              _preferredHospital = hosp;
            } else {
              _preferredHospital = 'None / Auto-Select (Nearest Capable Facility)';
            }

            if (res['known_risks'] is List) {
              _selectedRisks.clear();
              _selectedRisks.addAll(List<String>.from(res['known_risks']));
            } else if (meta['known_risks'] is List) {
              _selectedRisks.clear();
              _selectedRisks.addAll(List<String>.from(meta['known_risks']));
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Profile fetch error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handlePlanToggle(String newPlan) async {
    if (newPlan == _carePlan) return;

    if (_carePlan == 'maternal' && newPlan == 'standard') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? AppTheme.darkCard
              : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Switch to Standard Care Plan?'),
          content: const Text(
            'Your gestational tracking and maternal insights will be paused. '
            'You will receive standard emergency EMS ambulance dispatch. You can switch back at any time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Confirm Switch'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    HapticFeedback.selectionClick();
    setState(() => _carePlan = newPlan);
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();

    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);

    try {
      final name = _nameController.text.trim();
      final phone = _phoneController.text.trim();
      final isMaternal = _carePlan == 'maternal';
      final cleanBlood = MemberProfile.sanitizeBloodGroup(_selectedBloodGroup);
      final finalAgeBand = _effectiveAgeBand;
      final eddText = _eddController.text.trim();
      final lmpText = _lmpController.text.trim();
      final dobText = _dobController.text.trim();
      final parityText = _gravidaParaController.text.trim();

      final cleanHosp = (_preferredHospital.contains('Auto-Select') || _preferredHospital.contains('None /'))
          ? null
          : _preferredHospital;

      // 1. Database table payload (strictly existing columns in public.profiles)
      final dbPayload = <String, dynamic>{
        'user_id': user.id,
        'role': _currentRole,
        'display_name': name.isNotEmpty ? name : 'Solace Member',
        'full_name': name.isNotEmpty ? name : null,
        'phone': phone.isNotEmpty ? phone : null,
        'profile_type': _carePlan,
        'is_pregnant': isMaternal,
        'gestational_weeks': isMaternal ? _computedWeeks : null,
        'gravida_para': isMaternal && parityText.isNotEmpty ? parityText : null,
        'edd': isMaternal && eddText.isNotEmpty ? eddText : null,
        'blood_group': cleanBlood.isNotEmpty ? cleanBlood : null,
        'genotype': _selectedGenotype,
        'age_band': finalAgeBand,
        'preferred_hospital': cleanHosp,
        'known_risks': isMaternal && _selectedRisks.isNotEmpty ? _selectedRisks : null,
        'allergies': _allergiesController.text.trim().isNotEmpty
            ? _allergiesController.text.trim()
            : null,
        'chronic_conditions': _conditionsController.text.trim().isNotEmpty
            ? _conditionsController.text.trim()
            : null,
        'next_of_kin_name': _kinNameController.text.trim().isNotEmpty
            ? _kinNameController.text.trim()
            : null,
        'next_of_kin_phone': _kinPhoneController.text.trim().isNotEmpty
            ? _kinPhoneController.text.trim()
            : null,
      };

      await _supabase.from('profiles').upsert(dbPayload, onConflict: 'user_id');

      // 2. Auth User Metadata (stores date_of_birth, lmp_date, care_plan)
      try {
        await _supabase.auth.updateUser(
          UserAttributes(
            data: {
              ...dbPayload,
              'care_plan': _carePlan,
              'subscription_tier': _carePlan,
              'date_of_birth': dobText.isNotEmpty ? dobText : null,
              'lmp_date': isMaternal && lmpText.isNotEmpty ? lmpText : null,
            },
          ),
        );
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Medical ID & Care Plan saved successfully!'),
          backgroundColor: Color(0xFF00E676),
          behavior: SnackBarBehavior.floating,
        ),
      );

      widget.onProfileUpdated?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ErrorSanitizer.sanitize(e, fallback: 'Failed to save Medical ID. Please try again.'),
          ),
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

  InputDecoration _inputDeco(String label, IconData icon, bool isDark, {String? hintText, Widget? suffixIcon}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: isDark ? AppTheme.darkCardBorder : const Color(0xFFCBD5E1),
      ),
    );
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      hintStyle: TextStyle(
        color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
        fontSize: 12,
      ),
      labelStyle: TextStyle(
        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
        fontSize: 13,
      ),
      prefixIcon: Icon(icon, size: 20, color: const Color(0xFF0284C7)),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: isDark ? const Color(0xFF0B192C) : const Color(0xFFF8FAFC),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final cardBorder = isDark ? AppTheme.darkCardBorder : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isMaternal = _carePlan == 'maternal';

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        title: const Text('Medical ID & Care Plan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ════════════════════════════════════════════════════════════════
              // BLOCK 1 — EMERGENCY MEDICAL ID (EVERYONE)
              // ════════════════════════════════════════════════════════════════
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.badge_rounded, color: Color(0xFF0284C7), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Emergency Medical ID',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Full Legal Name
                    TextFormField(
                      controller: _nameController,
                      decoration: _inputDeco('Full Name *', Icons.person_rounded, isDark),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required for dispatch' : null,
                    ),
                    const SizedBox(height: 12),

                    // Phone Number
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: _inputDeco('Callback Phone Number *', Icons.phone_rounded, isDark),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required for dispatch' : null,
                    ),
                    const SizedBox(height: 12),

                    // Date of Birth & Derived Age
                    TextFormField(
                      controller: _dobController,
                      readOnly: true,
                      onTap: () => _pickDate(
                        controller: _dobController,
                        title: 'Select Date of Birth',
                        initialDate: DateTime.now().subtract(const Duration(days: 365 * 25)),
                        firstDate: DateTime(1920),
                        lastDate: DateTime.now(),
                      ),
                      decoration: _inputDeco(
                        'Date of Birth',
                        Icons.cake_rounded,
                        isDark,
                        hintText: 'YYYY-MM-DD',
                        suffixIcon: _dobController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => setState(() => _dobController.clear()),
                              )
                            : const Icon(Icons.calendar_today_rounded, size: 18),
                      ),
                    ),
                    if (_derivedAge != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 4),
                        child: Text(
                          'Age: $_derivedAge years • Triage Band: $_effectiveAgeBand',
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF0284C7), fontWeight: FontWeight.w700),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _selectedAgeBand,
                        decoration: _inputDeco('Age Group (Triage Band)', Icons.groups_rounded, isDark),
                        items: _ageBands.map((band) {
                          return DropdownMenuItem(
                            value: band['value'],
                            child: Text(band['label']!, style: TextStyle(color: textColor, fontSize: 13)),
                          );
                        }).toList>,
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedAgeBand = val);
                        },
                      ),
                    ],
                    const SizedBox(height: 12),

                    // Blood Group (Plain labels only)
                    DropdownButtonFormField<String>(
                      value: _selectedBloodGroup,
                      decoration: _inputDeco('Blood Group (Optional)', Icons.bloodtype_rounded, isDark),
                      items: _bloodGroups.map((bg) {
                        return DropdownMenuItem(
                          value: bg,
                          child: Text(bg, style: TextStyle(color: textColor, fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedBloodGroup = val);
                      },
                    ),
                    const SizedBox(height: 12),

                    // Known Allergies
                    TextFormField(
                      controller: _allergiesController,
                      decoration: _inputDeco(
                        'Known Allergies (Optional)',
                        Icons.warning_amber_rounded,
                        isDark,
                        hintText: 'e.g. Penicillin, Sulfa, Aspirin',
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Chronic Conditions
                    TextFormField(
                      controller: _conditionsController,
                      decoration: _inputDeco(
                        'Chronic Conditions (Optional)',
                        Icons.health_and_safety_rounded,
                        isDark,
                        hintText: 'e.g. Asthma, Hypertension, Diabetes',
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Next of Kin
                    TextFormField(
                      controller: _kinNameController,
                      decoration: _inputDeco('Next of Kin Name (Optional)', Icons.contacts_rounded, isDark),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _kinPhoneController,
                      keyboardType: TextInputType.phone,
                      decoration: _inputDeco('Next of Kin Phone (Optional)', Icons.phone_callback_rounded, isDark),
                    ),
                    const SizedBox(height: 10),

                    // Collapsed "More details" (Genotype)
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                          'More details (Genotype)',
                          style: TextStyle(fontSize: 12, color: textSecondary, fontWeight: FontWeight.w600),
                        ),
                        children: [
                          DropdownButtonFormField<String>(
                            value: _selectedGenotype,
                            decoration: _inputDeco('Genotype (Optional)', Icons.biotech_rounded, isDark),
                            items: _genotypes.map((g) {
                              return DropdownMenuItem(
                                value: g,
                                child: Text(g, style: TextStyle(color: textColor, fontSize: 13)),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedGenotype = val);
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ════════════════════════════════════════════════════════════════
              // BLOCK 2 — CARE PLAN (STANDARD | MATERNAL)
              // ════════════════════════════════════════════════════════════════
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.medical_services_rounded, color: Color(0xFF0284C7), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Care Plan',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Care Plan Toggle Cards
                    Row(
                      children: [
                        // Standard Card
                        Expanded(
                          child: InkWell(
                            onTap: () => _handlePlanToggle('standard'),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: !isMaternal
                                    ? const Color(0xFF0284C7).withValues(alpha: 0.12)
                                    : (isDark ? const Color(0xFF0B192C) : const Color(0xFFF8FAFC)),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: !isMaternal ? const Color(0xFF0284C7) : cardBorder,
                                  width: !isMaternal ? 2.0 : 1.0,
                                ),
                              ),
                              child: Column(
                                children: [
                                  const Text('🛡️', style: TextStyle(fontSize: 22)),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Standard',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: !isMaternal ? const Color(0xFF0284C7) : textColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Ambulance & Triage',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 10, color: textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Maternal Card
                        Expanded(
                          child: InkWell(
                            onTap: () => _handlePlanToggle('maternal'),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isMaternal
                                    ? const Color(0xFFEC4899).withValues(alpha: 0.12)
                                    : (isDark ? const Color(0xFF0B192C) : const Color(0xFFF8FAFC)),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isMaternal ? const Color(0xFFEC4899) : cardBorder,
                                  width: isMaternal ? 2.0 : 1.0,
                                ),
                              ),
                              child: Column(
                                children: [
                                  const Text('🌸', style: TextStyle(fontSize: 22)),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Maternal',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: isMaternal ? const Color(0xFFEC4899) : textColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Obstetric & Insights',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 10, color: textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Active Care Plan Badge
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isMaternal
                            ? const Color(0xFFEC4899).withValues(alpha: 0.08)
                            : const Color(0xFF0284C7).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isMaternal
                              ? const Color(0xFFEC4899).withValues(alpha: 0.3)
                              : const Color(0xFF0284C7).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isMaternal ? Icons.pregnant_woman_rounded : Icons.shield_rounded,
                            color: isMaternal ? const Color(0xFFEC4899) : const Color(0xFF0284C7),
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isMaternal ? 'Maternal & Obstetric Care Plan' : 'Standard Emergency Plan',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: isMaternal ? const Color(0xFFEC4899) : const Color(0xFF0284C7),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isMaternal
                                      ? 'Obstetric triage, gestational guidance & en-route hospital alert.'
                                      : 'Emergency ambulance dispatch & rapid hospital triage for medical emergencies.',
                                  style: TextStyle(fontSize: 11, color: textSecondary, height: 1.3),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── MATERNAL DETAILS (WHEN CARE PLAN = MATERNAL) ─────────
                    if (isMaternal) ...[
                      // READ-ONLY COMPUTED GESTATIONAL AGE & TRIMESTER
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEC4899).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFEC4899).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Current Gestational Age (Computed):',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFBE185D)),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Week $_computedWeeks, Day $_computedDays',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: textColor),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEC4899),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _trimesterLabel,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // EDD Date Picker
                      TextFormField(
                        controller: _eddController,
                        readOnly: true,
                        onTap: () => _pickDate(
                          controller: _eddController,
                          title: 'Select Estimated Due Date (EDD)',
                          initialDate: DateTime.now().add(const Duration(days: 60)),
                          firstDate: DateTime.now().subtract(const Duration(days: 14)),
                          lastDate: DateTime.now().add(const Duration(days: 294)),
                          onSelected: () {
                            if (_eddController.text.isNotEmpty) {
                              final edd = DateTime.tryParse(_eddController.text);
                              if (edd != null) {
                                final lmp = edd.subtract(const Duration(days: 280));
                                _lmpController.text = "${lmp.year.toString().padLeft(4, '0')}-"
                                    "${lmp.month.toString().padLeft(2, '0')}-"
                                    "${lmp.day.toString().padLeft(2, '0')}";
                              }
                            }
                          },
                        ),
                        decoration: _inputDeco(
                          'Estimated Due Date (EDD)',
                          Icons.event_rounded,
                          isDark,
                          hintText: 'Tap to pick due date',
                          suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // LMP Date Picker
                      TextFormField(
                        controller: _lmpController,
                        readOnly: true,
                        onTap: () => _pickDate(
                          controller: _lmpController,
                          title: 'Select Last Menstrual Period (LMP)',
                          initialDate: DateTime.now().subtract(const Duration(days: 120)),
                          firstDate: DateTime.now().subtract(const Duration(days: 300)),
                          lastDate: DateTime.now(),
                          onSelected: () {
                            if (_lmpController.text.isNotEmpty) {
                              final lmp = DateTime.tryParse(_lmpController.text);
                              if (lmp != null) {
                                final edd = lmp.add(const Duration(days: 280));
                                _eddController.text = "${edd.year.toString().padLeft(4, '0')}-"
                                    "${edd.month.toString().padLeft(2, '0')}-"
                                    "${edd.day.toString().padLeft(2, '0')}";
                              }
                            }
                          },
                        ),
                        decoration: _inputDeco(
                          'Last Menstrual Period (LMP)',
                          Icons.date_range_rounded,
                          isDark,
                          hintText: 'Tap to pick LMP date',
                          suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Parity
                      TextFormField(
                        controller: _gravidaParaController,
                        decoration: _inputDeco(
                          'Parity / Gravida (Optional e.g. G2P1)',
                          Icons.pregnant_woman_rounded,
                          isDark,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Maternal Risk Chips
                      Text(
                        'Maternal Factors (User-declared for triage awareness):',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textColor),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _maternalRiskOptions.map((risk) {
                          final selected = _selectedRisks.contains(risk);
                          return FilterChip(
                            label: Text(
                              risk,
                              style: TextStyle(fontSize: 11, color: selected ? Colors.white : textColor),
                            ),
                            selected: selected,
                            selectedColor: const Color(0xFFEC4899),
                            checkmarkColor: Colors.white,
                            onSelected: (val) {
                              setState(() {
                                if (val) {
                                  _selectedRisks.add(risk);
                                } else {
                                  _selectedRisks.remove(risk);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Preferred Hospital (Preference Only)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String>(
                          value: _preferredHospital,
                          decoration: _inputDeco('Preferred Hospital (Preference only)', Icons.local_hospital_rounded, isDark),
                          isExpanded: true,
                          items: _hospitals.map((h) {
                            return DropdownMenuItem(
                              value: h,
                              child: Text(h, overflow: TextOverflow.ellipsis, style: TextStyle(color: textColor, fontSize: 12)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _preferredHospital = val);
                          },
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            'Preference only — hospital admission and bed assignment are coordinated by emergency dispatch.',
                            style: TextStyle(fontSize: 10.5, color: textSecondary, height: 1.25),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ════════════════════════════════════════════════════════════════
              // SAVE BUTTON
              // ════════════════════════════════════════════════════════════════
              FilledButton(
                onPressed: _isSaving ? null : _saveProfile,
                style: FilledButton.styleFrom(
                  backgroundColor: isMaternal ? const Color(0xFFEC4899) : const Color(0xFF0284C7),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'Save Medical ID & Care Plan',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                      ),
              ),
              const SizedBox(height: 20),

              // ════════════════════════════════════════════════════════════════
              // MANDATORY FOOTER DISCLAIMER
              // ════════════════════════════════════════════════════════════════
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cardBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF64748B)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You provide this for emergencies. It is not a hospital medical record. Hospital assignment is coordinated by dispatch.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
