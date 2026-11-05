import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../api_session.dart';
import 'shop_details_screen.dart';

class CreateShopScreen extends StatefulWidget {
  final Function(String shopId, String shopName)? onShopCreated;

  const CreateShopScreen({super.key, this.onShopCreated});

  @override
  State<CreateShopScreen> createState() => _CreateShopScreenState();
}

class _CreateShopScreenState extends State<CreateShopScreen> {
  final _formKey = GlobalKey<FormState>();
  final _shopNameController = TextEditingController();
  final _licenseController = TextEditingController();
  final _shopPhoneController = TextEditingController();
  final _shopEmailController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _ownerEmailController = TextEditingController();
  final _ownerPhoneController = TextEditingController();
  final _addressLine1Controller = TextEditingController();
  final _addressLine2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _postalCodeController = TextEditingController();

  bool _isLoading = false;
  String? _error;
  String? _successMessage;
  String? _tempPassword;
  String? _createdShopId;
  String? _ownerLogin;
  String? _activationStatus;

  static const String _kApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  @override
  void dispose() {
    _shopNameController.dispose();
    _licenseController.dispose();
    _shopPhoneController.dispose();
    _shopEmailController.dispose();
    _ownerNameController.dispose();
    _ownerEmailController.dispose();
    _ownerPhoneController.dispose();
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _postalCodeController.dispose();
    super.dispose();
  }

