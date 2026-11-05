import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api_session.dart';
import '../l10n/strings.dart';
import '../utils/app_sounds.dart';
import '../utils/toast.dart';
import '../utils/report_exporter.dart';
import '../widgets/app_shell.dart';
import '../widgets/action_required_banner.dart';
import 'shop_details_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.userRole,
    required this.userName,
  });

  final String userRole;
  final String userName;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  bool _isLoading = true;
  Map<String, dynamic>? _shopStats;
  List<dynamic> _recentShops = [];
  Map<String, int> _ownerStats = {};
  String? _error;
  String? _ownerShopName;

  @override
  void initState() {
    super.initState();
    if (widget.userRole == 'SUPER_ADMIN') {
      _loadDashboard();
    } else {
      _loadOwnerStats();
    }
  }

  Future<void> _loadOwnerStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final responses = await Future.wait([
        http
            .get(
              Uri.parse('$_apiBaseUrl/api/inventory/items'),
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
      final response = responses[0];
      if (response.statusCode != 200) {
        throw Exception('Could not load inventory');
      }
      // The owner's own shop name heads the dashboard.
      if (responses[1].statusCode == 200) {
        final shopData = jsonDecode(responses[1].body) as Map<String, dynamic>;
        final shop = shopData['shop'];
        if (shop is Map<String, dynamic>) {
          _ownerShopName = shop['shopName']?.toString();
        }
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>? ?? [];
      int lowStock = 0;
      int expiringSoon = 0;
      final now = DateTime.now();
      for (final raw in items) {
        final item = raw as Map<String, dynamic>;
        final qty = (item['quantity'] as num?)?.toInt() ?? 0;
        final reorder = (item['reorderLevel'] as num?)?.toInt() ?? 0;
        if (qty <= reorder) lowStock++;
        final expiry = DateTime.tryParse(item['expiryDate']?.toString() ?? '');
        if (expiry != null &&
            expiry.isBefore(now.add(const Duration(days: 30)))) {
          expiringSoon++;
        }
      }
      if (mounted) {
        setState(() {
          _ownerStats = {
            'items': items.length,
            'lowStock': lowStock,
            'expiringSoon': expiringSoon,
          };
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = tr('ownerStatsError'));
      }
      debugPrint('Failed to load owner stats: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _exportShopsReport(bool asPdf) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final response = await http
          .get(
            Uri.parse('$_apiBaseUrl/api/admin/shops?page=1&pageSize=100'),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('Could not fetch shops for report');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final shops = data['items'] as List<dynamic>? ?? [];
      final rows = <List<String>>[
        for (final raw in shops)
          [
            (raw as Map<String, dynamic>)['_id']?.toString() ?? '',
            raw['shopName']?.toString() ?? '',
            raw['status']?.toString() ?? '',
            raw['phoneE164']?.toString() ?? '',
            raw['createdAt']?.toString().substring(0, 10) ?? '',
          ],
      ];
      final headers = ['Shop ID', 'Name', 'Status', 'Phone', 'Created'];
      if (asPdf) {
        await ReportExporter.exportPdfWithMessenger(
          messenger,
          fileName: 'shops-report',
          title: 'Shops Report (${shops.length} shops)',
          headers: headers,
          rows: rows,
        );
      } else {
        await ReportExporter.exportExcelWithMessenger(
          messenger,
          fileName: 'shops-report',
          sheetName: 'Shops',
          headers: headers,
          rows: rows,
        );
      }
      AppSounds.playAlert();
      if (mounted) AppToast.show(context, tr('reportBuilt'));
    } catch (error) {
      debugPrint('Export failed: $error');
      if (mounted) {
        AppToast.show(context, tr('reportFailed'), success: false);
      } else {
        messenger.showSnackBar(SnackBar(content: Text(tr('reportFailed'))));
      }
    }
  }

  Future<void> _exportDatabaseJson() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final response = await http
          .get(
            Uri.parse('$_apiBaseUrl/api/admin/export'),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw Exception('Could not export the database');
      }
      await FileSaver.instance.saveFile(
        name: 'medishop-export',
        bytes: Uint8List.fromList(utf8.encode(response.body)),
        fileExtension: 'json',
        mimeType: MimeType.json,
      );
      if (mounted) AppToast.show(context, tr('reportBuilt'));
    } catch (error) {
      debugPrint('Database export failed: $error');
      messenger.showSnackBar(SnackBar(content: Text(tr('reportFailed'))));
    }
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final responses = await Future.wait([
        http
            .get(
              Uri.parse('$_apiBaseUrl/api/admin/stats'),
              headers: ApiSession.headers,
            )
            .timeout(const Duration(seconds: 6)),
        http
            .get(
              Uri.parse('$_apiBaseUrl/api/admin/shops?page=1&pageSize=5'),
              headers: ApiSession.headers,
            )
            .timeout(const Duration(seconds: 6)),
      ]);
      if (responses.any((response) => response.statusCode != 200)) {
        throw Exception('Dashboard request failed');
      }
      final stats = jsonDecode(responses[0].body) as Map<String, dynamic>;
      final shopList = jsonDecode(responses[1].body) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _shopStats = stats;
          _recentShops = shopList['items'] as List<dynamic>? ?? [];
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = tr('dashboardLoadError'));
      }
      debugPrint('Failed to load dashboard: $error');
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
    } catch (error) {
      debugPrint('Sign out request failed: $error');
    } finally {
      ApiSession.clear();
      AppFlash.set(tr('loggedOut'));
      if (mounted) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/login', (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      selectedTab: 0,
      onSignOut: _signOut,
      body: widget.userRole == 'SHOP_OWNER'
          ? _buildOwnerDashboard()
          : _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _loadDashboard,
                    icon: const Icon(Icons.refresh),
                    label: Text(tr('retry')),
                  ),
                ],
              ),
            )
          : _buildAdminDashboard(),
    );
  }

  void _openShopDetails(dynamic shop) {
    if (shop is! Map<String, dynamic>) return;
    final storeId = shop['_id']?.toString();
    if (storeId == null || storeId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ShopDetailsScreen(storeId: storeId),
      ),
    );
  }

  Widget _buildOwnerDashboard() {
    final actions = [
      (tr('navMyShop'), Icons.storefront_rounded, '/shop'),
      (tr('prescriptions'), Icons.medical_services_rounded, '/prescriptions'),
      (tr('inventory'), Icons.inventory_2_rounded, '/inventory'),
      ('Report an issue', Icons.report_problem_rounded, '/issues'),
    ];
    final stats = _ownerStats;
    return RefreshIndicator(
      onRefresh: _loadOwnerStats,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ActionRequiredBanner(),
          Text(
            '${tr('yourPharmacy')}: ${_ownerShopName ?? widget.userName}',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              // Three across on tablets/desktop, stacked on narrow phones so
              // the labels never collide.
              final threeAcross = constraints.maxWidth >= 520;
              final cardWidth = threeAcross
                  ? (constraints.maxWidth - 24) / 3
                  : constraints.maxWidth;
              final cards = [
                _buildStatCard(
                  tr('stockItems'),
                  stats['items']?.toString() ?? '-',
                  Icons.inventory_2_rounded,
                  const Color(0xFF0B4F3A),
                ),
                _buildStatCard(
                  tr('lowStock'),
                  stats['lowStock']?.toString() ?? '-',
                  Icons.warning_rounded,
                  const Color(0xFFDC2626),
                ),
                _buildStatCard(
                  tr('expiringSoon'),
                  stats['expiringSoon']?.toString() ?? '-',
                  Icons.event_busy_rounded,
                  const Color(0xFFD97706),
                ),
              ];
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final card in cards)
                    SizedBox(width: cardWidth, child: card),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            tr('stockHealth'),
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(height: 220, child: _buildOwnerStockPie(stats)),
            ),
          ),
          const SizedBox(height: 16),
          for (final action in actions)
            Card(
              child: ListTile(
                leading: Icon(action.$2, color: const Color(0xFF0B4F3A)),
                title: Text(action.$1),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pushNamed(action.$3),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOwnerStockPie(Map<String, int> stats) {
    final total = stats['items'] ?? 0;
    final low = stats['lowStock'] ?? 0;
    final ok = (total - low).clamp(0, 1 << 30);
    if (total == 0) {
      return Center(child: Text(tr('noStockYet')));
    }
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: PieChart(
            PieChartData(
              sectionsSpace: 4,
              centerSpaceRadius: 32,
              sections: [
                PieChartSectionData(
                  value: ok.toDouble(),
                  color: const Color(0xFF059669),
                  title: 'OK',
                  titleStyle: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                  ),
                ),
                PieChartSectionData(
                  value: low.toDouble(),
                  color: const Color(0xFFDC2626),
                  title: 'Low',
                  titleStyle: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Legend(
                  label: tr('healthyStock'),
                  color: const Color(0xFF059669),
                ),
                const SizedBox(height: 8),
                _Legend(label: tr('lowStock'), color: const Color(0xFFDC2626)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdminDashboard() {
    final stats = _shopStats ?? {};
    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ActionRequiredBanner(),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () async {
                await Navigator.of(context).pushNamed('/create-shop');
                _loadDashboard();
              },
              icon: const Icon(Icons.add),
              label: Text(tr('addNewShop')),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  tr('activeShops'),
                  stats['active']?.toString() ?? '0',
                  Icons.storefront_rounded,
                  const Color(0xFF059669),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  tr('totalShops'),
                  stats['total']?.toString() ?? '0',
                  Icons.receipt_long_rounded,
                  const Color(0xFF0B4F3A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  tr('pending'),
                  stats['pending']?.toString() ?? '0',
                  Icons.pending_actions_rounded,
                  const Color(0xFFD97706),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  tr('suspended'),
                  stats['suspended']?.toString() ?? '0',
                  Icons.cancel_rounded,
                  const Color(0xFFDC2626),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            tr('shopStatusCharts'),
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(height: 230, child: _buildAdminStatusPie(stats)),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(height: 200, child: _buildAdminStatusBar(stats)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: Text(tr('exportPdf')),
                  onPressed: () => _exportShopsReport(true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.table_view_rounded),
                  label: Text(tr('exportExcel')),
                  onPressed: () => _exportShopsReport(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.data_object_rounded),
            label: Text(tr('exportJson')),
            onPressed: _exportDatabaseJson,
          ),
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFFE6F4F1),
            child: ListTile(
              leading: const Icon(
                Icons.fact_check_outlined,
                color: Color(0xFF0B4F3A),
              ),
              title: const Text(
                'Issue reports',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Monitor and resolve owner-reported issues'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).pushNamed('/admin-issues'),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            tr('recentShops'),
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_recentShops.isEmpty)
            ListTile(title: Text(tr('noShopsFound')))
          else
            for (final shop in _recentShops)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.storefront_rounded),
                  title: Text(
                    shop['shopName']?.toString() ?? tr('medicalShop'),
                  ),
                  subtitle: Text(
                    shop['status']?.toString() ?? 'Status unavailable',
                  ),
                  onTap: () => _openShopDetails(shop),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildAdminStatusPie(Map<String, dynamic> stats) {
    final sections = _adminSections(stats);
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: PieChart(
            PieChartData(
              sectionsSpace: 4,
              centerSpaceRadius: 40,
              sections: sections.map((entry) {
                return PieChartSectionData(
                  value: entry.$2.toDouble(),
                  color: entry.$3,
                  title: '${entry.$2}',
                  titleStyle: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in sections) ...[
                  _Legend(label: entry.$1, color: entry.$3),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<(String, int, Color)> _adminSections(Map<String, dynamic> stats) {
    return [
      (
        tr('active'),
        (stats['active'] as num?)?.toInt() ?? 0,
        const Color(0xFF059669),
      ),
      (
        tr('pending'),
        (stats['pending'] as num?)?.toInt() ?? 0,
        const Color(0xFFD97706),
      ),
      (
        tr('suspended'),
        (stats['suspended'] as num?)?.toInt() ?? 0,
        const Color(0xFFDC2626),
      ),
    ];
  }

  Widget _buildAdminStatusBar(Map<String, dynamic> stats) {
    final sections = _adminSections(stats);
    final maxVal = sections.fold<double>(
      1,
      (m, s) => m > s.$2 ? m : s.$2.toDouble(),
    );
    return BarChart(
      BarChartData(
        maxY: maxVal + 1,
        barGroups: [
          for (final entry in sections)
            BarChartGroupData(
              x: sections.indexOf(entry),
              barRods: [
                BarChartRodData(
                  toY: entry.$2.toDouble(),
                  color: entry.$3,
                  width: 26,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
        ],
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 24),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  value.toInt() >= 0 && value.toInt() < sections.length
                      ? sections[value.toInt()].$1
                      : '',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        gridData: const FlGridData(show: true),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
