import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api_session.dart';
import '../utils/app_sounds.dart';

/// Full notifications feed: every message can be marked as read (individually
/// or all at once), unread entries are highlighted, and the header badge
/// resets when unread counts drop to zero.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  bool _isLoading = true;
  bool _markingAll = false;
  List<dynamic> _items = [];
  Map<String, bool> _unread = {};
  String? _error;

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
      final response = await http
          .get(
            Uri.parse('$_apiBaseUrl/api/notifications'),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('Could not load notifications (${response.statusCode})');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _items = items;
          _unread = {
            for (final item in items)
              (item as Map<String, dynamic>)['_id'].toString():
                  item['isRead'] == false,
          };
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not load notifications. Try again.');
      }
      debugPrint('Failed to load notifications: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _hasUnread => _unread.values.any((v) => v);

  Future<void> _markRead(String id) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/api/notifications/$id/read'),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        // Already read or missing: reflect success locally anyway.
        debugPrint('Mark-read returned ${response.statusCode}');
      }
      if (mounted) {
        setState(() => _unread[id] = false);
        AppSounds.playAlert();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Marked as read')),
        );
      }
    } catch (error) {
      debugPrint('Mark-read failed: $error');
      if (mounted) {
        AppSounds.playAlert();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update notification')),
        );
      }
    }
  }

  Future<void> _markAllRead() async {
    if (!_hasUnread) return;
    setState(() => _markingAll = true);
    try {
      await http
          .post(
            Uri.parse('$_apiBaseUrl/api/notifications/read-all'),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 8));
      if (mounted) {
        setState(() {
          for (final key in _unread.keys.toList()) {
            _unread[key] = false;
          }
        });
        AppSounds.playAlert();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'All notifications marked as read (${_items.length}).',
            ),
          ),
        );
      }
    } catch (error) {
      debugPrint('Mark-all-read failed: $error');
      if (mounted) {
        AppSounds.playAlert();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not mark notifications read')),
        );
      }
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  IconData _iconFor(String? type) {
    switch (type) {
      case 'SHOP':
        return Icons.storefront_rounded;
      case 'INVENTORY':
        return Icons.inventory_2_rounded;
      case 'BILL':
        return Icons.receipt_long_rounded;
      case 'UDHAAR':
        return Icons.handshake_outlined;
      case 'PAYMENT':
        return Icons.currency_rupee_rounded;
      case 'PROFILE':
        return Icons.person_rounded;
      case 'OWNER':
        return Icons.person_add_alt_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  String _timeLabel(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final DateTime? parsed = DateTime.tryParse(iso);
    if (parsed == null) return '';
    final diff = DateTime.now().difference(parsed);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_markingAll)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _hasUnread ? _markAllRead : null,
              child: const Text(
                'Mark all as read',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
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
          : _items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_none, size: 48),
                    SizedBox(height: 12),
                    Text('No notifications yet'),
                    Text('Activity from your shop will appear here.'),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                itemCount: _items.length,
                padding: const EdgeInsets.all(12),
                itemBuilder: (context, index) {
                  final item = _items[index] as Map<String, dynamic>;
                  final id = item['_id'].toString();
                  final bool isUnread = _unread[id] ?? false;
                  return Card(
                    elevation: isUnread ? 2 : 0,
                    color: isUnread
                        ? const Color(0xFFF0FDFA)
                        : Theme.of(context).cardColor,
                    child: ListTile(
                      leading: Icon(
                        _iconFor(item['type'] as String?),
                        color: isUnread
                            ? const Color(0xFF0B4F3A)
                            : Colors.grey,
                      ),
                      title: Text(
                        item['title']?.toString() ?? 'Notification',
                        style: TextStyle(
                          fontWeight: isUnread
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['message']?.toString() ?? ''),
                          const SizedBox(height: 4),
                          Text(
                            _timeLabel(item['createdAt'] as String?),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      trailing: isUnread
                          ? IconButton(
                              tooltip: 'Mark as read',
                              icon: const Icon(
                                Icons.mark_email_read_outlined,
                              ),
                              onPressed: () => _markRead(id),
                            )
                          : const Icon(
                              Icons.done_all_rounded,
                              color: Colors.grey,
                            ),
                      onTap: () {
                        if (isUnread) _markRead(id);
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }
}