  Future<void> _createShop() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _successMessage = null;
      _tempPassword = null;
      _activationStatus = null;
    });

    try {
      final response = await http
          .post(
            Uri.parse('$_kApiBaseUrl/api/admin/shops'),
            headers: ApiSession.headers,
            body: jsonEncode({
              'shopName': _shopNameController.text.trim(),
              'addressLine1': _addressLine1Controller.text.trim(),
              'addressLine2': _addressLine2Controller.text.trim().isEmpty
                  ? null
                  : _addressLine2Controller.text.trim(),
              'city': _cityController.text.trim(),
              'state': _stateController.text.trim(),
              'postalCode': _postalCodeController.text.trim(),
              'shopPhone': _shopPhoneController.text.trim(),
              'shopEmail': _shopEmailController.text.trim().isEmpty
                  ? null
                  : _shopEmailController.text.trim(),
              'ownerFullName': _ownerNameController.text.trim(),
              'ownerContact': _ownerEmailController.text.trim().isEmpty
                  ? _ownerPhoneController.text.trim()
                  : _ownerEmailController.text.trim(),
              'licenceNumber': _licenseController.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final shop = data['shop'] as Map<String, dynamic>?;
        setState(() {
          _successMessage =
              'Shop "${shop?['shopName'] ?? 'Unknown'}" created successfully!';
          _tempPassword = data['devTempPassword'] as String?;
          _activationStatus = data['activationStatus'] as String?;
          _createdShopId = shop?['_id'] as String?;
          _ownerLogin = _ownerEmailController.text.trim().isNotEmpty
              ? _ownerEmailController.text.trim()
              : _ownerPhoneController.text.trim();
        });
        widget.onShopCreated?.call(
          shop?['_id'] as String? ?? '',
          shop?['shopName'] as String? ?? 'Unknown',
        );
        if (ApiSession.notificationSoundsEnabled) {
          SystemSound.play(SystemSoundType.alert);
        }
      } else {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final message = data['message'];
        setState(
          () => _error = message is String ? message : 'Failed to create shop',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Connection error. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _resetForm() {
    for (final controller in [
      _shopNameController,
      _licenseController,
      _shopPhoneController,
      _shopEmailController,
      _ownerNameController,
      _ownerEmailController,
      _ownerPhoneController,
      _addressLine1Controller,
      _addressLine2Controller,
      _cityController,
      _stateController,
      _postalCodeController,
    ]) {
      controller.clear();
    }
    setState(() {
      _error = null;
      _successMessage = null;
      _tempPassword = null;
      _createdShopId = null;
      _ownerLogin = null;
      _activationStatus = null;
    });
  }

  Widget _pairedFields(Widget first, Widget second) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 12), second],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('Create New Shop'),
        backgroundColor: const Color(0xFF0B4F3A),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Success/Error Messages
              if (_successMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _successMessage!,
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_tempPassword != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B4F3A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Temporary Password for Owner:',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              _tempPassword!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copy temporary password',
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              await Clipboard.setData(
                                ClipboardData(text: _tempPassword!),
                              );
                              if (mounted) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Temporary password copied'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.copy, color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Share this with the owner. They must change it on first login.',
                        style: TextStyle(
                          color: Color(0xFFB8D4E3),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_activationStatus == 'DELIVERY_NOT_CONFIGURED')
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFB45309),
                  ),
                  title: Text('Owner credential delivery is not configured'),
                  subtitle: Text(
                    'Configure a verified email or SMS provider before creating production owner accounts.',
                  ),
                ),
              if (_createdShopId != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Shop ID'),
                  subtitle: SelectableText(_createdShopId!),
                ),
              if (_ownerLogin != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Owner login'),
                  subtitle: SelectableText(_ownerLogin!),
                ),
              if (_successMessage != null)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _createdShopId == null
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    ShopDetailsScreen(storeId: _createdShopId!),
                              ),
                            ),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('View Shop'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pushNamed('/shops'),
                      icon: const Icon(Icons.storefront_outlined),
                      label: const Text('View All Shops'),
                    ),
                    TextButton.icon(
                      onPressed: _resetForm,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Another'),
                    ),
                  ],
                ),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              const Text(
                'Shop Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              _pairedFields(
                TextFormField(
                  controller: _shopNameController,
                  decoration: const InputDecoration(
                    labelText: 'Shop Name *',
                    hintText: 'e.g. Green Valley Pharmacy',
                    prefixIcon: Icon(Icons.storefront_rounded),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter shop name';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: _licenseController,
                  decoration: const InputDecoration(
                    labelText: 'License ID *',
                    hintText: 'e.g. DL-123456',
                    prefixIcon: Icon(Icons.business_rounded),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter license ID';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 12),
              _pairedFields(
                TextFormField(
                  controller: _shopPhoneController,
                  decoration: const InputDecoration(
                    labelText: 'Shop Phone *',
                    hintText: 'e.g. +919876543210',
                    prefixIcon: Icon(Icons.phone_rounded),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter shop phone';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: _shopEmailController,
                  decoration: const InputDecoration(
                    labelText: 'Shop Email',
                    hintText: 'e.g. shop@pharmacy.com',
                    prefixIcon: Icon(Icons.email_rounded),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Owner Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ownerNameController,
                decoration: const InputDecoration(
                  labelText: "Owner's Full Name *",
                  hintText: 'e.g. Ravi Kumar',
                  prefixIcon: Icon(Icons.person_rounded),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Please enter owner's name";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _pairedFields(
                TextFormField(
                  controller: _ownerEmailController,
                  decoration: const InputDecoration(
                    labelText: "Owner's Email *",
                    hintText: 'e.g. owner@pharmacy.com',
                    prefixIcon: Icon(Icons.email_rounded),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      if (_ownerPhoneController.text.trim().isEmpty) {
                        return "Please enter owner's email or phone";
                      }
                      return null;
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: _ownerPhoneController,
                  decoration: const InputDecoration(
                    labelText: "Owner's Phone",
                    hintText: 'e.g. +919876543210',
                    prefixIcon: Icon(Icons.phone_rounded),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Shop Address',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressLine1Controller,
                decoration: const InputDecoration(
                  labelText: 'Address *',
                  hintText: 'Enter shop address',
                  prefixIcon: Icon(Icons.location_on_rounded),
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter shop address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cityController,
                      decoration: const InputDecoration(
                        labelText: 'City *',
                        hintText: 'e.g. Hyderabad',
                        prefixIcon: Icon(Icons.location_city_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter city';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _stateController,
                      decoration: const InputDecoration(
                        labelText: 'State *',
                        hintText: 'e.g. Telangana',
                        prefixIcon: Icon(Icons.location_on_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter state';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _postalCodeController,
                      decoration: const InputDecoration(
                        labelText: 'PIN Code *',
                        hintText: 'e.g. 500001',
                        prefixIcon: Icon(Icons.pin_rounded),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter PIN code';
                        }
                        if (value.trim().length < 5 ||
                            value.trim().length > 10) {
                          return 'PIN code must be 5-10 digits';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        _shopNameController.clear();
                        _licenseController.clear();
                        _shopPhoneController.clear();
                        _shopEmailController.clear();
                        _ownerNameController.clear();
                        _ownerEmailController.clear();
                        _ownerPhoneController.clear();
                        _addressLine1Controller.clear();
                        _addressLine2Controller.clear();
                        _cityController.clear();
                        _stateController.clear();
                        _postalCodeController.clear();
                        setState(() {
                          _error = null;
                          _successMessage = null;
                          _tempPassword = null;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      child: _isLoading
                          ? const CircularProgressIndicator(
                              color: Color(0xFF0B4F3A),
                            )
                          : ElevatedButton(
                              onPressed: _createShop,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0B4F3A),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                'Create Shop',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
