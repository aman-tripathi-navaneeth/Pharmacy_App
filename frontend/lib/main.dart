import 'package:flutter/material.dart';

import 'api_session.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/module_drawer.dart';
import 'modules/inventory_batches_stock_ledger/screens/inventory_dashboard_screen.dart';
import 'modules/inventory_batches_stock_ledger/services/inventory_service.dart';
import 'screens/account_setup_screen.dart';
import 'screens/create_shop_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/email_history_screen.dart';
import 'screens/issues_screen.dart';
import 'screens/legal_information_screen.dart';
import 'screens/login_screen.dart';
import 'screens/new_bill_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/prescriptions_screen.dart';
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
    return MaterialApp(
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
      },
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
