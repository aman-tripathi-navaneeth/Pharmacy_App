import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api_session.dart';
import '../widgets/app_shell.dart';
import 'shop_details_screen.dart';

class ShopListScreen extends StatefulWidget {
  const ShopListScreen({super.key});

  @override
  State<ShopListScreen> createState() => _ShopListScreenState();
}

class _ShopListScreenState extends State<ShopListScreen> {
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _shops = [];
  String _status = 'ALL';
  int _page = 1;
  int _pageSize = 20;
  int _total = 0;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadShops();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadShops() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final query = <String, String>{
      'page': '$_page',
      'pageSize': '$_pageSize',
      if (_searchController.text.trim().isNotEmpty)
        'search': _searchController.text.trim(),
      if (_status != 'ALL') 'status': _status,
    };
    try {
      final uri = Uri.parse('$_apiBaseUrl/api/admin/shops')
          .replace(queryParameters: query);
      final response = await http
          .get(uri, headers: ApiSession.headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('Could not load shops (${response.statusCode})');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _shops = (data['items'] as List<dynamic>? ?? [])
              .map((e) => e as Map<String, dynamic>)
              .toList();
          _total = data['total'] as int? ?? 0;
          _pageSize = data['pageSize'] as int? ?? _pageSize;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load shops. Try again.');
      debugPrint('Failed to load shop list: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openDetails(dynamic shop) {
    final storeId = shop is Map<String, dynamic>
        ? shop['_id']?.toString()
        : null;
    if (storeId == null || storeId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ShopDetailsScreen(storeId: storeId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = (_total / _pageSize).ceil().clamp(1, 1 << 30);
    return AppShell(
      selectedTab: 1,
      showBack: true,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(context).pushNamed('/create-shop');
                  _loadShops();
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add New Shop'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) {
                    _page = 1;
                    _loadShops();
                  },
                  decoration: InputDecoration(
                    labelText: 'Search shops',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'Search',
                      onPressed: () {
                        _page = 1;
                        _loadShops();
                      },
                      icon: const Icon(Icons.arrow_forward),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: DropdownButton<String>(
                    value: _status,
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _status = value;
                        _page = 1;
                      });
                      _loadShops();
                    },
                    items: const [
                      DropdownMenuItem(
                        value: 'ALL',
                        child: Text('All statuses'),
                      ),
                      DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                      DropdownMenuItem(
                        value: 'PENDING',
                        child: Text('Pending'),
                      ),
                      DropdownMenuItem(
                        value: 'SUSPENDED',
                        child: Text('Suspended'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: FilledButton.icon(
                      onPressed: _loadShops,
                      icon: const Icon(Icons.refresh),
                      label: Text(_error!),
                    ),
                  )
                : _shops.isEmpty
                ? const Center(child: Text('No shops found'))
                : ListView.builder(
                    itemCount: _shops.length,
                    itemBuilder: (context, index) {
                      final shop = _shops[index];
                      return _ShopCard(
                        key: ValueKey(shop['_id']),
                        shop: shop,
                        onTap: () => _openDetails(shop),
                      );
                    },
                  ),
          ),
          if (!_isLoading && _error == null)
            SafeArea(
              top: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Previous page',
                    onPressed: _page > 1
                        ? () {
                            setState(() => _page--);
                            _loadShops();
                          }
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('Page $_page of $pageCount'),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: _page < pageCount
                        ? () {
                            setState(() => _page++);
                            _loadShops();
                          }
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ShopCard extends StatelessWidget {
  final Map<String, dynamic> shop;
  final VoidCallback onTap;

  const _ShopCard({super.key, required this.shop, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final shopName = shop['name'] ?? 'Unknown Shop';
    final shopId = shop['_id']?.toString() ?? '';

    return Card(
      key: ValueKey(shop['_id']),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Shop icon/logo
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.storefront,
                  size: 24,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              // Shop info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shopName,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Shop ID: $shopId',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
