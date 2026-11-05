import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api_session.dart';
import '../l10n/strings.dart';
import '../utils/app_sounds.dart';

/// Shared app chrome used by every top-level screens:
/// - Header: app name, sales report (owner) and notification bell with badge
/// - Footer: Home, Shop/My Shop, Scan, Alerts, Settings; owners also get a
///   "+ New Bill" action directly above the footer
///
/// Tab indexes: 0 = Home, 1 = Shop (Shops for SUPER_ADMIN / My Shop for
/// SHOP_OWNER), 2 = Scan, 3 = Alerts, 4 = Settings. Pass -1 for screens that
/// should not highlight a footer destination.

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.body,
    required this.selectedTab,
    this.showBack = false,
    this.onSignOut,
    this.showNewBillCta = true,
  });

  final Widget body;
  final int selectedTab;
  final bool showBack;
  final void Function()? onSignOut;
  final bool showNewBillCta;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  int _unreadCount = 0;
  // -1 marks the very first fetch so it never plays sound by itself.
  int _lastKnownUnread = -1;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
    // Keep the badge and in-app alert fresh while the screen stays open.
    _pollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadUnreadCount(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUnreadCount() async {
    if (!ApiSession.notificationsEnabled ||
        ApiSession.accessToken == null) {
      setState(() => _unreadCount = 0);
      return;
    }
    try {
      final response = await http
          .get(
            Uri.parse('$_apiBaseUrl/api/notifications/unread-count'),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final count = data['count'] as int? ?? 0;
        final previous = _unreadCount;
        if (mounted) {
          setState(() => _unreadCount = count);
        }
        // Sound and popup only when fresh unread messages arrive after the
        // first load, so opening the app never fires a false alert.
        if (count > previous && _lastKnownUnread != -1) {
          AppSounds.playAlert();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(tr('newAlerts')),
                action: SnackBarAction(
                  label: tr('navAlerts'),
                  onPressed: _openNotifications,
                ),
              ),
            );
          }
        }
        _lastKnownUnread = count;
      }
    } catch (error) {
      debugPrint('Could not read unread count: $error');
    }
  }

  Future<void> _openNotifications() async {
    if (!ApiSession.notificationsEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('notificationsOff')),
          action: SnackBarAction(
            label: tr('navSettings'),
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ),
      );
      return;
    }
    // The offscreen route returns here after closing, so re-poll the badge.
    await Navigator.of(context).pushNamed('/notifications');
    _loadUnreadCount();
  }

  void _selectFooter(int index) {
    switch (index) {
      case 0:
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/dashboard', (route) => false);
      case 1:
        final String role = ApiSession.user['role'] as String? ?? '';
        Navigator.of(context).pushNamedAndRemoveUntil(
          role == 'SUPER_ADMIN' ? '/shops' : '/shop',
          (route) => false,
        );
      case 2:
        Navigator.of(context).pushNamed('/scan');
      case 3:
        _openNotifications();
      case 4:
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/settings', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String role = ApiSession.user['role'] as String? ?? '';
    final bool isAdmin = role == 'SUPER_ADMIN';
    final bool isOwner = role == 'SHOP_OWNER';

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(child: widget.body),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isOwner && widget.showNewBillCta)
            Container(
              color: Theme.of(context).cardColor,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pushNamed('/new-bill'),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New Bill'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0B4F3A),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
          NavigationBar(
            selectedIndex: widget.selectedTab.clamp(0, 4),
            onDestinationSelected: _selectFooter,
            destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard),
            label: tr('navHome'),
          ),
          NavigationDestination(
            icon: Icon(
              isAdmin ? Icons.storefront_outlined : Icons.store_outlined,
            ),
            selectedIcon:
                Icon(isAdmin ? Icons.storefront : Icons.store),
            label: isAdmin ? tr('navShops') : tr('navMyShop'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.qr_code_scanner_outlined),
            selectedIcon: const Icon(Icons.qr_code_scanner),
            label: tr('navScan'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.notifications_outlined),
            selectedIcon: const Icon(Icons.notifications),
            label: tr('navAlerts'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: tr('navSettings'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final String role = ApiSession.user['role'] as String? ?? '';
    return Material(
      color: const Color(0xFF0B4F3A),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              if (widget.showBack)
                IconButton(
                  tooltip: tr('back'),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              const SizedBox(width: 4),
              const Icon(Icons.local_pharmacy_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('appTitle'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (role == 'SHOP_OWNER')
                IconButton(
                  tooltip: 'Sales report',
                  icon: const Icon(Icons.insights_rounded, color: Colors.white),
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/sales-report'),
                ),
              IconButton(
                tooltip: tr('notifications'),
                icon: Badge.count(
                  isLabelVisible: _unreadCount > 0,
                  count: _unreadCount,
                  backgroundColor: const Color(0xFFDC2626),
                  child: const Icon(
                    Icons.notifications_outlined,
                    color: Colors.white,
                  ),
                ),
                onPressed: _openNotifications,
              ),
              if (widget.onSignOut != null)
                IconButton(
                  tooltip: tr('signOut'),
                  icon: const Icon(Icons.logout, color: Colors.white),
                  onPressed: widget.onSignOut,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
