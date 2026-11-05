import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api_session.dart';
import '../widgets/app_shell.dart';

/// Super admin history screen: every owner login, logout, password change,
/// shop operation, and inventory action is stored server-side and shown here.
class AdminHistoryScreen extends StatefulWidget {
  const AdminHistoryScreen({super.key, required this.title, this.ownerOnly = false});

  final String title;
  final bool ownerOnly;

  @override
  State<AdminHistoryScreen> createState() => _AdminHistoryScreenState();
}

class _AdminHistoryScreenState extends State<AdminHistoryScreen> {
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  bool _isLoading = true;
  List<dynamic> _items = [];
  String? _error;
  String? _selectedUserId;
  String? _selectedAction;

  static const List<String> _actionFilters = [
    'ALL',
    'auth.login',
    'auth.logout',
    'auth.changePassword',
    'auth.changeTemporaryPassword',
    'admin.shops.create',
    'admin.shops.status',
    'inventory.item.create',
    'inventory.item.update',
    'inventory.item.archive',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final query = <String, String>{
        'limit': '100',
        if (_selectedUserId != null && _selectedUserId!.isNotEmpty)
          'userId': _selectedUserId!,
        if (_selectedAction != null &&
            _selectedAction!.isNotEmpty &&
            _selectedAction != 'ALL')
          'action': _selectedAction!,
      };
      final uri = Uri.parse('$_apiBaseUrl/api/audit')
          .replace(queryParameters: query);
      final response = await http
          .get(uri, headers: ApiSession.headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('Could not load history (${response.statusCode})');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _items = widget.ownerOnly
              ? items
                  .where((item) =>
                      (item as Map<String, dynamic>)['actorRole'] ==
                      'SHOP_OWNER')
                  .toList()
              : items;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not load history. Try again.');
      }
      debugPrint('Failed to load audit history: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  IconData _iconFor(String? action) {
    switch (action) {
      case 'auth.login':
        return Icons.login_rounded;
      case 'auth.logout':
        return Icons.logout_rounded;
      case 'auth.changePassword':
      case 'auth.changeTemporaryPassword':
        return Icons.password_rounded;
      case 'admin.shops.create':
      case 'admin.shops.status':
        return Icons.storefront_rounded;
      default:
        return Icons.history_rounded;
    }
  }

  Color _colorFor(String? result) {
    switch (result) {
      case 'SUCCESS':
        return const Color(0xFF059669);
      case 'DENIED':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFFDC2626);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      selectedTab: -1,
      showBack: true,
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
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'All activity is stored on the server audit log '
                    '(${_items.length} entries shown).',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      DropdownButton<String>(
                        value: _selectedAction ?? 'ALL',
                        hint: const Text('Filter by action'),
                        onChanged: (value) {
                          setState(() => _selectedAction = value);
                          _load();
                        },
                        items: [
                          for (final action in _actionFilters)
                            DropdownMenuItem(
                              value: action,
                              child: Text(
                                action == 'ALL' ? 'All actions' : action,
                              ),
                            ),
                        ],
                      ),
                      DropdownButton<String>(
                        value: _selectedUserId,
                        hint: const Text('Filter by user'),
                        onChanged: (value) {
                          setState(() => _selectedUserId = value);
                          _load();
                        },
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('All users'),
                          ),
                          for (final item in _items)
                            DropdownMenuItem(
                              value:
                                  (item as Map<String, dynamic>)['actorUserId']
                                      ?.toString(),
                              child: Text(
                                '${item['actorUserId']}'.substring(0, 10),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('No history found')),
                    )
                  else
                    for (final item in _items) ...[
                      Card(
                        child: ListTile(
                          leading: Icon(
                            _iconFor(item['action'] as String?),
                          ),
                          title: Text(
                            item['action']?.toString() ?? 'Activity',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${item['actorRole']} · ${item['timestamp']?.toString().substring(0, 19) ?? ''}'
                            '${item['storeId'] != null ? ' · shop ${item['storeId']}' : ''}',
                          ),
                          trailing: Chip(
                            label: Text(
                              item['result']?.toString() ?? '',
                              style: TextStyle(
                                color: _colorFor(item['result'] as String?),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                ],
              ),
            ),
    );
  }
}
