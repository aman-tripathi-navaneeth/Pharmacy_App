import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../../modules/authentication_store_roles/module.dart';
import '../../modules/catalogue_search_units/module.dart';
import '../../modules/suppliers_purchase_orders/module.dart';
import '../../modules/purchase_invoice_scanning/module.dart';
import '../../modules/expiry_low_stock_reconciliation/module.dart';
import '../../modules/outward_sales_report_scanning/module.dart';
import '../../modules/customers_refills_prescriptions/module.dart';
import '../../modules/udhaar_credit_payments/module.dart';
import '../../modules/whatsapp_notifications/module.dart';
import '../../modules/today_dashboard_reports/module.dart';
import '../../modules/offline_sync_reliability/module.dart';

class ModuleDrawer extends StatelessWidget {
  final int activeModuleNumber;

  const ModuleDrawer({super.key, this.activeModuleNumber = 5});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              color: AppTheme.primaryTeal,
              child: const Row(
                children: [
                  Icon(Icons.local_pharmacy, color: Colors.white, size: 32),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pharmacy Store',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '12-Member Modular Architecture',
                          style: TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'ACTIVE SCOPE (OUR MODULE)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: AppTheme.primaryTealDark,
                      ),
                    ),
                  ),
                  _buildModuleItem(
                    context: context,
                    moduleNumber: 5,
                    title: 'Inventory, Batches & Stock Ledger',
                    member: 'Member 5 (Us)',
                    icon: Icons.inventory_2_rounded,
                    isActive: activeModuleNumber == 5,
                    onTap: () {
                      Navigator.of(context).pop();
                    },
                  ),
                  const Divider(height: 24),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(
                      'OTHER TEAM MODULES (SCAFFOLDED)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                  ),
                  _buildModuleItem(
                    context: context,
                    moduleNumber: 1,
                    title: 'Authentication & Store Setup',
                    member: 'Member 1',
                    icon: Icons.admin_panel_settings_outlined,
                    isActive: activeModuleNumber == 1,
                    onTap: () => _navigateTo(context, const AuthenticationModuleScreen()),
                  ),
                  _buildModuleItem(
                    context: context,
                    moduleNumber: 2,
                    title: 'Catalogue, Search & Units',
                    member: 'Member 2',
                    icon: Icons.search_rounded,
                    isActive: activeModuleNumber == 2,
                    onTap: () => _navigateTo(context, const CatalogueModuleScreen()),
                  ),
                  _buildModuleItem(
                    context: context,
                    moduleNumber: 3,
                    title: 'Suppliers & Purchase Orders',
                    member: 'Member 3',
                    icon: Icons.local_shipping_outlined,
                    isActive: activeModuleNumber == 3,
                    onTap: () => _navigateTo(context, const SuppliersPurchaseOrdersScreen()),
                  ),
                  _buildModuleItem(
                    context: context,
                    moduleNumber: 4,
                    title: 'Purchase Invoice Scanning (OCR)',
                    member: 'Member 4',
                    icon: Icons.document_scanner_outlined,
                    isActive: activeModuleNumber == 4,
                    onTap: () => _navigateTo(context, const PurchaseInvoiceScanningScreen()),
                  ),
                  _buildModuleItem(
                    context: context,
                    moduleNumber: 6,
                    title: 'Expiry & Low Stock Alerts',
                    member: 'Member 6',
                    icon: Icons.warning_amber_rounded,
                    isActive: activeModuleNumber == 6,
                    onTap: () => _navigateTo(context, const ExpiryLowStockReconciliationScreen()),
                  ),
                  _buildModuleItem(
                    context: context,
                    moduleNumber: 7,
                    title: 'Outward Sales Scanning (OCR)',
                    member: 'Member 7',
                    icon: Icons.point_of_sale_rounded,
                    isActive: activeModuleNumber == 7,
                    onTap: () => _navigateTo(context, const OutwardSalesReportScanningScreen()),
                  ),
                  _buildModuleItem(
                    context: context,
                    moduleNumber: 8,
                    title: 'Customers, Refills & Prescriptions',
                    member: 'Member 8',
                    icon: Icons.people_outline_rounded,
                    isActive: activeModuleNumber == 8,
                    onTap: () => _navigateTo(context, const CustomersRefillsPrescriptionsScreen()),
                  ),
                  _buildModuleItem(
                    context: context,
                    moduleNumber: 9,
                    title: 'Udhaar / Credit & Payments',
                    member: 'Member 9',
                    icon: Icons.account_balance_wallet_outlined,
                    isActive: activeModuleNumber == 9,
                    onTap: () => _navigateTo(context, const UdhaarCreditPaymentsScreen()),
                  ),
                  _buildModuleItem(
                    context: context,
                    moduleNumber: 10,
                    title: 'WhatsApp & Notifications',
                    member: 'Member 10',
                    icon: Icons.chat_bubble_outline_rounded,
                    isActive: activeModuleNumber == 10,
                    onTap: () => _navigateTo(context, const WhatsappNotificationsScreen()),
                  ),
                  _buildModuleItem(
                    context: context,
                    moduleNumber: 11,
                    title: 'Today Dashboard & Reports',
                    member: 'Member 11',
                    icon: Icons.analytics_outlined,
                    isActive: activeModuleNumber == 11,
                    onTap: () => _navigateTo(context, const TodayDashboardReportsScreen()),
                  ),
                  _buildModuleItem(
                    context: context,
                    moduleNumber: 12,
                    title: 'Offline Sync & Reliability',
                    member: 'Member 12',
                    icon: Icons.sync_rounded,
                    isActive: activeModuleNumber == 12,
                    onTap: () => _navigateTo(context, const OfflineSyncReliabilityScreen()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateTo(BuildContext context, Widget screen) {
    Navigator.of(context).pop(); // Close drawer
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Widget _buildModuleItem({
    required BuildContext context,
    required int moduleNumber,
    required String title,
    required String member,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: isActive ? AppTheme.tealSurface.withOpacity(0.5) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isActive ? AppTheme.primaryTeal : AppTheme.slateBorder.withOpacity(0.5),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 16,
            color: isActive ? Colors.white : AppTheme.slateMuted,
          ),
        ),
        title: Text(
          'M$moduleNumber: $title',
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? AppTheme.primaryTealDark : AppTheme.slateDark,
          ),
        ),
        subtitle: Text(
          member,
          style: TextStyle(
            fontSize: 10,
            color: isActive ? AppTheme.primaryTeal : AppTheme.slateMuted,
          ),
        ),
        trailing: isActive
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryTeal,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'DESIGNED',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              )
            : null,
        onTap: onTap,
        dense: true,
      ),
    );
  }
}
