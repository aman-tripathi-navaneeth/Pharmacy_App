import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../api_session.dart';
import '../utils/responsive.dart';

class ShopDetailsScreen extends StatefulWidget {
  const ShopDetailsScreen({super.key, required this.storeId});

  final String storeId;

  @override
  State<ShopDetailsScreen> createState() => _ShopDetailsScreenState();
}

class _ShopDetailsScreenState extends State<ShopDetailsScreen> {
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _shop;
  Map<String, dynamic>? _owner;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await http
          .get(
            Uri.parse('$_apiBaseUrl/api/admin/shops/${widget.storeId}'),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('Could not load shop details (${response.statusCode})');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _shop = data['shop'] as Map<String, dynamic>?;
          _owner = data['owner'] as Map<String, dynamic>?;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not load shop details. Try again.');
      }
      debugPrint('Failed to load shop details: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editShop() async {
    final shop = _shop;
    if (shop == null) return;
    final address = shop['address'] as Map<String, dynamic>? ?? {};
    final nameController = TextEditingController(
      text: shop['shopName']?.toString(),
    );
    final line1Controller = TextEditingController(
      text: address['line1']?.toString(),
    );
    final line2Controller = TextEditingController(
      text: address['line2']?.toString(),
    );
    final cityController = TextEditingController(
      text: address['city']?.toString(),
    );
    final stateController = TextEditingController(
      text: address['state']?.toString(),
    );
    final postalController = TextEditingController(
      text: address['postalCode']?.toString(),
    );
    final phoneController = TextEditingController(
      text: shop['phoneE164']?.toString(),
    );
    final emailController = TextEditingController(
      text: shop['emailNormalized']?.toString(),
    );
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit shop'),
        content: SizedBox(
          width: dialogWidth(dialogContext, 440),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _editField(nameController, 'Shop name'),
                  _editField(line1Controller, 'Address line 1'),
                  _editField(
                    line2Controller,
                    'Address line 2',
                    required: false,
                  ),
                  _editField(cityController, 'City'),
                  _editField(stateController, 'State'),
                  _editField(postalController, 'PIN code'),
                  _editField(phoneController, 'Shop phone'),
                  _editField(emailController, 'Shop email', required: false),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogContext).pop(true);
              }
            },
            child: const Text('Save changes'),
          ),
        ],
      ),
    );

    if (saved == true) {
      try {
        final response = await http
            .patch(
              Uri.parse('$_apiBaseUrl/api/admin/shops/${widget.storeId}'),
              headers: ApiSession.headers,
              body: jsonEncode({
                'shopName': nameController.text.trim(),
                'addressLine1': line1Controller.text.trim(),
                'addressLine2': line2Controller.text.trim().isEmpty
                    ? null
                    : line2Controller.text.trim(),
                'city': cityController.text.trim(),
                'state': stateController.text.trim(),
                'postalCode': postalController.text.trim(),
                'phone': phoneController.text.trim(),
                'email': emailController.text.trim().isEmpty
                    ? null
                    : emailController.text.trim(),
              }),
            )
            .timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) {
          throw Exception(
            'Could not save shop changes (${response.statusCode})',
          );
        }
        await _loadDetails();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Shop details updated')));
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Update failed: $error')));
        }
      }
    }

    nameController.dispose();
    line1Controller.dispose();
    line2Controller.dispose();
    cityController.dispose();
    stateController.dispose();
    postalController.dispose();
    phoneController.dispose();
    emailController.dispose();
  }

  Widget _editField(
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
                  value == null || value.trim().isEmpty ? 'Required' : null
            : null,
      ),
    );
  }

  Future<void> _reissueAccess() async {
    try {
      final response = await http
          .post(
            Uri.parse(
              '$_apiBaseUrl/api/admin/shops/${widget.storeId}/reissue-access',
            ),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 12));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(data['message'] ?? 'Could not reissue access');
      }
      final password = data['devTempPassword']?.toString();
      final destination = data['destination']?.toString() ?? 'owner';
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.key_rounded, color: Color(0xFF0B4F3A)),
          title: const Text('Owner login reissued'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('A temporary password was issued for $destination.'),
              if (password != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    password,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The owner must change it after signing in. It is only shown in development mode.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ],
          ),
          actions: [
            if (password != null)
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: password));
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text('Temporary password copied'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy'),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      await _loadDetails();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Reissue failed: $error')));
      }
    }
  }

  Future<void> _toggleShopStatus() async {
    final currentStatus = _shop?['status']?.toString();
    final nextStatus = currentStatus == 'ACTIVE' ? 'SUSPENDED' : 'ACTIVE';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          nextStatus == 'ACTIVE' ? 'Activate shop?' : 'Suspend shop?',
        ),
        content: Text(
          nextStatus == 'ACTIVE'
              ? 'The owner will be able to use this shop again.'
              : 'The shop record will remain saved, but the account will be suspended.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(nextStatus == 'ACTIVE' ? 'Activate' : 'Suspend'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final response = await http
          .patch(
            Uri.parse('$_apiBaseUrl/api/admin/shops/${widget.storeId}/status'),
            headers: ApiSession.headers,
            body: jsonEncode({'status': nextStatus}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception(
          'Could not change shop status (${response.statusCode})',
        );
      }
      await _loadDetails();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Shop ${nextStatus.toLowerCase()}')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Status update failed: $error')));
      }
    }
  }

  Widget _detail(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: const TextStyle(fontSize: 15, color: Color(0xFF1E293B)),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: const Color(0xFF0B4F3A)),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0B4F3A),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return raw;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}, '
        '${parsed.hour.toString().padLeft(2, '0')}:'
        '${parsed.minute.toString().padLeft(2, '0')}';
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'ACTIVE':
        return const Color(0xFF1F7A45);
      case 'SUSPENDED':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFFB45309);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = _shop;
    final owner = _owner;
    final address = shop?['address'] as Map<String, dynamic>? ?? {};
    final licence = shop?['licenceDetails'] as Map<String, dynamic>? ?? {};
    final String status = shop?['status']?.toString() ?? 'UNKNOWN';

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(title: const Text('Shop details')),
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
                    onPressed: _loadDetails,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ---- Status banner -------------------------------------
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B4F3A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shop?['shopName']?.toString() ?? 'Medical shop',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: _statusColor(status),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                status,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // ---- Owner actions -------------------------------------
                if (ApiSession.user['role'] == 'SUPER_ADMIN')
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _editShop,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit shop'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _toggleShopStatus,
                        icon: Icon(
                          shop?['status'] == 'ACTIVE'
                              ? Icons.pause_circle_outline
                              : Icons.play_circle_outline,
                        ),
                        label: Text(
                          shop?['status'] == 'ACTIVE' ? 'Suspend' : 'Activate',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _reissueAccess,
                        icon: const Icon(Icons.key_rounded),
                        label: const Text('Reissue owner login'),
                      ),
                    ],
                  ),
                if (ApiSession.user['role'] == 'SUPER_ADMIN')
                  const SizedBox(height: 4),
                // ---- Owner section -------------------------------------
                _sectionCard(
                  title: 'Owner & access',
                  icon: Icons.person_outline,
                  children: [
                    _detail('Owner', owner?['fullName']?.toString()),
                    _detail(
                      'Owner login',
                      owner?['emailNormalized']?.toString() ??
                          owner?['phoneE164']?.toString(),
                    ),
                    _detail('Owner status', owner?['status']?.toString()),
                    _detail(
                      'Password setup',
                      owner?['mustChangePassword'] == true
                          ? 'Temporary password pending'
                          : 'Owner password set',
                    ),
                    _detail('Shop ID', shop?['_id']?.toString()),
                  ],
                ),
                // ---- Contact & address section --------------------------
                _sectionCard(
                  title: 'Contact & address',
                  icon: Icons.location_on_outlined,
                  children: [
                    _detail('Shop phone', shop?['phoneE164']?.toString()),
                    _detail('Shop email', shop?['emailNormalized']?.toString()),
                    _detail(
                      'Address',
                      [
                            address['line1'],
                            address['line2'],
                            address['city'],
                            address['state'],
                            address['postalCode'],
                            address['country'],
                          ]
                          .where(
                            (part) =>
                                part != null && part.toString().isNotEmpty,
                          )
                          .join(', '),
                    ),
                  ],
                ),
                // ---- Licence & meta section -------------------------------
                _sectionCard(
                  title: 'Licence & registration',
                  icon: Icons.verified_outlined,
                  children: [
                    _detail('Drug licence', licence['number']?.toString()),
                    _detail(
                      'Created',
                      _formatDate(shop?['createdAt']?.toString()),
                    ),
                    _detail(
                      'Last updated',
                      _formatDate(shop?['updatedAt']?.toString()),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
