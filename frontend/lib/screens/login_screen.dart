import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api_session.dart';
import '../l10n/strings.dart';
import '../utils/toast.dart';
import '../widgets/action_required_banner.dart';
import 'owner_setup_screen.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _error;

  static const String _kApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  static const String _demoAdminId = 'superadmin@medishop.local';
  static const String _demoOwnerId = '+919876512345';

  @override
  void initState() {
    super.initState();
    // Show the "signed out" confirmation left behind by the previous screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final flash = AppFlash.take();
      if (flash != null && mounted) {
        AppToast.show(context, flash);
      }
    });
  }

  /// Fills the demo account identifier without exposing or filling a password.
  void _fillDemoCredentials(String role) {
    switch (role) {
      case 'SUPER_ADMIN':
        _identifierController.text = _demoAdminId;
      case 'SHOP_OWNER':
        _identifierController.text = _demoOwnerId;
    }
    _passwordController.clear();
    setState(() {
      _error = null;
      _obscurePassword = true;
    });
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Welcome popup shown right after a successful login, before routing on.
  Future<void> _showWelcomeDialog() async {
    final name = ApiSession.user['fullName'] as String? ?? 'Account';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.celebration_rounded, color: Color(0xFF0B4F3A)),
        title: Text(trf('welcomeBack', {'name': name})),
        content: Text(tr('welcomeMessage')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(tr('goToDashboard')),
          ),
        ],
      ),
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    _error = null;
    try {
      final response = await http
          .post(
            Uri.parse('$_kApiBaseUrl/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'identifier': _identifierController.text.trim(),
              'password': _passwordController.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        ApiSession.updateFromResponse(data);
        // Restore the language saved on the account so notifications and all
        // screens open in the owner's choice after a restart.
        AppLanguage.set(ApiSession.userLanguage ?? 'en');
        final role = ApiSession.user['role'] as String?;
        if (!mounted) return;
        if (role == 'SHOP_OWNER' || role == 'SUPER_ADMIN') {
          await _showWelcomeDialog();
        }
        if (!mounted) return;
        // Surface anything still blocking the account before the dashboard.
        await showActionRequiredPopup(context);
        if (!mounted) return;
        if (role == 'SHOP_OWNER' &&
            ApiSession.onboarding['mustChangePassword'] == true) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const OwnerSetupScreen()),
          );
        } else if (role == 'SUPER_ADMIN' || role == 'SHOP_OWNER') {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => DashboardScreen(
                userRole: role!,
                userName: ApiSession.user['fullName'] as String? ?? 'Account',
              ),
            ),
          );
        } else {
          setState(() => _error = tr('noAppRole'));
        }
      } else {
        final responseData = jsonDecode(response.body);
        setState(
          () => _error =
              responseData['message']?.toString() ?? tr('invalidCredentials'),
        );
      }
    } catch (e) {
      debugPrint('Sign-in flow failed (${e.runtimeType}): $e');
      if (mounted) setState(() => _error = tr('connectionError'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B4F3A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.local_pharmacy_rounded,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  tr('signInTitle'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('signInSubtitle'),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 24),
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _identifierController,
                  decoration: InputDecoration(
                    labelText: tr('emailOrMobile'),
                    hintText: tr('emailOrMobileHint'),
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return tr('enterIdentifier');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: tr('password'),
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      tooltip: _obscurePassword
                          ? 'Show password'
                          : 'Hide password',
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _login(),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return tr('enterPassword');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: _isLoading
                      ? const CircularProgressIndicator(
                          color: Color(0xFF0B4F3A),
                        )
                      : ElevatedButton(
                          onPressed: _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0B4F3A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            tr('signIn'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          tr('quickDemo'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Keep the two demo buttons side by side only when there is
                    // room; stack them on narrow phones so labels stay readable.
                    final twoAcross = constraints.maxWidth >= 360;
                    final buttonWidth = twoAcross
                        ? (constraints.maxWidth - 12) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        SizedBox(
                          width: buttonWidth,
                          child: OutlinedButton.icon(
                            icon: const Icon(
                              Icons.admin_panel_settings_outlined,
                            ),
                            label: Text(
                              tr('superAdmin'),
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF0B4F3A),
                              side: const BorderSide(color: Color(0xFF0B4F3A)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () =>
                                _fillDemoCredentials('SUPER_ADMIN'),
                          ),
                        ),
                        SizedBox(
                          width: buttonWidth,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.storefront_outlined),
                            label: Text(
                              tr('medicalOwner'),
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF0B4F3A),
                              side: const BorderSide(color: Color(0xFF0B4F3A)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => _fillDemoCredentials('SHOP_OWNER'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pushNamed('/terms'),
                      child: const Text('Terms of Use'),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pushNamed('/privacy'),
                      child: const Text('Privacy Policy'),
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
