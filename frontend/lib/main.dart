import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/mobile_view_wrapper.dart';
import 'core/widgets/module_drawer.dart';
import 'modules/inventory_batches_stock_ledger/screens/inventory_dashboard_screen.dart';
import 'modules/inventory_batches_stock_ledger/services/inventory_service.dart';

void main() {
  runApp(const PharmacyApp());
}

class PharmacyApp extends StatefulWidget {
  const PharmacyApp({super.key});

  @override
  State<PharmacyApp> createState() => _PharmacyAppState();
}

class _PharmacyAppState extends State<PharmacyApp> {
  late final InventoryService _inventoryService;

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
    return MaterialApp(
      title: 'Pharmacy Store',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: MobileViewWrapper(
        child: AppShell(inventoryService: _inventoryService),
      ),
    );
  }
}

class AppShell extends StatelessWidget {
  final InventoryService inventoryService;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  AppShell({super.key, required this.inventoryService});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: const ModuleDrawer(activeModuleNumber: 5),
      body: InventoryDashboardScreen(
        service: inventoryService,
        onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
      ),
    );
  }
}
