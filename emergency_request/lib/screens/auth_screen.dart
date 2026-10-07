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

  bool _isSignUp = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
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

    try {
      if (_isSignUp) {
        final res = await _supabase.auth.signUp(
          email: email,
          password: password,
          data: {
            'full_name': name,
            'phone': phone,
          },
        );
        final user = res.user;
        if (user != null) {
          try {
            await _supabase.from('profiles').upsert({
              'user_id': user.id,
              'display_name': name.isNotEmpty ? name : 'Solace Patient',
              'full_name': name.isNotEmpty ? name : 'Solace Patient',
              'phone': phone.isNotEmpty ? phone : null,
              'role': 'client',
            }, onConflict: 'user_id');
          } catch (_) {}
        }
        if (res.session == null) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _errorMessage = 'Account created. Please check your email to confirm, then sign in.';
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final cardBorder = isDark ? AppTheme.darkCardBorder : const Color(0xFFCBD5E1);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF81D4FA) : const Color(0xFF0284C7);
    final textMuted = isDark ? Colors.white60 : const Color(0xFF64748B);
    final inputBg = isDark ? const Color(0xFF0D2559) : const Color(0xFFF1F5F9);
    final inputBorder = isDark ? const Color(0xFF1E3A8A) : const Color(0xFF94A3B8);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme',
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7),
            ),
            onPressed: () {
              HapticFeedback.selectionClick();
              AppTheme.toggleTheme();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Solace Emergency Logo & Brand
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF07193F) : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7),
                          width: 2.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7))
                                .withValues(alpha: 0.25),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.medical_services_rounded,
                        size: 46,
                        color: isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7),
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
                        ? 'Register for instant emergency dispatch & tracking'
                        : 'Sign in to access rapid ambulance response',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: textMuted),
                  ),
                  const SizedBox(height: 26),

                  // Error notification
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
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
                      boxShadow: isDark
                          ? []
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 12,
                                offset: const Offset(0, 3),
                              ),
                            ],
                    ),
                    child: Column(
                      children: [
                        if (_isSignUp) ...[
                          TextFormField(
                            controller: _nameController,
                            style: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                            decoration: InputDecoration(
                              labelText: 'Full Name',
                              labelStyle: TextStyle(color: textMuted, fontSize: 13),
                              prefixIcon: Icon(Icons.person_outline_rounded, color: textMuted),
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
                            validator: (val) {
                              if (_isSignUp && (val == null || val.trim().isEmpty)) {
                                return 'Please enter your full name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            style: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                            decoration: InputDecoration(
                              labelText: 'Phone Number (Callback Line)',
                              labelStyle: TextStyle(color: textMuted, fontSize: 13),
                              prefixIcon: Icon(Icons.phone_outlined, color: textMuted),
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
                            validator: (val) {
                              if (_isSignUp && (val == null || val.trim().isEmpty)) {
                                return 'Please enter your phone number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                          decoration: InputDecoration(
                            labelText: 'Email Address',
                            labelStyle: TextStyle(color: textMuted, fontSize: 13),
                            prefixIcon: Icon(Icons.email_outlined, color: textMuted),
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
                          style: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            labelStyle: TextStyle(color: textMuted, fontSize: 13),
                            prefixIcon: Icon(Icons.lock_outline_rounded, color: textMuted),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                color: textMuted,
                                size: 20,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
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
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          ),
                          validator: (val) {
                            if (val == null || val.length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFD32F2F),
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
                                    _isSignUp ? 'CREATE ACCOUNT & ENTER' : 'SIGN IN TO DISPATCH',
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.8),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Toggle between Sign in & Register
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isSignUp ? 'Already have a Solace account?' : "Don't have an account?",
                        style: TextStyle(color: textMuted, fontSize: 13),
                      ),
                      TextButton(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _isSignUp = !_isSignUp;
                            _errorMessage = null;
                          });
                        },
                        child: Text(
                          _isSignUp ? 'Sign In' : 'Register Now',
                          style: TextStyle(
                            color: isDark ? const Color(0xFF00D4FF) : const Color(0xFF0284C7),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      '24/7 Rapid Emergency Response Network',
                      style: TextStyle(color: textMuted.withValues(alpha: 0.7), fontSize: 11),
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
