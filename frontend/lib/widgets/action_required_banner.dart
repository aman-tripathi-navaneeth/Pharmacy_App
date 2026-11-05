import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api_session.dart';
import '../utils/app_sounds.dart';
import '../utils/toast.dart';

// The pending steps for the signed-in user. The same list drives the banner,
// the popup and the action-required emails on the server.
class ActionRequiredBanner extends StatefulWidget {
  const ActionRequiredBanner({super.key});

  @override
  State<ActionRequiredBanner> createState() => _ActionRequiredBannerState();
}

class _ActionRequiredBannerState extends State<ActionRequiredBanner> {
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  List<Map<String, dynamic>> _actions = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadActions();
  }

  /// Fetches the pending steps. Returns an empty list when nothing is due.
  Future<void> _loadActions() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_apiBaseUrl/api/notifications/action-required'),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>? ?? [];
      setState(() {
        _actions = items.whereType<Map<String, dynamic>>().toList(
          growable: false,
        );
        _loading = false;
      });
      if (_actions.isNotEmpty) {
        AppSounds.playAlert();
      }
    } catch (_) {
      setState(() {
        _actions = [];
        _loading = false;
      });
    }
  }

  IconData iconFor(String? severity) {
    switch (severity) {
      case 'HIGH':
        return Icons.priority_high_rounded;
      case 'MEDIUM':
        return Icons.info_outline_rounded;
      default:
        return Icons.check_circle_outline_rounded;
    }
  }

  void _open(String? route) {
    if (route == null || route.isEmpty) return;
    Navigator.of(context).pushNamed(route).then((_) => _loadActions());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (_actions.isEmpty) return const SizedBox.shrink();

    return Card(
      color: const Color(0xFFFFFBEB),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFFCD34D)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFB45309),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Action required (${_actions.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB45309),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(
                    Icons.refresh,
                    size: 18,
                    color: Color(0xFFB45309),
                  ),
                  onPressed: _loadActions,
                ),
              ],
            ),
            for (final action in _actions)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  iconFor(action['severity']?.toString()),
                  color: const Color(0xFFB45309),
                  size: 18,
                ),
                title: Text(
                  action['title']?.toString() ?? 'Action required',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  action['message']?.toString() ?? '',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: TextButton(
                  onPressed: () => _open(action['route']?.toString()),
                  child: const Text('Do it'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shows the pending steps in a modal popup. Safe to call on every screen.
Future<void> showActionRequiredPopup(BuildContext context) async {
  // Use the same base URL the banner uses.
  const base = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
  try {
    final response = await http
        .get(
          Uri.parse('$base/api/notifications/action-required'),
          headers: ApiSession.headers,
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200 || !context.mounted) return;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? [];
    if (items.isEmpty) return;
    if (!context.mounted) return;
    final selectedRoute = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.error_outline_rounded, color: Color(0xFFB45309)),
        title: const Text('Action required'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final action in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.priority_high_rounded,
                    color: const Color(0xFFB45309),
                  ),
                  title: Text(
                    action['title']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(action['message']?.toString() ?? ''),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              final route = items.first['route']?.toString();
              Navigator.of(dialogContext).pop(route);
            },
            child: const Text('Open now'),
          ),
        ],
      ),
    );
    if (selectedRoute != null && selectedRoute.isNotEmpty) {
      if (!context.mounted) return;
      Navigator.of(context).pushNamed(selectedRoute);
    }
  } catch (_) {
    if (context.mounted) {
      AppToast.show(
        context,
        'Could not load action required steps',
        success: false,
      );
    }
  }
}
