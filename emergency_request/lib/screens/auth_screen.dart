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
  final _gestationalWeeksController = TextEditingController(text: '32');

  bool _isSignUp = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  // Sign up care plan
  String _profileType = 'maternal'; // 'maternal' | 'standard'

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _gestationalWeeksController.dispose();
    super.dispose();
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
    final isMaternal = _profileType == 'maternal';
    final weeks = int.tryParse(_gestationalWeeksController.text.trim()) ?? 32;

    try {
      if (_isSignUp) {
        final res = await _supabase.auth.signUp(
          email: email,
          password: password,
          data: {
            'full_name': name,
            'phone': phone,
            'profile_type': _profileType,
            'is_pregnant': isMaternal,
            'gestational_weeks': isMaternal ? weeks : null,
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
              'profile_type': _profileType,
              'is_pregnant': isMaternal,
              'gestational_weeks': isMaternal ? weeks : null,
            }, onConflict: 'user_id');
          } catch (_) {}
        }
        if (res.session == null) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _errorMessage =
                'Account registered. Please check your email inbox to confirm, then sign in.';
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
        _errorMessage = 'An unexpected error occurred: $e';
      });
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData prefixIcon,
    required bool isDark,
    Widget? suffixIcon,
  }) {
    final textMuted = isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted;
    final inputBg = isDark ? const Color(0xFF0D2559) : const Color(0xFFF1F5F9);
    final normalBorder = isDark ? AppTheme.darkCardBorder : const Color(0xFF94A3B8);
    final focusedBorderColor = isDark ? AppTheme.darkPrimary : AppTheme.lightPrimary;

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: normalBorder),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: focusedBorderColor, width: 1.8),
    );
    final errorBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFD32F2F), width: 1.4),
    );

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: textMuted, fontSize: 13),
      prefixIcon: Icon(prefixIcon, color: textMuted, size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: inputBg,
      border: border,
      enabledBorder: border,
      focusedBorder: focusedBorder,
      errorBorder: errorBorder,
      focusedErrorBorder: errorBorder,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final cardBorder = isDark ? AppTheme.darkCardBorder : const Color(0xFFCBD5E1);
    final textPrimary = isDark ? AppTheme.darkTextPrimary : const Color(0xFF0F172A);
    final textMuted = isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted;
    final primaryColor = isDark ? AppTheme.darkPrimary : AppTheme.lightPrimary;

    final isMaternal = _profileType == 'maternal';

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: cardColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: primaryColor, width: 2.0),
                        boxShadow: [
                          BoxShadow(
                            color: primaryColor.withValues(alpha: 0.25),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.medical_services_rounded,
                        size: 46,
                        color: primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'SOLACE RAPID EMS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: textPrimary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isSignUp
                        ? 'Select your emergency care plan & register'
                        : 'Sign in to access rapid ambulance response',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: textMuted),
                  ),
                  const SizedBox(height: 24),

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: Colors.redAccent, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                  color: Colors.redAccent, fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Form Container
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: cardBorder),
                    ),
                    child: Column(
                      children: [
                        if (_isSignUp) ...[
                          // Care Plan Picker
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _profileType = 'maternal');
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                    decoration: BoxDecoration(
                                      color: isMaternal
                                          ? const Color(0xFFEC4899).withValues(alpha: 0.15)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isMaternal ? const Color(0xFFEC4899) : cardBorder,
                                        width: isMaternal ? 1.6 : 1.0,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        const Text('🌸', style: TextStyle(fontSize: 18)),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Maternal Plan',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: isMaternal ? const Color(0xFFEC4899) : textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _profileType = 'standard');
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                    decoration: BoxDecoration(
                                      color: !isMaternal
                                          ? const Color(0xFF0284C7).withValues(alpha: 0.15)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: !isMaternal ? const Color(0xFF0284C7) : cardBorder,
                                        width: !isMaternal ? 1.6 : 1.0,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        const Text('🛡️', style: TextStyle(fontSize: 18)),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Standard Shield',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: !isMaternal ? const Color(0xFF0284C7) : textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Name
                          TextFormField(
                            controller: _nameController,
                            style: TextStyle(color: textPrimary, fontSize: 14),
                            cursorColor: primaryColor,
                            decoration: _inputDecoration(
                              label: 'Full Name',
                              prefixIcon: Icons.person_outline_rounded,
                              isDark: isDark,
                            ),
                            validator: (val) {
                              if (_isSignUp && (val == null || val.trim().isEmpty)) {
                                return 'Please enter your name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          // Phone
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            style: TextStyle(color: textPrimary, fontSize: 14),
                            cursorColor: primaryColor,
                            decoration: _inputDecoration(
                              label: 'Phone Number',
                              prefixIcon: Icons.phone_outlined,
                              isDark: isDark,
                            ),
                            validator: (val) {
                              if (_isSignUp && (val == null || val.trim().isEmpty)) {
                                return 'Please enter phone number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          if (isMaternal) ...[
                            TextFormField(
                              controller: _gestationalWeeksController,
                              keyboardType: TextInputType.number,
                              style: TextStyle(color: textPrimary, fontSize: 14),
                              decoration: _inputDecoration(
                                label: 'Gestational Weeks (e.g. 32)',
                                prefixIcon: Icons.pregnant_woman_rounded,
                                isDark: isDark,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ],

                        // Email
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: TextStyle(color: textPrimary, fontSize: 14),
                          cursorColor: primaryColor,
                          decoration: _inputDecoration(
                            label: 'Email Address',
                            prefixIcon: Icons.email_outlined,
                            isDark: isDark,
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Please enter your email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        // Password
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: TextStyle(color: textPrimary, fontSize: 14),
                          cursorColor: primaryColor,
                          decoration: _inputDecoration(
                            label: 'Password',
                            prefixIcon: Icons.lock_outline_rounded,
                            isDark: isDark,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: textMuted,
                                size: 20,
                              ),
                              onPressed: () {
                                setState(() => _obscurePassword = !_obscurePassword);
                              },
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        // Submit
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _isLoading ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: isDark ? const Color(0xFF030E22) : Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                                  )
                                : Text(
                                    _isSignUp ? 'Create My Solace Shield' : 'Sign In to Solace',
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Switch between sign in / sign up
                  Center(
                    child: TextButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _isSignUp = !_isSignUp;
                          _errorMessage = null;
                        });
                      },
                      child: Text(
                        _isSignUp
                            ? 'Already have an account? Sign in'
                            : "Don't have an account? Register with Care Plan",
                        style: TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
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
