import 'package:flutter/material.dart';

import 'features/dashboard/screens/dashboard_frame.dart';
import 'features/dashboard/screens/purchases_screen.dart';
import 'features/dashboard/screens/summary_screen.dart';
import 'features/dashboard/screens/today_screen.dart';

void main() {
  runApp(const PharmacyApp());
}

class PharmacyApp extends StatelessWidget {
  const PharmacyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pharmacy Store',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E), // Teal pharmacy theme
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
      home: const MobileViewWrapper(
        child: DashboardHome(),
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

/// Wraps the content in a centered mobile viewport when running on Web or Desktop,
/// and renders full-screen on native mobile devices.
class MobileViewWrapper extends StatelessWidget {
  final Widget child;

  const MobileViewWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // If screen width is wider than a phone (e.g., Web/Desktop), display in mobile frame
        if (constraints.maxWidth > 500) {
          return Scaffold(
            backgroundColor: const Color(0xFFE2E8F0),
            body: Center(
              child: Container(
                width: 420,
                height: constraints.maxHeight > 880 ? 840 : constraints.maxHeight * 0.96,
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

        // Native mobile view: fill device screen
        return child;
      },
    );
  }
}
