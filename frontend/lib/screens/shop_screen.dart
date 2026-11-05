import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api_session.dart';
import '../widgets/app_shell.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, required this.userRole, required this.shopId});

  final String userRole;
  final String? shopId;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  static const String _kApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  bool _isLoading = true;
  Map<String, dynamic>? _shopDetails;
  List<dynamic> _stockItems = [];

  @override
  void initState() {
    super.initState();
    _loadShopDetails();
    _loadStock();
  }

  Future<void> _loadShopDetails() async {
    try {
      final url = '$_kApiBaseUrl/api/shops/me';
      final response = await http
          .get(Uri.parse(url), headers: ApiSession.headers)
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final shop = data['shop'];
        if (mounted && shop is Map<String, dynamic>) {
          setState(() => _shopDetails = shop);
        }
      }
    } catch (e) {
      debugPrint('Failed to load shop details: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStock() async {
    try {
      final url = '$_kApiBaseUrl/api/inventory/items';
      final response = await http
          .get(Uri.parse(url), headers: ApiSession.headers)
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() => _stockItems = data['items'] as List<dynamic>? ?? []);
      }
    } catch (e) {
      debugPrint('Failed to load stock: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      selectedTab: 1,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0B4F3A)),
            )
          : _shopDetails == null
          ? const Center(child: Text('No shop data available'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Shop header
                  _buildShopHeader(),
                  const Divider(height: 32),
                  // Stock summary
                  if (_stockItems.isNotEmpty) ...[
                    const Text(
                      'Stock Summary',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._stockItems.map((item) => _buildStockItem(item)),
                    const SizedBox(height: 24),
                  ] else ...[
                    const Center(
                      child: Text(
                        'No stock items found. Add inventory to get started.',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF64748B),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildShopHeader() {
    if (_shopDetails == null) return const SizedBox.shrink();
    final shop = _shopDetails!;
    final address = shop['address'];
    final addressText =
        shop['shopAddress']?.toString() ??
        (address is Map<String, dynamic>
            ? [
                address['line1'],
                address['city'],
                address['state'],
                address['postalCode'],
              ].whereType<String>().where((part) => part.isNotEmpty).join(', ')
            : '');
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.storefront_rounded,
                  color: Color(0xFF0B4F3A),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop['shopName'] ?? 'My Pharmacy',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      if (addressText.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          addressText,
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(
                  Icons.grass_rounded,
                  color: Color(0xFF0B4F3A),
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  'Status: ${shop['status'] ?? 'Active'}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: shop['status'] == 'ACTIVE'
                        ? const Color(0xFF059669)
                        : const Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockItem(Map<String, dynamic> item) {
    final name = item['medicineName'] ?? 'Unknown';
    final quantity = item['quantity'] ?? '0';
    final lowStock = item['lowStock'] == true;

    return ListTile(
      leading: Icon(
        lowStock ? Icons.warning_rounded : Icons.inventory_rounded,
        color: lowStock ? const Color(0xFFDC2626) : const Color(0xFF0B4F3A),
      ),
      title: Text(
        name,
        style: const TextStyle(
          fontWeight: FontWeight.w500,
          color: Color(0xFF1E293B),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$quantity',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
          if (lowStock) ...[
            const SizedBox(width: 4),
            const Icon(
              Icons.remove_circle_rounded,
              color: Color(0xFFDC2626),
              size: 16,
            ),
          ] else ...[
            const SizedBox(width: 4),
            Icon(
              Icons.check_circle_rounded,
              color: const Color(0xFF059669),
              size: 16,
            ),
          ],
        ],
      ),
    );
  }
}
