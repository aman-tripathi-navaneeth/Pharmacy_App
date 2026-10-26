import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'data/expiry_repository.dart';
import 'data/low_stock_repository.dart';
import 'data/reconciliation_repository.dart';
import 'screens/expiry_dashboard_screen.dart';
import 'screens/low_stock_screen.dart';
import 'screens/reconciliation_screen.dart';

void main() => runApp(const PharmacyApp());

class PharmacyApp extends StatelessWidget {
  const PharmacyApp({super.key});

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
        home: const MobileViewWrapper(child: PharmacyHome()),
      ),
    );
  }
}

class MobileViewWrapper extends StatelessWidget {
  final Widget child;

  const MobileViewWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 500) {
          return Scaffold(
            backgroundColor: const Color(0xFFE2E8F0),
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
                  border: Border.all(
                    color: const Color(0xFFCBD5E1),
                    width: 1.5,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: child,
              ),
            ),
          );
        }
        return child;
      },
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
