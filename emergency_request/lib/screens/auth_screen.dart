import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
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
  final _eddController = TextEditingController();

  bool _isSignUp = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  // Care Plan Onboarding State
  String _selectedPlan = 'standard'; // 'standard' (default) | 'maternal'
  int _gestationalWeeks = 32;
  String _selectedBloodGroup = 'O- (Rare Blood Shield)';
  String _selectedGenotype = 'AA';
  String _preferredHospital = 'LifeCare Private Clinic (Ring Road, Ibadan)';

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

  static const List<String> _hospitals = [
    'LifeCare Private Clinic (Ring Road, Ibadan)',
    'Bodija Premier Medical Center (Ibadan)',
    'University College Hospital - UCH Private Wing (Ibadan)',
    'Asubiaro State Hospital (Osogbo, Osun State)',
    'UNIOSUN Teaching Hospital (Osun State)',
    'Lagos University Teaching Hospital - LUTH (Lagos)',
    'First Cardiology / Lekki Medical Center (Lagos)',
  ];

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _eddController.dispose();
    super.dispose();
  }

  String _getTrimesterLabel(int weeks) {
    if (weeks < 13) return '1st Trimester';
    if (weeks < 28) return '2nd Trimester';
    return '3rd Trimester';
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

    try {
      if (_isSignUp) {
        final res = await _supabase.auth.signUp(
          email: email,
          password: password,
          data: {
            'full_name': name,
            'name': name,
            'phone': phone,
            'profile_type': _selectedPlan,
            'is_pregnant': isMaternal,
            'gestational_weeks': isMaternal ? _gestationalWeeks : null,
            'edd': isMaternal && _eddController.text.trim().isNotEmpty
                ? _eddController.text.trim()
                : null,
            'blood_group': _selectedBloodGroup != 'Unknown' ? _selectedBloodGroup : null,
            'genotype': _selectedGenotype,
            'preferred_hospital': _preferredHospital,
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
              'gestational_weeks': isMaternal ? _gestationalWeeks : null,
              'edd': isMaternal && _eddController.text.trim().isNotEmpty
                  ? _eddController.text.trim()
                  : null,
              'blood_group': _selectedBloodGroup != 'Unknown' ? _selectedBloodGroup : null,
              'genotype': _selectedGenotype,
              'preferred_hospital': _preferredHospital,
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
  }) {
    final borderCol = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
    final focusCol = isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7);
    final fillCol = isDark ? const Color(0xFF0B192C) : const Color(0xFFF8FAFC);

    return InputDecoration(
      labelText: label,
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
                  // ── LOGO & HEADLINE ──────────────────────────────────────────
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
                    'Emergency Medical Network • Direct-to-Bed Guarantee',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── ERROR BANNER ─────────────────────────────────────────────
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

                  // ── MAIN FORM CARD ───────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(22),
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

                        // SIGN UP ONLY FIELDS
                        if (_isSignUp) ...[
                          // Full Name
                          TextFormField(
                            controller: _nameController,
                            style: TextStyle(color: textPrimary, fontSize: 14),
                            decoration: _inputDecoration(
                              label: 'Full Legal Name',
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
                              label: 'Emergency Contact Phone (+234...)',
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

                          // ── CARE PLAN SELECTOR (Maternal vs Standard) ─────────
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
                                  const Text('• Required', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Plan A: Standard Emergency Shield (Default)
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
                                      color: _selectedPlan == 'standard'
                                          ? primaryColor
                                          : cardBorder,
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
                                        child: const Text('🛡️', style: TextStyle(fontSize: 20)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                const Text(
                                                  'Standard Emergency Shield',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
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
                                              'VIP direct-to-bed intake for acute trauma, cardiac, pediatric & acute cases.',
                                              style: TextStyle(color: textSecondary, fontSize: 10.5, height: 1.3),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        _selectedPlan == 'standard'
                                            ? Icons.check_circle_rounded
                                            : Icons.radio_button_off_rounded,
                                        color: _selectedPlan == 'standard'
                                            ? primaryColor
                                            : textSecondary,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Plan B: Maternal & Obstetric Plan (Subscription)
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
                                        child: const Text('🌸', style: TextStyle(fontSize: 20)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                const Text(
                                                  'Maternal & Obstetric Plan',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFEC4899).withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: const Text(
                                                    'SUBSCRIPTION',
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
                                              'Gestational tracking, daily wellness insights, labor pre-alert & rare blood shield.',
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

                          // MATERNAL-SPECIFIC FIELDS
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
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Current Gestational Age:',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEC4899),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'Week $_gestationalWeeks • ${_getTrimesterLabel(_gestationalWeeks)}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                          ),
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
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: _eddController,
                                    style: TextStyle(color: textPrimary, fontSize: 13),
                                    decoration: _inputDecoration(
                                      label: 'Estimated Due Date (EDD e.g., 2026-12-15)',
                                      prefixIcon: Icons.calendar_today_rounded,
                                      isDark: isDark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],

                          // Blood Group Selection (Rare Blood Shield Support)
                          DropdownButtonFormField<String>(
                            value: _selectedBloodGroup,
                            dropdownColor: cardBg,
                            style: TextStyle(color: textPrimary, fontSize: 13),
                            decoration: _inputDecoration(
                              label: 'Blood Group',
                              prefixIcon: Icons.bloodtype_rounded,
                              isDark: isDark,
                            ),
                            items: _bloodGroups.map((bg) {
                              return DropdownMenuItem(
                                value: bg,
                                child: Text(
                                  bg,
                                  style: TextStyle(
                                    color: bg.contains('O-') ? Colors.redAccent : textPrimary,
                                    fontWeight: bg.contains('O-') ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedBloodGroup = val);
                            },
                          ),
                          const SizedBox(height: 14),

                          // Preferred Hospital
                          DropdownButtonFormField<String>(
                            value: _preferredHospital,
                            isExpanded: true,
                            dropdownColor: cardBg,
                            style: TextStyle(color: textPrimary, fontSize: 12),
                            decoration: _inputDecoration(
                              label: 'Preferred Partner Hospital',
                              prefixIcon: Icons.local_hospital_outlined,
                              isDark: isDark,
                            ),
                            items: _hospitals.map((h) {
                              return DropdownMenuItem(
                                value: h,
                                child: Text(h, overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _preferredHospital = val);
                            },
                          ),
                          const SizedBox(height: 18),
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
                                            ? 'ACTIVATE MATERNAL SHIELD'
                                            : 'ACTIVATE EMERGENCY SHIELD')
                                        : 'SIGN IN TO SOLACE SHIELD',
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
                    'Solace EMS • 24/7 Rapid Ambulance & Hospital Intake Network',
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
