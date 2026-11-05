import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

import '../api_session.dart';
import '../l10n/strings.dart';
import '../utils/payments.dart';
import '../utils/toast.dart';
import '../widgets/app_shell.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.passwordUpdated = false});

  final bool passwordUpdated;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _notificationsEnabled = ApiSession.notificationsEnabled;
  bool _notificationSoundsEnabled = ApiSession.notificationSoundsEnabled;
  bool _obscurePassword = true;
  String? _error;
  List<dynamic> _sessions = [];
  String _selectedLanguage = AppLanguage.current;
  bool _isSavingLanguage = false;
  List<dynamic> _plans = [];
  String _currentPlan = '';
  bool _isSavingPlan = false;

  // Owner payment setup (UPI + QR) and profile photo.
  final _upiIdController = TextEditingController();
  final _payeeNameController = TextEditingController();
  bool _cashEnabled = true;
  bool _onlineEnabled = true;
  String? _staticQrImage;
  String? _profileImage;
  String? _shopId;
  bool _isSavingPayments = false;
  bool _isSavingPhoto = false;

  bool get _isAdmin => ApiSession.user['role'] == 'SUPER_ADMIN';
  bool get _isOwner => ApiSession.user['role'] == 'SHOP_OWNER';

  @override
  void initState() {
    super.initState();
    _profileImage = ApiSession.user['profileImage'] as String?;
    _loadSessions();
    _loadPlans();
    if (_isOwner) _loadShopPaymentSettings();
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _upiIdController.dispose();
    _payeeNameController.dispose();
    super.dispose();
  }

  Future<void> _loadShopPaymentSettings() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_apiBaseUrl/api/shops/me'),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 || !mounted) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final shop = data['shop'] as Map<String, dynamic>?;
      final settings = shop?['paymentSettings'] as Map<String, dynamic>?;
      setState(() {
        _shopId = shop?['_id']?.toString();
        _upiIdController.text = settings?['upiId']?.toString() ?? '';
        _payeeNameController.text = settings?['payeeName']?.toString() ?? '';
        _staticQrImage = settings?['qrImage']?.toString();
        _cashEnabled = settings?['cashEnabled'] as bool? ?? true;
        _onlineEnabled = settings?['onlineEnabled'] as bool? ?? true;
      });
    } catch (error) {
      debugPrint('Could not load payment settings: $error');
    }
  }

  // base64 grows ~33%, so 800 KB stays under the API's 1.5 MB data-URL cap.
  Future<String?> _pickImageDataUrl({int maxBytes = 800000}) async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.image);
      if (picked.isEmpty) return null;
      final file = picked.single;
      final Uint8List bytes = await file.xFile.readAsBytes();
      if (bytes.length > maxBytes) {
        if (mounted) {
          AppToast.show(
            context,
            'Image is too large. Use one under ${maxBytes ~/ 1000} KB.',
            success: false,
          );
        }
        return null;
      }
      final extension = (file.extension ?? 'png').toLowerCase();
      final mime = extension == 'jpg' || extension == 'jpeg'
          ? 'jpeg'
          : extension == 'webp'
          ? 'webp'
          : 'png';
      return 'data:image/$mime;base64,${base64Encode(bytes)}';
    } catch (error) {
      debugPrint('Image pick failed: $error');
      if (mounted) {
        AppToast.show(context, 'Could not read that image', success: false);
      }
      return null;
    }
  }

  Future<void> _savePaymentSettings() async {
    if (_shopId == null) {
      AppToast.show(context, 'No shop linked to this account', success: false);
      return;
    }
    final upiId = _upiIdController.text.trim();
    if (upiId.isNotEmpty && !isValidUpiId(upiId)) {
      AppToast.show(
        context,
        'Enter a valid UPI ID, for example shop@okhdfcbank',
        success: false,
      );
      return;
    }
    if (!_cashEnabled && !_onlineEnabled) {
      AppToast.show(
        context,
        'Keep cash or online payment turned on',
        success: false,
      );
      return;
    }
    setState(() => _isSavingPayments = true);
    try {
      final response = await http
          .patch(
            Uri.parse('$_apiBaseUrl/api/shops/$_shopId'),
            headers: ApiSession.headers,
            body: jsonEncode({
              'paymentSettings': {
                'upiId': upiId.isEmpty ? null : upiId,
                'payeeName': _payeeNameController.text.trim().isEmpty
                    ? null
                    : _payeeNameController.text.trim(),
                'qrImage': _staticQrImage,
                'cashEnabled': _cashEnabled,
                'onlineEnabled': _onlineEnabled,
              },
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      if (response.statusCode == 200) {
        AppToast.show(context, tr('paymentSettingsSaved'));
      } else {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(data['message'] ?? 'Could not save payment settings');
      }
    } catch (error) {
      if (mounted) {
        AppToast.show(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          success: false,
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingPayments = false);
    }
  }

  Future<void> _saveProfilePhoto() async {
    setState(() => _isSavingPhoto = true);
    try {
      final response = await http
          .patch(
            Uri.parse('$_apiBaseUrl/api/users/me'),
            headers: ApiSession.headers,
            body: jsonEncode({'profileImage': _profileImage ?? ''}),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final user = data['user'] as Map<String, dynamic>?;
        if (user != null) setState(() => ApiSession.user = user);
        AppToast.show(context, tr('profilePhotoSaved'));
      } else {
        throw Exception('Could not save photo');
      }
    } catch (error) {
      debugPrint('Profile photo save failed: $error');
      if (mounted) {
        setState(
          () => _profileImage = ApiSession.user['profileImage'] as String?,
        );
        AppToast.show(context, tr('couldNotUpdateProfile'), success: false);
      }
    } finally {
      if (mounted) setState(() => _isSavingPhoto = false);
    }
  }

  Future<void> _loadPlans() async {
    try {
      final response = await http
          .get(Uri.parse('$_apiBaseUrl/api/plans'), headers: ApiSession.headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;
      if (!mounted) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      setState(() {
        _plans = data['plans'] as List<dynamic>? ?? [];
        _currentPlan = data['currentPlan']?.toString() ?? '';
      });
    } catch (_) {
      // Plan catalog is optional chrome; never block settings over it.
    }
  }

  Future<void> _changePlan(String planId) async {
    if (_isSavingPlan) return;
    setState(() => _isSavingPlan = true);
    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/api/plans/select'),
            headers: ApiSession.headers,
            body: jsonEncode({'plan': planId}),
          )
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() => _currentPlan = planId);
        ApiSession.plan = planId;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Plan changed to ${planId.toLowerCase()}')),
        );
      } else {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['message']?.toString() ?? 'Could not change plan',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection error. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingPlan = false);
    }
  }

  void _openPlanPicker() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Choose a plan'),
        children: [
          for (final plan in _plans)
            ListTile(
              leading: (plan['id']?.toString() ?? '') == _currentPlan
                  ? const Icon(Icons.check_circle, color: Color(0xFF1F7A45))
                  : const Icon(Icons.radio_button_unchecked),
              title: Text('${plan['name']} · ₹${plan['priceInr']}/month'),
              subtitle: Text(
                (plan['features'] as List<dynamic>?)?.join(' · ') ?? '',
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.of(dialogContext).pop();
                _changePlan(plan['id']?.toString() ?? '');
              },
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSessions() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_apiBaseUrl/api/users/me/sessions'),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (mounted) {
          setState(() => _sessions = data['items'] as List<dynamic>? ?? []);
        }
      }
    } catch (error) {
      debugPrint('Could not load sessions: $error');
    }
  }

  Future<void> _editProfile() async {
    final controller = TextEditingController(
      text: ApiSession.user['fullName'] as String? ?? '',
    );
    var dialogPhoto = _profileImage;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(tr('editProfile')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  _profileAvatar(size: 84, image: decodeDataImage(dialogPhoto)),
                  IconButton.filled(
                    tooltip: tr('changePhoto'),
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    onPressed: () async {
                      final picked = await _pickImageDataUrl(maxBytes: 800000);
                      if (picked != null) {
                        setDialogState(() => dialogPhoto = picked);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(labelText: tr('fullName')),
              ),
            ],
          ),
          actions: [
            if (dialogPhoto != null)
              TextButton.icon(
                onPressed: () => setDialogState(() => dialogPhoto = null),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(tr('removePhoto')),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(tr('save')),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final newName = controller.text.trim();
    if (newName.length < 2) {
      if (mounted) {
        AppToast.show(
          context,
          'Name must be at least 2 characters',
          success: false,
        );
      }
      return;
    }
    try {
      final response = await http
          .patch(
            Uri.parse('$_apiBaseUrl/api/users/me'),
            headers: ApiSession.headers,
            body: jsonEncode({
              'fullName': newName,
              'profileImage': dialogPhoto ?? '',
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final user = data['user'] as Map<String, dynamic>?;
        if (user != null && mounted) {
          setState(() {
            ApiSession.user = user;
            _profileImage = user['profileImage'] as String?;
          });
          AppToast.show(context, trf('profileUpdated', {'name': newName}));
        }
      } else {
        throw Exception('Update failed (${response.statusCode})');
      }
    } catch (error) {
      debugPrint('Profile update failed: $error');
      if (mounted) {
        AppToast.show(context, tr('couldNotUpdateProfile'), success: false);
      }
    }
  }

  Widget _profileAvatar({double size = 52, Uint8List? image}) {
    if (image != null) {
      return ClipOval(
        child: Image.memory(
          image,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFFE2ECE7),
      child: Icon(
        Icons.person_outline,
        size: size * 0.5,
        color: const Color(0xFF0B4F3A),
      ),
    );
  }

  Widget _buildPaymentSettingsCard() {
    final previewUri = buildUpiUri(
      upiId: _upiIdController.text,
      payeeName: _payeeNameController.text,
      amount: null,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.qr_code_2_rounded, color: Color(0xFF0B4F3A)),
                const SizedBox(width: 10),
                Text(
                  tr('paymentSettings'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              tr('paymentSettingsHint'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _upiIdController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: tr('upiId'),
                hintText: 'shop@okhdfcbank',
                prefixIcon: const Icon(Icons.account_balance_outlined),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _payeeNameController,
              decoration: InputDecoration(
                labelText: tr('payeeName'),
                border: const OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.payments_outlined),
              title: Text(tr('acceptCash')),
              value: _cashEnabled,
              onChanged: (value) => setState(() => _cashEnabled = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.qr_code_scanner_rounded),
              title: Text(tr('acceptOnline')),
              value: _onlineEnabled,
              onChanged: (value) => setState(() => _onlineEnabled = value),
            ),
            if (_onlineEnabled && previewUri != null) ...[
              const Divider(height: 24),
              Center(
                child: Column(
                  children: [
                    QrImageView(
                      data: previewUri,
                      size: 150,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF0B4F3A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr('paymentQrPreview'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await _pickImageDataUrl();
                      if (picked != null) {
                        setState(() => _staticQrImage = picked);
                      }
                    },
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: Text(
                      _staticQrImage == null ? tr('uploadQr') : tr('replaceQr'),
                    ),
                  ),
                ),
                if (_staticQrImage != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: tr('removePhoto'),
                    onPressed: () => setState(() => _staticQrImage = null),
                    icon: const Icon(Icons.delete_outline),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      decodeDataImage(_staticQrImage) ?? Uint8List(0),
                      width: 46,
                      height: 46,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _isSavingPayments ? null : _savePaymentSettings,
                icon: _isSavingPayments
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(tr('savePaymentSettings')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Applies the selected language across the whole app after Save is pressed.
  Future<void> _saveLanguage() async {
    setState(() => _isSavingLanguage = true);
    AppLanguage.set(_selectedLanguage);
    ApiSession.userLanguage = _selectedLanguage;
    // Persist on the account when the API supports it; local state always wins.
    try {
      await http
          .patch(
            Uri.parse('$_apiBaseUrl/api/users/me'),
            headers: ApiSession.headers,
            body: jsonEncode({'language': _selectedLanguage}),
          )
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      // Language still applies locally even when the backend is offline.
    }
    if (mounted) {
      setState(() => _isSavingLanguage = false);
      AppToast.show(
        context,
        trf('languageSaved', {'lang': AppLanguage.labelFor(_selectedLanguage)}),
      );
    }
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/api/auth/change-password'),
            headers: ApiSession.headers,
            body: jsonEncode({
              'currentPassword': _currentPasswordController.text,
              'newPassword': _newPasswordController.text,
              'confirmPassword': _confirmPasswordController.text,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        final message = data['message'];
        throw Exception(
          message is String ? message : 'Could not update password',
        );
      }
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.check_circle_outline),
            title: Text(tr('passwordUpdated')),
            content: Text(tr('passwordUpdatedMsg')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(tr('done')),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    try {
      if (ApiSession.accessToken != null) {
        await http
            .post(
              Uri.parse('$_apiBaseUrl/api/auth/logout'),
              headers: ApiSession.headers,
            )
            .timeout(const Duration(seconds: 5));
      }
    } catch (_) {
      // Clear the local session even when the API is unavailable.
    } finally {
      ApiSession.clear();
      AppFlash.set(tr('loggedOut'));
      if (mounted) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/login', (route) => false);
      }
    }
  }

  String? _passwordValidator(String? value) {
    if (value == null || value.length < 12) return 'Use at least 12 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(value) ||
        !RegExp(r'[0-9]').hasMatch(value)) {
      return 'Include at least one letter and one number';
    }
    return null;
  }

  Widget _buildLanguageCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.language, color: Color(0xFF0B4F3A)),
                const SizedBox(width: 10),
                Text(
                  tr('appLanguage'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              tr('chooseLanguage'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (code, label, native) in kSupportedLanguages)
                  ChoiceChip(
                    label: Text(code == 'en' ? label : '$native  ·  $label'),
                    selected: _selectedLanguage == code,
                    selectedColor: const Color(0xFF0B4F3A)
                        .withValues(alpha: 0.18),
                    labelStyle: TextStyle(
                      color: _selectedLanguage == code
                          ? const Color(0xFF0B4F3A)
                          : const Color(0xFF334155),
                      fontWeight: _selectedLanguage == code
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                    side: BorderSide(
                      color: _selectedLanguage == code
                          ? const Color(0xFF0B4F3A)
                          : const Color(0xFFCBD5E1),
                    ),
                    onSelected: (_) => setState(() => _selectedLanguage = code),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed:
                    _isSavingLanguage ||
                        _selectedLanguage == AppLanguage.current
                    ? null
                    : _saveLanguage,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: _isSavingLanguage
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(tr('save')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userName = ApiSession.user['fullName'] as String? ?? 'Account';
    final identifier =
        ApiSession.user['emailNormalized'] as String? ??
        ApiSession.user['phoneE164'] as String? ??
        '';

    return AppShell(
      selectedTab: 4,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.passwordUpdated)
            Card(
              color: const Color(0xFFE6F4F1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('passwordUpdatedMsg'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(
                        context,
                      ).pushNamedAndRemoveUntil('/dashboard', (route) => false),
                      icon: const Icon(Icons.dashboard_outlined),
                      label: Text(tr('goToDashboard')),
                    ),
                  ],
                ),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _profileAvatar(
                    size: 56,
                    image: decodeDataImage(_profileImage),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ApiSession.user['fullName'] as String? ?? userName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          identifier.isEmpty ? tr('tapToEditName') : identifier,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: _editProfile,
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              label: Text(tr('editProfile')),
                            ),
                            TextButton.icon(
                              onPressed: _isSavingPhoto
                                  ? null
                                  : () async {
                                      final picked = await _pickImageDataUrl(
                                        maxBytes: 800000,
                                      );
                                      if (picked == null) return;
                                      setState(() => _profileImage = picked);
                                      await _saveProfilePhoto();
                                    },
                              icon: _isSavingPhoto
                                  ? const SizedBox.square(
                                      dimension: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.add_a_photo_outlined,
                                      size: 16,
                                    ),
                              label: Text(tr('changePhoto')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isOwner) ...[
            const SizedBox(height: 8),
            _buildPaymentSettingsCard(),
          ],
          const SizedBox(height: 8),
          _buildLanguageCard(),
          const SizedBox(height: 8),
          ExpansionTile(
            leading: const Icon(Icons.devices_outlined),
            title: Text(tr('activeSessions')),
            subtitle: Text(
              trf('activeSessionCount', {'n': '${_sessions.length}'}),
            ),
            children: [
              if (_sessions.isEmpty)
                ListTile(
                  leading: const Icon(Icons.hourglass_empty_outlined),
                  title: Text(tr('noActiveSessions')),
                )
              else
                for (final session in _sessions)
                  ListTile(
                    leading: Icon(
                      (session as Map<String, dynamic>)['current'] == true
                          ? Icons.smartphone
                          : Icons.devices_other,
                    ),
                    title: Text(
                      session['deviceLabel']?.toString() ?? 'this device',
                    ),
                    subtitle: Text(
                      session['current'] == true
                          ? tr('thisDevice')
                          : session['lastUsedAt']?.toString() ?? '',
                    ),
                  ),
            ],
          ),
          // Steps the account still has to complete (password, contact
          // verification, profile). The same list drives the banner, the
          // popup and the action-required emails.
          ListTile(
            leading: const Icon(Icons.assignment_turned_in_outlined),
            title: const Text('Account setup'),
            subtitle: const Text(
              'Finish the steps still required for your account',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/account-setup'),
          ),
          // Every email the app sent, with the template that triggered it and
          // whether the SMTP hand-off worked.
          ListTile(
            leading: const Icon(Icons.outbox_outlined),
            title: const Text('Email history'),
            subtitle: const Text(
              'Credentials, welcome and issue emails sent to you',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/email-history'),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: Text(tr('notifications')),
            subtitle: const Text('Show in-app activity notifications'),
            value: _notificationsEnabled,
            onChanged: (value) {
              setState(() => _notificationsEnabled = value);
              ApiSession.notificationsEnabled = value;
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_outlined),
            title: Text(tr('notificationSounds')),
            value: _notificationSoundsEnabled,
            onChanged: (value) {
              setState(() => _notificationSoundsEnabled = value);
              ApiSession.notificationSoundsEnabled = value;
            },
          ),
          // Subscription plan: owners pick from the catalog; the plan is
          // stored server-side and validated (never free-form).
          Card(
            child: ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: Text(tr('plan')),
              subtitle: Text(
                _currentPlan.isEmpty
                    ? 'Loading plan...'
                    : 'Current: $_currentPlan · Tap to change',
              ),
              trailing: _isSavingPlan
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _plans.isEmpty ? null : _openPlanPicker,
            ),
          ),
          ExpansionTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(tr('changePassword')),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    if (_error != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ),
                    TextFormField(
                      controller: _currentPasswordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: tr('currentPassword'),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? 'Show passwords'
                              : 'Hide passwords',
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      validator: (value) =>
                          value == null || value.isEmpty ? 'Required' : null,
                    ),
                    TextFormField(
                      controller: _newPasswordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(labelText: tr('newPassword')),
                      validator: _passwordValidator,
                    ),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: tr('confirmNewPassword'),
                      ),
                      validator: (value) => value != _newPasswordController.text
                          ? 'Passwords do not match'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _isLoading ? null : _changePassword,
                        child: _isLoading
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(tr('updatePassword')),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Owners report issues to the super admin; the super admin has no
          // one above them, so help stays an owner-side feature.
          if (_isAdmin)
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: const Text('Issue reports'),
              subtitle: const Text('Monitor and resolve owner reports'),
              onTap: () => Navigator.of(context).pushNamed('/admin-issues'),
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.report_problem_outlined),
              title: const Text('Report an issue'),
              subtitle: const Text('Tell the admin about a problem or bug'),
              onTap: () => Navigator.of(context).pushNamed('/issues'),
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: Text(tr('helpSupport')),
              onTap: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(tr('helpSupport')),
                  content: Text(tr('helpMsg')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(tr('close')),
                    ),
                  ],
                ),
              ),
            ),
          ],
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms of Use'),
            onTap: () => Navigator.of(context).pushNamed('/terms'),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            onTap: () => Navigator.of(context).pushNamed('/privacy'),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(tr('logOut')),
            onTap: _signOut,
          ),
        ],
      ),
    );
  }
}
