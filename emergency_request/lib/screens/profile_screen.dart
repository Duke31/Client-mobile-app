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

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _conditionsController = TextEditingController();
  final _kinNameController = TextEditingController();
  final _kinPhoneController = TextEditingController();

  // Maternal specific controllers
  final _gravidaParaController = TextEditingController();
  final _eddController = TextEditingController();

  String _profileType = 'standard'; // 'maternal' | 'standard'
  int _gestationalWeeks = 32;
  String _selectedBloodGroup = 'Unknown';
  String _selectedGenotype = 'AA';
  String _selectedAgeBand = '18-39';
  String _preferredHospital = 'LifeCare Private Clinic (Ring Road, Ibadan)';
  final List<String> _selectedRisks = [];

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
    'O- (Rare Blood Shield)',
  ];

  static const List<String> _genotypes = ['AA', 'AS', 'SS', 'AC', 'SC'];

  static const List<String> _ageBands = [
    '0-1',
    '2-12',
    '13-17',
    '18-39',
    '40-64',
    '65+',
  ];

  static const List<String> _hospitals = [
    'LifeCare Private Clinic (Ring Road, Ibadan)',
    'Bodija Premier Medical Center (Ibadan)',
    'University College Hospital - UCH Private Wing (Ibadan)',
    'Asubiaro State Hospital (Osogbo, Osun State)',
    'UNIOSUN Teaching Hospital (Osun State)',
    'Lagos University Teaching Hospital - LUTH (Lagos)',
    'First Cardiology / Lekki Medical Center (Lagos)',
  ];

  static const List<String> _maternalRiskOptions = [
    'Previous C-Section',
    'Gestational Hypertension',
    'Gestational Diabetes',
    'Multiple Gestation (Twins)',
    'History of Pre-Eclampsia',
    'Previous Preterm Birth',
    'Anemia in Pregnancy',
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
    _gravidaParaController.dispose();
    _eddController.dispose();
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
              '';
          _phoneController.text = res['phone']?.toString() ?? '';
          _allergiesController.text = res['allergies']?.toString() ?? '';
          _conditionsController.text = res['chronic_conditions']?.toString() ?? '';
          _kinNameController.text = res['next_of_kin_name']?.toString() ?? '';
          _kinPhoneController.text = res['next_of_kin_phone']?.toString() ?? '';

          _profileType = (res['profile_type']?.toString() ??
              (res['is_pregnant'] == true ? 'maternal' : 'standard')).toLowerCase();

          if (res['gestational_weeks'] != null) {
            _gestationalWeeks = (res['gestational_weeks'] as num).toInt();
          }
          _gravidaParaController.text = res['gravida_para']?.toString() ?? '';
          _eddController.text = res['edd']?.toString() ?? '';

          final bg = res['blood_group']?.toString();
          if (bg != null) {
            if (bg.contains('O-')) {
              _selectedBloodGroup = 'O- (Rare Blood Shield)';
            } else if (_bloodGroups.contains(bg)) {
              _selectedBloodGroup = bg;
            }
          }

          final geno = res['genotype']?.toString();
          if (geno != null && _genotypes.contains(geno)) {
            _selectedGenotype = geno;
          }

          final ab = res['age_band']?.toString();
          if (ab != null && _ageBands.contains(ab)) {
            _selectedAgeBand = ab;
          }

          final hosp = res['preferred_hospital']?.toString();
          if (hosp != null && _hospitals.contains(hosp)) {
            _preferredHospital = hosp;
          }

          if (res['known_risks'] is List) {
            _selectedRisks.clear();
            _selectedRisks.addAll(List<String>.from(res['known_risks']));
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
      final isMaternal = _profileType == 'maternal';

      final payload = <String, dynamic>{
        'user_id': userId,
        'role': _currentRole,
        'display_name': name.isNotEmpty ? name : 'Solace Member',
        'full_name': name.isNotEmpty ? name : null,
        'phone': phone.isNotEmpty ? phone : null,
        'profile_type': _profileType,
        'is_pregnant': isMaternal,
        'gestational_weeks': isMaternal ? _gestationalWeeks : null,
        'gravida_para': isMaternal && _gravidaParaController.text.trim().isNotEmpty
            ? _gravidaParaController.text.trim()
            : null,
        'edd': isMaternal && _eddController.text.trim().isNotEmpty
            ? _eddController.text.trim()
            : null,
        'blood_group': _selectedBloodGroup != 'Unknown' ? _selectedBloodGroup : null,
        'genotype': _selectedGenotype,
        'age_band': _selectedAgeBand,
        'preferred_hospital': _preferredHospital,
        'known_risks': isMaternal ? _selectedRisks : null,
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

      await _supabase.from('profiles').upsert(payload, onConflict: 'user_id');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Medical ID & Hospital Shield saved successfully!'),
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

  InputDecoration _inputDeco(String label, IconData icon, bool isDark) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: isDark ? AppTheme.darkCardBorder : const Color(0xFFCBD5E1),
      ),
    );
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: const Color(0xFF0284C7)),
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

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isMaternal = _profileType == 'maternal';

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        title: const Text('Medical ID & Hospital Shield', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
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
              // ── Care Plan Selector ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Emergency Care Plan',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _profileType = 'maternal');
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                              decoration: BoxDecoration(
                                color: isMaternal
                                    ? const Color(0xFFEC4899).withValues(alpha: 0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isMaternal ? const Color(0xFFEC4899) : cardBorder,
                                  width: isMaternal ? 1.8 : 1.0,
                                ),
                              ),
                              child: Column(
                                children: [
                                  const Text('🌸', style: TextStyle(fontSize: 22)),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Maternal Plan',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                      color: isMaternal ? const Color(0xFFEC4899) : textColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Obstetric & L&D Hub',
                                    style: TextStyle(fontSize: 10, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _profileType = 'standard');
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                              decoration: BoxDecoration(
                                color: !isMaternal
                                    ? const Color(0xFF0284C7).withValues(alpha: 0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: !isMaternal ? const Color(0xFF0284C7) : cardBorder,
                                  width: !isMaternal ? 1.8 : 1.0,
                                ),
                              ),
                              child: Column(
                                children: [
                                  const Text('🛡️', style: TextStyle(fontSize: 22)),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Standard Shield',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                      color: !isMaternal ? const Color(0xFF0284C7) : textColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Trauma & Cardiac Bay',
                                    style: TextStyle(fontSize: 10, color: Colors.grey),
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
              const SizedBox(height: 16),

              // ── Personal Info ───────────────────────────────────────────
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
                    Text(
                      'Personal Information',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textColor),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameController,
                      decoration: _inputDeco('Full Name', Icons.person_rounded, isDark),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: _inputDeco('Phone Number', Icons.phone_rounded, isDark),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Maternal Specific Fields ────────────────────────────────
              if (isMaternal) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2E1045) : const Color(0xFFFDF2F8),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDark ? const Color(0xFF6B21A8) : const Color(0xFFFBCFE8),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Text('🌸 ', style: TextStyle(fontSize: 16)),
                          Text(
                            'Obstetric & Gestational Profile',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFBE185D),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Gestational Age: $_gestationalWeeks Weeks',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: textColor,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEC4899).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _gestationalWeeks >= 28 ? '3rd Trimester' : (_gestationalWeeks >= 13 ? '2nd Trimester' : '1st Trimester'),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFEC4899)),
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _gestationalWeeks.toDouble(),
                        min: 4,
                        max: 42,
                        divisions: 38,
                        activeColor: const Color(0xFFEC4899),
                        onChanged: (val) {
                          setState(() => _gestationalWeeks = val.round());
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _gravidaParaController,
                        decoration: _inputDeco('Parity (e.g. G2P1)', Icons.pregnant_woman, isDark),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _eddController,
                        decoration: _inputDeco('Estimated Due Date (e.g. 15 Nov 2026)', Icons.calendar_today, isDark),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Known Maternal Risks (Check all that apply):',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textColor),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _maternalRiskOptions.map((risk) {
                          final selected = _selectedRisks.contains(risk);
                          return FilterChip(
                            label: Text(risk, style: TextStyle(fontSize: 11, color: selected ? Colors.white : textColor)),
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
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Medical Baseline: Blood & Genotype ──────────────────────
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
                    Text(
                      'Clinical Baseline & Blood Shield',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textColor),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedBloodGroup,
                      decoration: _inputDeco('Blood Group', Icons.bloodtype_rounded, isDark),
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
                    DropdownButtonFormField<String>(
                      value: _selectedGenotype,
                      decoration: _inputDeco('Genotype', Icons.biotech_rounded, isDark),
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
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _preferredHospital,
                      decoration: _inputDeco('Preferred Hospital Intake Center', Icons.local_hospital_rounded, isDark),
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
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Allergies & Chronic Conditions ──────────────────────────
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
                    Text(
                      'Allergies & Medical History',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textColor),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _allergiesController,
                      decoration: _inputDeco('Known Allergies (e.g. Penicillin, NSAIDs)', Icons.warning_amber_rounded, isDark),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _conditionsController,
                      decoration: _inputDeco('Chronic Conditions (e.g. Asthma, Hypertension)', Icons.health_and_safety_rounded, isDark),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Next of Kin Emergency Contact ───────────────────────────
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
                    Text(
                      'Primary Emergency Contact',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textColor),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _kinNameController,
                      decoration: _inputDeco('Next of Kin / Relative Name', Icons.contacts_rounded, isDark),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _kinPhoneController,
                      keyboardType: TextInputType.phone,
                      decoration: _inputDeco('Contact Phone Number', Icons.phone_callback_rounded, isDark),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Save Button ─────────────────────────────────────────────
              FilledButton(
                onPressed: _isSaving ? null : _saveProfile,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
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
                        'Save Medical ID & Hospital Shield',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
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
