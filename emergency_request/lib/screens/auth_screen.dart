import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../models/member_profile.dart';
import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();
  final _allergiesController = TextEditingController();

  // Maternal controllers
  final _eddController = TextEditingController();
  final _lmpController = TextEditingController();
  final _parityController = TextEditingController();
  bool _hasPreviousCSection = false;

  bool _isSignUp = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  // Care Plan Onboarding State
  String _selectedPlan = 'standard'; // 'standard' (default) | 'maternal'
  String _selectedAgeBand = '18-39';
  String _selectedBloodGroup = 'Unknown';

  static const List<String> _bloodGroups = MemberProfile.validBloodGroups;
  static const List<Map<String, String>> _ageBands = MemberProfile.ageBandOptions;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _allergiesController.dispose();
    _eddController.dispose();
    _lmpController.dispose();
    _parityController.dispose();
    super.dispose();
  }

  /// Derive computed gestational age and trimester from EDD or LMP
  int? get _computedGestationalWeeks {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (_lmpController.text.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(_lmpController.text.trim());
      if (parsed != null) {
        final lmpDay = DateTime(parsed.year, parsed.month, parsed.day);
        final elapsed = today.difference(lmpDay).inDays;
        return (elapsed ~/ 7).clamp(1, 42);
      }
    }

    if (_eddController.text.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(_eddController.text.trim());
      if (parsed != null) {
        final eddDay = DateTime(parsed.year, parsed.month, parsed.day);
        final daysUntilDue = eddDay.difference(today).inDays;
        final elapsed = 280 - daysUntilDue;
        return (elapsed ~/ 7).clamp(1, 42);
      }
    }

    return null;
  }

  String _getTrimesterLabel(int weeks) {
    if (weeks <= 13) return '1st Trimester';
    if (weeks <= 27) return '2nd Trimester';
    return '3rd Trimester';
  }

  /// Derive age in years from DOB
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final isMaternal = _selectedPlan == 'maternal';

    final cleanBlood = MemberProfile.sanitizeBloodGroup(_selectedBloodGroup);
    final allergiesText = _allergiesController.text.trim();
    final eddText = _eddController.text.trim();
    final lmpText = _lmpController.text.trim();
    final parityText = _parityController.text.trim();
    final dobText = _dobController.text.trim();
    final finalAgeBand = _effectiveAgeBand;

    final maternalRisks = <String>[];
    if (isMaternal && _hasPreviousCSection) {
      maternalRisks.add('Previous C-Section');
    }

    try {
      if (_isSignUp) {
        final res = await _supabase.auth.signUp(
          email: email,
          password: password,
          data: {
            'full_name': name,
            'name': name,
            'phone': phone,
            'care_plan': _selectedPlan,
            'profile_type': _selectedPlan,
            'subscription_tier': _selectedPlan,
            'is_pregnant': isMaternal,
            'date_of_birth': dobText.isNotEmpty ? dobText : null,
            'age_band': finalAgeBand,
            'blood_group': cleanBlood.isNotEmpty ? cleanBlood : null,
            'allergies': allergiesText.isNotEmpty ? allergiesText : null,
            'gestational_weeks': isMaternal ? _computedGestationalWeeks : null,
            'edd': isMaternal && eddText.isNotEmpty ? eddText : null,
            'lmp_date': isMaternal && lmpText.isNotEmpty ? lmpText : null,
            'gravida_para': isMaternal && parityText.isNotEmpty ? parityText : null,
            'known_risks': isMaternal && maternalRisks.isNotEmpty ? maternalRisks : null,
          },
        );

        final user = res.user;
        if (user != null) {
          try {
            await _supabase.from('profiles').upsert({
              'user_id': user.id,
              'display_name': name.isNotEmpty ? name : 'Solace Member',
              'full_name': name.isNotEmpty ? name : 'Solace Member',
              'phone': phone.isNotEmpty ? phone : null,
              'role': 'client',
              'profile_type': _selectedPlan,
              'is_pregnant': isMaternal,
              'gestational_weeks': isMaternal ? _computedGestationalWeeks : null,
              'edd': isMaternal && eddText.isNotEmpty ? eddText : null,
              'gravida_para': isMaternal && parityText.isNotEmpty ? parityText : null,
              'blood_group': cleanBlood.isNotEmpty ? cleanBlood : null,
              'age_band': finalAgeBand,
              'allergies': allergiesText.isNotEmpty ? allergiesText : null,
              'known_risks': isMaternal && maternalRisks.isNotEmpty ? maternalRisks : null,
            }, onConflict: 'user_id');
          } catch (_) {}
        }

        if (res.session == null) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _errorMessage =
                'Account created! Please check your email inbox to confirm, then sign in.';
            _isSignUp = false;
          });
          return;
        }
      } else {
        await _supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Authentication notice: $e';
      });
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData prefixIcon,
    required bool isDark,
    Widget? suffixIcon,
    String? hintText,
  }) {
    final borderCol = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
    final focusCol = isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7);
    final fillCol = isDark ? const Color(0xFF0B192C) : const Color(0xFFF8FAFC);

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
      filled: true,
      fillColor: fillCol,
      prefixIcon: Icon(prefixIcon, color: focusCol, size: 20),
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderCol, width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: focusCol, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.0),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final cardBorder = isDark ? AppTheme.darkCardBorder : const Color(0xFFCBD5E1);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final primaryColor = isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7);

    final weeks = _computedGestationalWeeks;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // -- LOGO & HEADLINE ------------------------------------------
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0284C7), Color(0xFF00D4FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00D4FF).withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.local_hospital_rounded, color: Colors.white, size: 36),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'SOLACE EMS',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Emergency Medical Network  \u2022  Fast Dispatch Coordination',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // -- ERROR BANNER ---------------------------------------------
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 12, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],

                  // -- MAIN FORM CARD -------------------------------------------
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: cardBorder),
                      boxShadow: isDark
                          ? []
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Tab switcher: Sign In vs Sign Up
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _isSignUp = false);
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      color: !_isSignUp
                                          ? (isDark ? const Color(0xFF1E293B) : Colors.white)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: !_isSignUp && !isDark
                                          ? [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.06),
                                                blurRadius: 4,
                                                offset: const Offset(0, 2),
                                              ),
                                            ]
                                          : [],
                                    ),
                                    child: Center(
                                      child: Text(
                                        'SIGN IN',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: !_isSignUp ? primaryColor : textSecondary,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _isSignUp = true);
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      color: _isSignUp
                                          ? (isDark ? const Color(0xFF1E293B) : Colors.white)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: _isSignUp && !isDark
                                          ? [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.06),
                                                blurRadius: 4,
                                                offset: const Offset(0, 2),
                                              ),
                                            ]
                                          : [],
                                    ),
                                    child: Center(
                                      child: Text(
                                        'CREATE ACCOUNT',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: _isSignUp ? primaryColor : textSecondary,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // SIGN UP ONLY FIELDS (Minimum essentials)
                        if (_isSignUp) ...[
                          // Full Name
                          TextFormField(
                            controller: _nameController,
                            style: TextStyle(color: textPrimary, fontSize: 14),
                            decoration: _inputDecoration(
                              label: 'Full Legal Name *',
                              prefixIcon: Icons.person_outline_rounded,
                              isDark: isDark,
                            ),
                            validator: (val) {
                              if (_isSignUp && (val == null || val.trim().isEmpty)) {
                                return 'Please enter your full legal name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // Phone
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            style: TextStyle(color: textPrimary, fontSize: 14),
                            decoration: _inputDecoration(
                              label: 'Emergency Contact Phone (+234...) *',
                              prefixIcon: Icons.phone_outlined,
                              isDark: isDark,
                            ),
                            validator: (val) {
                              if (_isSignUp && (val == null || val.trim().isEmpty)) {
                                return 'Please enter your phone number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 18),

                          // -- CARE PLAN SELECTOR (Standard vs Maternal) ---------
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'SELECT CARE PLAN',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: primaryColor,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text('  \u2022  Required', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Plan A: Standard Emergency Care Plan (Default)
                              InkWell(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _selectedPlan = 'standard');
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: _selectedPlan == 'standard'
                                        ? primaryColor.withValues(alpha: 0.12)
                                        : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: _selectedPlan == 'standard' ? primaryColor : cardBorder,
                                      width: _selectedPlan == 'standard' ? 2.0 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: primaryColor.withValues(alpha: 0.2),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(Icons.shield_rounded, size: 20, color: primaryColor),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Wrap(
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              spacing: 6,
                                              runSpacing: 2,
                                              children: [
                                                const Text(
                                                  'Standard Emergency Care',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                  decoration: BoxDecoration(
                                                    color: primaryColor.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    'DEFAULT',
                                                    style: TextStyle(
                                                      fontSize: 8.5,
                                                      fontWeight: FontWeight.w900,
                                                      color: primaryColor,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Text(
                                              'Emergency ambulance dispatch & rapid hospital triage for medical emergencies.',
                                              style: TextStyle(color: textSecondary, fontSize: 10.5, height: 1.3),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        _selectedPlan == 'standard'
                                            ? Icons.check_circle_rounded
                                            : Icons.radio_button_off_rounded,
                                        color: _selectedPlan == 'standard' ? primaryColor : textSecondary,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Plan B: Maternal & Obstetric Plan
                              InkWell(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _selectedPlan = 'maternal');
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: _selectedPlan == 'maternal'
                                        ? const Color(0xFFEC4899).withValues(alpha: 0.12)
                                        : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: _selectedPlan == 'maternal'
                                          ? const Color(0xFFEC4899)
                                          : cardBorder,
                                      width: _selectedPlan == 'maternal' ? 2.0 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEC4899).withValues(alpha: 0.2),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.pregnant_woman_rounded, size: 20, color: Color(0xFFEC4899)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Wrap(
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              spacing: 6,
                                              runSpacing: 2,
                                              children: [
                                                const Text(
                                                  'Maternal & Obstetric Care',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFEC4899).withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: const Text(
                                                    'MATERNAL',
                                                    style: TextStyle(
                                                      fontSize: 8.5,
                                                      fontWeight: FontWeight.w900,
                                                      color: Color(0xFFEC4899),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Text(
                                              'Obstetric triage, gestational guidance & en-route hospital alert.',
                                              style: TextStyle(color: textSecondary, fontSize: 10.5, height: 1.3),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        _selectedPlan == 'maternal'
                                            ? Icons.check_circle_rounded
                                            : Icons.radio_button_off_rounded,
                                        color: _selectedPlan == 'maternal'
                                            ? const Color(0xFFEC4899)
                                            : textSecondary,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // -- CLIENT AGE / DOB SECTION -------------------------
                          TextFormField(
                            controller: _dobController,
                            readOnly: true,
                            style: TextStyle(color: textPrimary, fontSize: 13),
                            onTap: () => _pickDate(
                              controller: _dobController,
                              title: 'Select Date of Birth',
                              initialDate: DateTime.now().subtract(const Duration(days: 365 * 25)),
                              firstDate: DateTime(1920),
                              lastDate: DateTime.now(),
                            ),
                            decoration: _inputDecoration(
                              label: 'Date of Birth (Optional for Age Band)',
                              prefixIcon: Icons.cake_outlined,
                              hintText: 'YYYY-MM-DD',
                              isDark: isDark,
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
                                'Age: $_derivedAge years ? Derived Band: $_effectiveAgeBand',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF0284C7), fontWeight: FontWeight.w600),
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 10),
                            // Fallback age band selector if DOB not provided
                            DropdownButtonFormField<String>(
                              value: _selectedAgeBand,
                              dropdownColor: cardBg,
                              style: TextStyle(color: textPrimary, fontSize: 13),
                              decoration: _inputDecoration(
                                label: 'Age Group (For Triage)',
                                prefixIcon: Icons.groups_outlined,
                                isDark: isDark,
                              ),
                              items: _ageBands.map((band) {
                                return DropdownMenuItem(
                                  value: band['value'],
                                  child: Text(band['label']!, style: TextStyle(color: textPrimary, fontSize: 12)),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedAgeBand = val);
                              },
                            ),
                          ],
                          const SizedBox(height: 14),

                          // -- OPTIONAL MEDICAL BASICS --------------------------
                          DropdownButtonFormField<String>(
                            value: _selectedBloodGroup,
                            dropdownColor: cardBg,
                            style: TextStyle(color: textPrimary, fontSize: 13),
                            decoration: _inputDecoration(
                              label: 'Blood Group (Optional)',
                              prefixIcon: Icons.bloodtype_outlined,
                              isDark: isDark,
                            ),
                            items: _bloodGroups.map((bg) {
                              return DropdownMenuItem(
                                value: bg,
                                child: Text(bg, style: TextStyle(color: textPrimary, fontSize: 13)),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedBloodGroup = val);
                            },
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _allergiesController,
                            style: TextStyle(color: textPrimary, fontSize: 13),
                            decoration: _inputDecoration(
                              label: 'Known Allergies (Optional)',
                              prefixIcon: Icons.warning_amber_rounded,
                              hintText: 'e.g. Penicillin, NSAIDs',
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // -- MATERNAL-SPECIFIC ONBOARDING FIELDS --------------
                          if (_selectedPlan == 'maternal') ...[
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFDF2F8),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFEC4899).withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.pregnant_woman_rounded, size: 18, color: Color(0xFFEC4899)),
                                       const SizedBox(width: 6),
                                      const Text(
                                        'Maternal Care Setup',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFEC4899),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),

                                  // Estimated Due Date (EDD) Picker
                                  TextFormField(
                                    controller: _eddController,
                                    readOnly: true,
                                    style: TextStyle(color: textPrimary, fontSize: 13),
                                    onTap: () => _pickDate(
                                      controller: _eddController,
                                      title: 'Select Estimated Due Date (EDD)',
                                      initialDate: DateTime.now().add(const Duration(days: 60)),
                                      firstDate: DateTime.now().subtract(const Duration(days: 14)),
                                      lastDate: DateTime.now().add(const Duration(days: 294)),
                                      onSelected: () {
                                        // Auto-derive LMP if empty
                                        if (_lmpController.text.isEmpty && _eddController.text.isNotEmpty) {
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
                                    decoration: _inputDecoration(
                                      label: 'Estimated Due Date (EDD) *',
                                      prefixIcon: Icons.event_rounded,
                                      hintText: 'Tap to pick due date',
                                      isDark: isDark,
                                    ),
                                    validator: (val) {
                                      if (_isSignUp && _selectedPlan == 'maternal' && (val == null || val.trim().isEmpty) && _lmpController.text.trim().isEmpty) {
                                        return 'Please provide EDD or LMP date';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 10),

                                  // Read-only computed gestational age badge
                                  if (weeks != null) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEC4899).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.info_outline, size: 16, color: Color(0xFFEC4899)),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Computed: Week $weeks  \u2022  ${_getTrimesterLabel(weeks)}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFFEC4899),
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12,
                                            ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                  ],

                                  // Parity (Optional)
                                  TextFormField(
                                    controller: _parityController,
                                    style: TextStyle(color: textPrimary, fontSize: 13),
                                    decoration: _inputDecoration(
                                      label: 'Parity / Gravida (Optional e.g. G2P1)',
                                      prefixIcon: Icons.pregnant_woman_rounded,
                                      isDark: isDark,
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  // Previous C-Section Chip
                                  FilterChip(
                                    label: const Text('Previous C-Section', style: TextStyle(fontSize: 12)),
                                    selected: _hasPreviousCSection,
                                    selectedColor: const Color(0xFFEC4899),
                                    checkmarkColor: Colors.white,
                                    labelStyle: TextStyle(
                                      color: _hasPreviousCSection ? Colors.white : textPrimary,
                                      fontWeight: _hasPreviousCSection ? FontWeight.w700 : FontWeight.normal,
                                    ),
                                    onSelected: (val) => setState(() => _hasPreviousCSection = val),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                        ],

                        // COMMON FIELDS (Email & Password)
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: TextStyle(color: textPrimary, fontSize: 14),
                          decoration: _inputDecoration(
                            label: 'Email Address',
                            prefixIcon: Icons.email_outlined,
                            isDark: isDark,
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty || !val.contains('@')) {
                              return 'Please enter a valid email address';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: TextStyle(color: textPrimary, fontSize: 14),
                          decoration: _inputDecoration(
                            label: 'Password (min 6 characters)',
                            prefixIcon: Icons.lock_outline_rounded,
                            isDark: isDark,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                color: textSecondary,
                                size: 20,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),

                        // SUBMIT BUTTON
                        SizedBox(
                          height: 52,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _isSignUp && _selectedPlan == 'maternal'
                                  ? const Color(0xFFEC4899)
                                  : primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 2,
                            ),
                            onPressed: _isLoading ? null : _submit,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                  )
                                : Text(
                                    _isSignUp
                                        ? (_selectedPlan == 'maternal'
                                            ? 'ACTIVATE MATERNAL CARE PLAN'
                                            : 'ACTIVATE EMERGENCY ACCESS')
                                        : 'SIGN IN TO SOLACE EMS',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // FOOTER
                  Text(
                    'Solace EMS ? 24/7 Rapid Ambulance & Hospital Intake Network',
                    style: TextStyle(fontSize: 11, color: textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
