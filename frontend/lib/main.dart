import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api_session.dart';
import 'core/api_client.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/module_drawer.dart';
import 'data/expiry_repository.dart';
import 'data/low_stock_repository.dart';
import 'data/reconciliation_repository.dart';
import 'features/dashboard/screens/dashboard_frame.dart';
import 'features/dashboard/screens/purchases_screen.dart';
import 'features/dashboard/screens/summary_screen.dart';
import 'features/dashboard/screens/today_screen.dart';
import 'modules/inventory_batches_stock_ledger/screens/inventory_dashboard_screen.dart';
import 'modules/inventory_batches_stock_ledger/services/inventory_service.dart';
import 'modules/offline_sync_reliability/module.dart';
import 'screens/account_setup_screen.dart';
import 'screens/create_shop_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/email_history_screen.dart';
import 'screens/expiry_dashboard_screen.dart';
import 'screens/issues_screen.dart';
import 'screens/legal_information_screen.dart';
import 'screens/login_screen.dart';
import 'screens/low_stock_screen.dart';
import 'screens/new_bill_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/prescriptions_screen.dart';
import 'screens/reconciliation_screen.dart';
import 'screens/sales_report_screen.dart';
import 'screens/scan_inventory_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shop_list_screen.dart';
import 'screens/shop_screen.dart';
import 'screens/welcome_screen.dart';

void main() {
  runApp(const PharmacyApp());
}

class PharmacyApp extends StatelessWidget {
  final Widget? home;

  const PharmacyApp({super.key, this.home});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ExpiryRepository>(
          create: (_) => ExpiryRepository(ApiClient()),
        ),
        Provider<LowStockRepository>(
          create: (_) => LowStockRepository(ApiClient()),
        ),
        Provider<ReconciliationRepository>(
          create: (_) => ReconciliationRepository(ApiClient()),
        ),
      ],
      child: MaterialApp(
        title: 'Pharmacy Store',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0F766E),
            primary: const Color(0xFF0F766E),
            surface: const Color(0xFFF8FAFC),
          ),
          scaffoldBackgroundColor: const Color(0xFFF1F5F9),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0F766E),
            foregroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0F766E),
            primary: const Color(0xFF0F766E),
            surface: const Color(0xFF112D22),
          ),
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0F766E),
            foregroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
          ),
        ),
        builder: (context, child) =>
            MobileViewWrapper(child: child ?? const SizedBox.shrink()),
        home: home ?? const WelcomeScreen(),
        routes: {
          '/login': (_) => const LoginScreen(),
          '/terms': (_) =>
              const LegalInformationScreen(document: LegalDocument.terms),
          '/privacy': (_) =>
              const LegalInformationScreen(document: LegalDocument.privacy),
          '/account-setup': (_) => const AccountSetupScreen(),
          '/dashboard': (_) => DashboardScreen(
            userRole: ApiSession.user['role']?.toString() ?? '',
            userName: ApiSession.user['fullName']?.toString() ?? 'Account',
          ),
          '/shop': (_) => ShopScreen(
            userRole: ApiSession.user['role']?.toString() ?? '',
            shopId: ApiSession.user['ownerStoreId']?.toString(),
          ),
          '/shops': (_) => const ShopListScreen(),
          '/scan': (_) => ScanInventoryScreen(
            userRole: ApiSession.user['role']?.toString() ?? '',
            storeId: ApiSession.user['ownerStoreId']?.toString(),
          ),
          '/notifications': (_) => const NotificationsScreen(),
          '/settings': (context) => SettingsScreen(
            passwordUpdated: ModalRoute.of(context)?.settings.arguments == true,
          ),
          '/new-bill': (_) => const NewBillScreen(),
          '/sales-report': (_) => const SalesReportScreen(),
          '/create-shop': (_) => const CreateShopScreen(),
          '/email-history': (_) => const EmailHistoryScreen(),
          '/admin-issues': (_) => const AdminIssuesScreen(),
          '/issues': (_) => const IssuesScreen(),
          '/prescriptions': (_) => PrescriptionsScreen(
            userRole: ApiSession.user['role']?.toString() ?? '',
            shopId: ApiSession.user['ownerStoreId']?.toString(),
          ),
          '/inventory': (_) => const Module5InventoryScreen(),
          '/m6': (_) => const PharmacyHome(),
          '/expiry': (_) => const ExpiryDashboardScreen(),
          '/low-stock': (_) => const LowStockScreen(),
          '/reconcile': (_) => const ReconciliationScreen(),
          '/today-dashboard': (_) => const DashboardHome(),
          '/offline-sync': (_) => const OfflineSyncReliabilityScreen(),
        },
      ),
    );
  }
}

/// Hosts the three dashboard tabs, keeping each screen's state alive.
class DashboardHome extends StatefulWidget {
  const DashboardHome({super.key});

  @override
  State<DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<DashboardHome> {
  DashboardTab _tab = DashboardTab.today;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: _tab.index,
      children: <Widget>[
        TodayScreen(
          activeTab: _tab,
          onTabSelected: (DashboardTab t) => setState(() => _tab = t),
        ),
        SummaryScreen(
          activeTab: _tab,
          onTabSelected: (DashboardTab t) => setState(() => _tab = t),
        ),
        PurchasesScreen(
          activeTab: _tab,
          onTabSelected: (DashboardTab t) => setState(() => _tab = t),
        ),
      ],
    );
  }
}

class Module5InventoryScreen extends StatefulWidget {
  const Module5InventoryScreen({super.key});

  @override
  State<Module5InventoryScreen> createState() => _Module5InventoryScreenState();
}

class _Module5InventoryScreenState extends State<Module5InventoryScreen> {
  late final InventoryService _inventoryService;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _inventoryService = InventoryService();
  }

  @override
  void dispose() {
    _inventoryService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: const ModuleDrawer(activeModuleNumber: 5),
      body: InventoryDashboardScreen(
        service: _inventoryService,
        onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
      ),
    );
  }
}

class PharmacyHome extends StatefulWidget {
  const PharmacyHome({super.key});

  @override
  State<PharmacyHome> createState() => _PharmacyHomeState();
}

class _PharmacyHomeState extends State<PharmacyHome> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const BlankHomePage(),
      const ExpiryDashboardScreen(),
      const LowStockScreen(),
      const ReconciliationScreen(),
      const SettingsPage(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_busy_outlined),
            label: 'Expiry',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            label: 'Low Stock',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            label: 'Reconcile',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class BlankHomePage extends StatelessWidget {
  const BlankHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Column(
          children: [
            Text(
              'Pharmacy Store',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              'Mobile View',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCCFBF1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.local_pharmacy_rounded,
                    size: 40,
                    color: Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Pharmacy App',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Manage expiry, low stock, and inventory reconciliation from the navigation bar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(
        child: Text('Settings – not implemented yet'),
      ),
    );
  }
}

class MobileViewWrapper extends StatelessWidget {
  const MobileViewWrapper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 640) {
          return child;
        }
        return Scaffold(
          backgroundColor: const Color(0xFFF1F5F9),
          body: Center(
            child: Container(
              width: 420,
              height: constraints.maxHeight > 880
                  ? 840
                  : constraints.maxHeight * 0.96,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
