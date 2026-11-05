import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api_session.dart';
import '../utils/toast.dart';

/// Finishes the steps the API still reports as open: set a password, verify
/// the contact and complete the shop profile. Every action-required banner in
/// the app points here.
class AccountSetupScreen extends StatefulWidget {
  const AccountSetupScreen({super.key});

  @override
  State<AccountSetupScreen> createState() => _AccountSetupScreenState();
}

class _AccountSetupScreenState extends State<AccountSetupScreen> {
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  final _formKey = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _code = TextEditingController();
  final _fullName = TextEditingController();
  final _shopName = TextEditingController();
  final _address1 = TextEditingController();
  final _address2 = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _postalCode = TextEditingController();
  final _shopContact = TextEditingController();

  bool _isLoading = true;
  bool _busy = false;
  bool _obscure = true;
  Map<String, dynamic> _steps = {};
  List<Map<String, dynamic>> _stepList = [];
  String? _verificationHint;
  String? _error;

  bool get _mustChangePassword =>
      _steps['mustChangePassword'] == true ||
      ApiSession.onboarding['mustChangePassword'] == true;

  bool _stepDone(String key) {
    for (final step in _stepList) {
      if (step['key'] == key) return step['done'] == true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    _code.dispose();
    _fullName.dispose();
    _shopName.dispose();
    _address1.dispose();
    _address2.dispose();
    _city.dispose();
    _state.dispose();
    _postalCode.dispose();
    _shopContact.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final responses = await Future.wait([
        http
            .get(
              Uri.parse('$_apiBaseUrl/api/owner/onboarding'),
              headers: ApiSession.headers,
            )
            .timeout(const Duration(seconds: 8)),
        http
            .get(
              Uri.parse('$_apiBaseUrl/api/shops/me'),
              headers: ApiSession.headers,
            )
            .timeout(const Duration(seconds: 8)),
      ]);
      final onboarding = jsonDecode(responses[0].body) as Map<String, dynamic>;
      final steps = (onboarding['steps'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (responses[1].statusCode == 200) {
        final shopData = jsonDecode(responses[1].body) as Map<String, dynamic>;
        final shop = shopData['shop'] as Map<String, dynamic>?;
        final address = shop?['address'] as Map<String, dynamic>? ?? {};
        _fullName.text = ApiSession.user['fullName']?.toString() ?? '';
        _shopName.text = shop?['shopName']?.toString() ?? '';
        _address1.text = address['line1']?.toString() ?? '';
        _address2.text = address['line2']?.toString() ?? '';
        _city.text = address['city']?.toString() ?? '';
        _state.text = address['state']?.toString() ?? '';
        _postalCode.text = address['postalCode']?.toString() ?? '';
        _shopContact.text =
            shop?['phoneE164']?.toString() ??
            shop?['emailNormalized']?.toString() ??
            ApiSession.user['emailNormalized']?.toString() ??
            '';
      }
      if (!mounted) return;
      setState(() {
        _steps = onboarding;
        _stepList = steps;
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('Could not load onboarding: $error');
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your setup steps.';
        _isLoading = false;
      });
    }
  }

  String? _validatePassword(String? value) {
    if (value == null || value.length < 12) return 'Use at least 12 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(value) ||
        !RegExp(r'[0-9]').hasMatch(value)) {
      return 'Include at least one letter and one number';
    }
    return null;
  }

  Future<void> _savePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final temporary = _mustChangePassword;
    try {
      final response = temporary
          ? await http
                .post(
                  Uri.parse(
                    '$_apiBaseUrl/api/auth/owner/change-temporary-password',
                  ),
                  headers: ApiSession.headers,
                  body: jsonEncode({
                    'newPassword': _newPassword.text.trim(),
                    'confirmPassword': _confirmPassword.text.trim(),
                  }),
                )
                .timeout(const Duration(seconds: 12))
          : await http
                .post(
                  Uri.parse('$_apiBaseUrl/api/auth/change-password'),
                  headers: ApiSession.headers,
                  body: jsonEncode({
                    'currentPassword': _currentPassword.text.trim(),
                    'newPassword': _newPassword.text.trim(),
                    'confirmPassword': _confirmPassword.text.trim(),
                  }),
                )
                .timeout(const Duration(seconds: 12));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(data['message'] ?? 'Could not update the password');
      }
      if (temporary) {
        ApiSession.updateFromResponse(data);
      }
      _currentPassword.clear();
      _newPassword.clear();
      _confirmPassword.clear();
      if (!mounted) return;
      AppToast.show(context, 'Password updated');
      await _load();
    } catch (error) {
      debugPrint('Password update failed: $error');
      if (!mounted) return;
      AppToast.show(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        success: false,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestCode() async {
    setState(() => _busy = true);
    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/api/auth/contact-verification/request'),
            headers: ApiSession.headers,
            body: jsonEncode({'email': true}),
          )
          .timeout(const Duration(seconds: 12));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(data['message'] ?? 'Could not send the code');
      }
      final code = data['devCode']?.toString();
      if (!mounted) return;
      setState(() {
        _verificationHint =
            'Code sent to ${data['destination'] ?? 'your contact'}'
            '${code == null ? '' : ' · dev code $code'}';
      });
    } catch (error) {
      debugPrint('Verification request failed: $error');
      if (!mounted) return;
      AppToast.show(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        success: false,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      AppToast.show(context, 'Enter the code you received', success: false);
      return;
    }
    setState(() => _busy = true);
    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/api/auth/contact-verification/verify'),
            headers: ApiSession.headers,
            body: jsonEncode({'code': code}),
          )
          .timeout(const Duration(seconds: 12));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(data['message'] ?? 'Could not verify the code');
      }
      _code.clear();
      if (!mounted) return;
      AppToast.show(context, 'Contact verified');
      await _load();
    } catch (error) {
      debugPrint('Verification failed: $error');
      if (!mounted) return;
      AppToast.show(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        success: false,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _busy = true);
    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/api/owner/profile/complete'),
            headers: ApiSession.headers,
            body: jsonEncode({
              'fullName': _fullName.text.trim(),
              'shopName': _shopName.text.trim(),
              'addressLine1': _address1.text.trim(),
              'addressLine2': _address2.text.trim().isEmpty
                  ? null
                  : _address2.text.trim(),
              'city': _city.text.trim(),
              'state': _state.text.trim(),
              'postalCode': _postalCode.text.trim(),
              'shopContactNumber': _shopContact.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(data['message'] ?? 'Could not save the profile');
      }
      if (!mounted) return;
      AppToast.show(context, 'Shop profile saved');
      await _load();
    } catch (error) {
      debugPrint('Profile save failed: $error');
      if (!mounted) return;
      AppToast.show(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        success: false,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account setup')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _stepCard(
                  title: '1. Password',
                  done: _stepDone('change_password'),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        if (!_mustChangePassword) ...[
                          TextFormField(
                            controller: _currentPassword,
                            obscureText: _obscure,
                            decoration: const InputDecoration(
                              labelText: 'Current password',
                            ),
                            validator: (value) =>
                                (value == null || value.isEmpty)
                                ? 'Required'
                                : null,
                          ),
                          const SizedBox(height: 10),
                        ],
                        TextFormField(
                          controller: _newPassword,
                          obscureText: _obscure,
                          decoration: const InputDecoration(
                            labelText: 'New password',
                          ),
                          validator: _validatePassword,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _confirmPassword,
                          obscureText: _obscure,
                          decoration: const InputDecoration(
                            labelText: 'Confirm new password',
                          ),
                          validator: (value) => value != _newPassword.text
                              ? 'Passwords do not match'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 18,
                              ),
                              label: const Text('Show'),
                            ),
                            const Spacer(),
                            FilledButton(
                              onPressed: _busy ? null : _savePassword,
                              child: const Text('Save password'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                _stepCard(
                  title: '2. Verify your contact',
                  done: _stepDone('verify_contact'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'We send receipts and alerts to a verified email or mobile number.',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _code,
                              decoration: const InputDecoration(
                                labelText: '8-character code',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _busy ? null : _requestCode,
                            child: const Text('Send code'),
                          ),
                        ],
                      ),
                      if (_verificationHint != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _verificationHint!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: _busy ? null : _verifyCode,
                          child: const Text('Verify'),
                        ),
                      ),
                    ],
                  ),
                ),
                _stepCard(
                  title: '3. Shop profile',
                  done: _stepDone('complete_profile'),
                  child: Column(
                    children: [
                      _field(_fullName, 'Your full name'),
                      _field(_shopName, 'Shop name'),
                      _field(_address1, 'Address line 1'),
                      _field(_address2, 'Address line 2', required: false),
                      _field(_city, 'City'),
                      _field(_state, 'State'),
                      _field(_postalCode, 'PIN code'),
                      _field(_shopContact, 'Shop phone or email'),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: _busy ? null : _saveProfile,
                          child: const Text('Save profile'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        validator: required
            ? (value) =>
                  (value == null || value.trim().isEmpty) ? 'Required' : null
            : null,
      ),
    );
  }

  Widget _stepCard({
    required String title,
    required bool done,
    required Widget child,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  done
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  color: done
                      ? const Color(0xFF059669)
                      : const Color(0xFFB45309),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }
}
