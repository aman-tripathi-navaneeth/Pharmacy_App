import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/batch_model.dart';
import '../models/enums.dart';
import '../models/expiry_tier_model.dart';
import '../services/inventory_service.dart';
import '../widgets/batch_card.dart';
import '../widgets/inventory_kpi_cards.dart';
import '../widgets/stock_balance_card.dart';
import '../widgets/transaction_card.dart';
import 'add_batch_dialog.dart';
import 'post_movement_dialog.dart';
import 'reorder_threshold_dialog.dart';
import 'return_to_supplier_dialog.dart';
import 'audit_session_dialog.dart';
import 'blind_count_sheet_dialog.dart';
import 'discrepancy_review_sheet.dart';
import '../models/audit_model.dart';
import '../models/low_stock_alert_model.dart';
import '../models/stock_balance_model.dart';

class InventoryDashboardScreen extends StatefulWidget {
  final InventoryService service;
  final VoidCallback? onOpenDrawer;

  const InventoryDashboardScreen({
    super.key,
    required this.service,
    this.onOpenDrawer,
  });

  @override
  State<InventoryDashboardScreen> createState() => _InventoryDashboardScreenState();
}

class _InventoryDashboardScreenState extends State<InventoryDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _openAddBatchModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddBatchDialog(service: widget.service),
    );
  }

  void _openPostMovementModal({String? productId, String? batchId}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PostMovementDialog(
        service: widget.service,
        initialProductId: productId,
        initialBatchId: batchId,
      ),
    );
  }

  void _openReturnToSupplierModal(BatchItem batch) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReturnToSupplierDialog(
        service: widget.service,
        batch: batch,
      ),
    );
  }

  void _openThresholdModal(StockBalanceItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReorderThresholdDialog(
        service: widget.service,
        item: item,
      ),
    );
  }

  void _openAuditsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final audits = widget.service.auditSessions.where((s) => s.storeId == widget.service.currentStoreId).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              maxChildSize: 0.95,
              minChildSize: 0.4,
              builder: (ctx, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: AppTheme.backgroundLight,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.fact_check, color: Colors.indigo),
                              SizedBox(width: 8),
                              Text(
                                'Physical Audits & Counts',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                              ),
                            ],
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('New Audit', style: TextStyle(fontSize: 12)),
                            onPressed: () async {
                              final newAudit = await showDialog<AuditSessionModel>(
                                context: context,
                                builder: (_) => AuditSessionDialog(service: widget.service),
                              );
                              if (newAudit != null) {
                                setModalState(() {});
                              }
                            },
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Expanded(
                        child: audits.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.inventory_outlined, size: 48, color: Colors.grey[400]),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No audits initiated yet for this store',
                                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                    ),
                                    const SizedBox(height: 8),
                                    ElevatedButton(
                                      onPressed: () async {
                                        final newAudit = await showDialog<AuditSessionModel>(
                                          context: context,
                                          builder: (_) => AuditSessionDialog(service: widget.service),
                                        );
                                        if (newAudit != null) {
                                          setModalState(() {});
                                        }
                                      },
                                      child: const Text('Start First Audit'),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                controller: scrollController,
                                itemCount: audits.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (ctx, idx) {
                                  final a = audits[idx];
                                  return Card(
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: const BorderSide(color: AppTheme.slateBorder),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  a.title,
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: a.status.color.withOpacity(0.12),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  a.status.label,
                                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: a.status.color),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Type: ${a.auditType.label}  •  Counted: ${a.totalItemsCounted}/${a.totalItemsExpected} lots',
                                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                          ),
                                          if (a.discrepancyCount > 0)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Text(
                                                'Discrepancies: ${a.discrepancyCount} (Surplus: ${a.surplusCount}, Shortage: ${a.shortageCount}) • Net: ₹${a.netVarianceValue.toStringAsFixed(2)}',
                                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: a.netVarianceValue >= 0 ? Colors.green.shade700 : Colors.red.shade700),
                                              ),
                                            ),
                                          const SizedBox(height: 10),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              if (a.status != AuditStatusEnum.reconciled && a.status != AuditStatusEnum.cancelled) ...[
                                                OutlinedButton.icon(
                                                  icon: const Icon(Icons.qr_code_scanner, size: 14),
                                                  label: const Text('Count Sheet', style: TextStyle(fontSize: 11)),
                                                  onPressed: () async {
                                                    await showDialog(
                                                      context: context,
                                                      builder: (_) => BlindCountSheetDialog(service: widget.service, auditSession: a),
                                                    );
                                                    setModalState(() {});
                                                  },
                                                ),
                                                const SizedBox(width: 8),
                                              ],
                                              ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: a.status == AuditStatusEnum.reconciled ? Colors.teal : Colors.deepPurple,
                                                  foregroundColor: Colors.white,
                                                ),
                                                icon: Icon(a.status == AuditStatusEnum.reconciled ? Icons.receipt_long : Icons.rate_review, size: 14),
                                                label: Text(a.status == AuditStatusEnum.reconciled ? 'View Ledger Record' : 'Review & Reconcile', style: const TextStyle(fontSize: 11)),
                                                onPressed: () async {
                                                  await showDialog(
                                                    context: context,
                                                    builder: (_) => DiscrepancyReviewSheet(service: widget.service, auditSession: a),
                                                  );
                                                  setModalState(() {});
                                                },
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _openSegregateDialog(BatchItem batch) {
    showDialog(
      context: context,
      builder: (context) {
        bool isProcessing = false;
        String? error;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.backgroundLight,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.shield_outlined, color: AppTheme.roseDanger, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Quarantine Expired Stock',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Segregate and quarantine ${batch.currentQuantity.toStringAsFixed(0)} ${batch.baseUnit} of ${batch.productName} (Batch: ${batch.batchNumber})?',
                    style: const TextStyle(fontSize: 12, color: AppTheme.slateDark),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.roseLight,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.roseDanger.withOpacity(0.3)),
                    ),
                    child: const Text(
                      'Action sets active batch stock to 0 to prevent accidental dispensing and appends an adjustment subtraction to the immutable stock ledger with Source: Stock Audit.',
                      style: TextStyle(fontSize: 11, color: AppTheme.roseDanger),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: const TextStyle(fontSize: 11, color: AppTheme.roseDanger, fontWeight: FontWeight.bold)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isProcessing ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.slateMuted, fontSize: 12)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.roseDanger,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: isProcessing
                      ? null
                      : () async {
                          setDialogState(() {
                            isProcessing = true;
                            error = null;
                          });
                          final idem = 'IDEM-QUAR-${DateTime.now().millisecondsSinceEpoch}';
                          final err = await widget.service.segregateExpiredBatchAsync(
                            batchId: batch.id,
                            idempotencyKey: idem,
                            reason: 'Expired stock quarantined and segregated',
                          );
                          if (err != null) {
                            setDialogState(() {
                              isProcessing = false;
                              error = err;
                            });
                          } else {
                            if (context.mounted) {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Batch ${batch.batchNumber} successfully quarantined.'),
                                  backgroundColor: AppTheme.roseDanger,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        },
                  child: isProcessing
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Quarantine Stock', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.service,
      builder: (context, _) {
        final service = widget.service;

        return Scaffold(
          backgroundColor: AppTheme.backgroundLight,
          appBar: AppBar(
            backgroundColor: AppTheme.backgroundLight,
            elevation: 0,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.slateBorder),
                ),
                child: const Icon(Icons.grid_view_rounded, size: 16, color: AppTheme.slateDark),
              ),
              tooltip: 'All System Modules',
              onPressed: widget.onOpenDrawer,
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'Pharmacy Store',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: 4),
                    Text(
                      '• Module 5',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primaryTeal),
                    ),
                  ],
                ),
                Text(
                  service.currentStoreName,
                  style: const TextStyle(fontSize: 11, color: AppTheme.slateMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            actions: [
              // Physical Audits & Cycle Counts Modal Trigger
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.indigo.withOpacity(0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fact_check_outlined, size: 16, color: Colors.indigo),
                      SizedBox(width: 4),
                      Text(
                        'Audits',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo),
                      ),
                    ],
                  ),
                ),
                tooltip: 'Physical Audits & Cycle Counts',
                onPressed: _openAuditsModal,
              ),

              // Store Switcher Menu
              PopupMenuButton<String>(
                icon: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.slateBorder),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.storefront_outlined, size: 16, color: AppTheme.slateDark),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down, size: 16, color: AppTheme.slateDark),
                    ],
                  ),
                ),
                tooltip: 'Switch Store Isolation',
                onSelected: (storeId) => service.switchStore(storeId),
                itemBuilder: (context) => service.availableStores.entries.map((entry) {
                  final isSelected = entry.key == service.currentStoreId;
                  return PopupMenuItem<String>(
                    value: entry.key,
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                          size: 16,
                          color: isSelected ? AppTheme.primaryTeal : AppTheme.slateMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.value,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                              color: isSelected ? AppTheme.primaryTeal : AppTheme.slateDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(width: 8),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(44),
              child: Container(
                color: AppTheme.backgroundLight,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEBE6DC),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.center,
                    labelColor: AppTheme.slateDark,
                    unselectedLabelColor: AppTheme.slateMuted,
                    indicator: BoxDecoration(
                      color: AppTheme.surfaceCard,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.inventory_2_outlined, size: 15),
                            const SizedBox(width: 4),
                            const Text('Balances'),
                            const SizedBox(width: 4),
                            _buildTabCountBadge(service.currentStoreBalances.length),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.layers_outlined, size: 15),
                            const SizedBox(width: 4),
                            const Text('Batches (FEFO)'),
                            const SizedBox(width: 4),
                            _buildTabCountBadge(service.currentStoreBatches.length),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.receipt_long_outlined, size: 15),
                            const SizedBox(width: 4),
                            const Text('Ledger'),
                            const SizedBox(width: 4),
                            _buildTabCountBadge(service.currentStoreTransactions.length),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          body: Column(
            children: [
              // Backend Status Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: service.isBackendConnected ? const Color(0xFFEDF3EC) : AppTheme.amberLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: service.isBackendConnected ? AppTheme.primaryTeal.withOpacity(0.3) : AppTheme.amberWarning.withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        service.isBackendConnected ? Icons.cloud_done : Icons.cloud_off,
                        size: 14,
                        color: service.isBackendConnected ? AppTheme.primaryTeal : AppTheme.amberWarning,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Backend Route: /stores/${service.currentStoreId}/inventory/connectivity [${service.backendDbStatus}]',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                            color: service.isBackendConnected ? AppTheme.slateDark : AppTheme.amberWarning,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      InkWell(
                        onTap: service.toggleBackendStatus,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceCard,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppTheme.slateBorder),
                          ),
                          child: Text(
                            service.isBackendConnected ? 'Simulate Offline' : 'Reconnect Live',
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.slateHeading),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // KPI Overviews & Search Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Column(
                  children: [
                    InventoryKpiCards(service: service),
                    const SizedBox(height: 12),
                    // Search bar
                    Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.slateBorder),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: service.setSearchQuery,
                        style: const TextStyle(fontSize: 13, color: AppTheme.slateDark),
                        decoration: InputDecoration(
                          hintText: 'Search medicines, batch lot, doc #, idem key...',
                          hintStyle: const TextStyle(fontSize: 12, color: AppTheme.slateMuted),
                          prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.slateMuted),
                          suffixIcon: service.searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16, color: AppTheme.slateMuted),
                                  onPressed: () {
                                    _searchController.clear();
                                    service.setSearchQuery('');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Stock Balances
                    _buildBalancesTab(service),

                    // Tab 2: Batches (FEFO)
                    _buildBatchesTab(service),

                    // Tab 3: Authoritative Stock Ledger
                    _buildLedgerTab(service),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
          floatingActionButton: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              FloatingActionButton.extended(
                heroTag: 'fab_add_batch',
                onPressed: _openAddBatchModal,
                backgroundColor: AppTheme.primaryTeal,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Batch', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              FloatingActionButton.extended(
                heroTag: 'fab_post_adjustment',
                onPressed: () => _openPostMovementModal(),
                backgroundColor: AppTheme.slateDark,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Stock Movement', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabCountBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.slateBorder.withOpacity(0.8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.slateHeading),
      ),
    );
  }

  Widget _buildBalancesTab(InventoryService service) {
    final balances = service.currentStoreBalances;
    final outOfStockCount = service.outOfStockProductsCount;
    final lowStockCount = service.lowStockProductsCount;

    return CustomScrollView(
      slivers: [
        // Low Stock & Replenishment Alert Banner
        if (outOfStockCount > 0 || lowStockCount > 0)
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: outOfStockCount > 0 ? AppTheme.roseLight : AppTheme.amberLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: outOfStockCount > 0
                      ? AppTheme.roseDanger.withOpacity(0.3)
                      : AppTheme.amberWarning.withOpacity(0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    outOfStockCount > 0 ? Icons.error_outline : Icons.notification_important_outlined,
                    color: outOfStockCount > 0 ? AppTheme.roseDanger : AppTheme.amberWarning,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          outOfStockCount > 0
                              ? '$outOfStockCount Out-of-Stock & $lowStockCount Low/Reorder Alert Products'
                              : '$lowStockCount Medicines Breached Reorder Threshold',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: outOfStockCount > 0 ? AppTheme.roseDanger : AppTheme.slateDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Unexpired stock has fallen to or below configured reorder levels. Tap "Thresholds" on any item to configure safety stock rules.',
                          style: TextStyle(fontSize: 11, color: AppTheme.slateBody),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Severity Pill Filter Row
        SliverToBoxAdapter(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All Items', style: TextStyle(fontSize: 11)),
                  selected: service.selectedStockAlertSeverityFilter == null,
                  onSelected: (_) => service.setStockAlertSeverityFilter(null),
                  selectedColor: AppTheme.tealSurface,
                  checkmarkColor: AppTheme.primaryTeal,
                ),
                const SizedBox(width: 6),
                ...StockAlertSeverityEnum.values.map((sev) {
                  final isSelected = service.selectedStockAlertSeverityFilter == sev;
                  Color chipColor;
                  String label;
                  switch (sev) {
                    case StockAlertSeverityEnum.outOfStock:
                      chipColor = AppTheme.roseLight;
                      label = 'Out of Stock (0)';
                      break;
                    case StockAlertSeverityEnum.criticalLow:
                      chipColor = AppTheme.roseLight;
                      label = 'Critical Low (<= Safety)';
                      break;
                    case StockAlertSeverityEnum.reorderRecommended:
                      chipColor = AppTheme.amberLight;
                      label = 'Reorder Required';
                      break;
                    case StockAlertSeverityEnum.adequate:
                      chipColor = AppTheme.tealSurface;
                      label = 'Adequate Stock';
                      break;
                  }

                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(label, style: const TextStyle(fontSize: 11)),
                      selected: isSelected,
                      onSelected: (selected) {
                        service.setStockAlertSeverityFilter(selected ? sev : null);
                      },
                      selectedColor: chipColor,
                      checkmarkColor: AppTheme.primaryTeal,
                    ),
                  );
                }),
              ],
            ),
          ),
        ),

        // Balances List
        if (balances.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyState('No medicines match the selected filter criteria'),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = balances[index];
                  return StockBalanceCard(
                    item: item,
                    onAdjustTap: () => _openPostMovementModal(productId: item.productId),
                    onConfigureThresholdTap: () => _openThresholdModal(item),
                  );
                },
                childCount: balances.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBatchesTab(InventoryService service) {
    final batches = service.currentStoreBatches;
    final expiredCount = service.expiredBatchesCount;
    final criticalCount = service.criticalExpiryCount;
    final atRiskUnits = service.atRiskUnitsCount;
    final atRiskCost = service.atRiskPurchaseValue;

    return Column(
      children: [
        // At-Risk Capital & Expiry Alerts Banner
        if (expiredCount > 0 || criticalCount > 0)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: expiredCount > 0 ? AppTheme.roseLight : AppTheme.amberLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: expiredCount > 0
                    ? AppTheme.roseDanger.withOpacity(0.3)
                    : AppTheme.amberWarning.withOpacity(0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  expiredCount > 0 ? Icons.warning_amber_rounded : Icons.schedule,
                  color: expiredCount > 0 ? AppTheme.roseDanger : AppTheme.amberWarning,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        expiredCount > 0
                            ? '$expiredCount Expired & $criticalCount Critical Batches Identified'
                            : '$criticalCount Critical Near-Expiry Batches (<30d)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: expiredCount > 0 ? AppTheme.roseDanger : AppTheme.slateDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Total Capital at Risk: ₹${atRiskCost.toStringAsFixed(2)} ($atRiskUnits units across early tiers)',
                        style: const TextStyle(fontSize: 11, color: AppTheme.slateBody),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Expiry Risk Pill Filter Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              FilterChip(
                label: const Text('All Batches', style: TextStyle(fontSize: 11)),
                selected: service.selectedExpiryTierFilter == null,
                onSelected: (_) => service.setExpiryTierFilter(null),
                selectedColor: AppTheme.tealSurface,
                checkmarkColor: AppTheme.primaryTeal,
              ),
              const SizedBox(width: 6),
              ...ExpiryTierEnum.values.map((tier) {
                final isSelected = service.selectedExpiryTierFilter == tier;
                Color chipColor;
                switch (tier) {
                  case ExpiryTierEnum.expired:
                    chipColor = AppTheme.roseLight;
                    break;
                  case ExpiryTierEnum.critical30:
                  case ExpiryTierEnum.near60:
                    chipColor = AppTheme.amberLight;
                    break;
                  default:
                    chipColor = AppTheme.tealSurface;
                }

                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(
                      tier == ExpiryTierEnum.expired
                          ? 'Expired (<0d)'
                          : tier == ExpiryTierEnum.critical30
                              ? 'Critical (<30d)'
                              : tier == ExpiryTierEnum.near60
                                  ? 'Near (31-60d)'
                                  : tier == ExpiryTierEnum.attention90
                                      ? 'Attention (61-90d)'
                                      : 'Safe (>90d)',
                      style: const TextStyle(fontSize: 11),
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      service.setExpiryTierFilter(selected ? tier : null);
                    },
                    selectedColor: chipColor,
                    checkmarkColor: AppTheme.primaryTeal,
                  ),
                );
              }),
            ],
          ),
        ),

        // Batches List
        Expanded(
          child: batches.isEmpty
              ? _buildEmptyState('No batches found for the selected expiry filter')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                  itemCount: batches.length,
                  itemBuilder: (context, index) {
                    final batch = batches[index];
                    return BatchCard(
                      batch: batch,
                      fefoRank: index + 1,
                      onAdjustTap: () => _openPostMovementModal(
                        productId: batch.productId,
                        batchId: batch.id,
                      ),
                      onSegregateTap: () => _openSegregateDialog(batch),
                      onReturnSupplierTap: () => _openReturnToSupplierModal(batch),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLedgerTab(InventoryService service) {
    final transactions = service.currentStoreTransactions;

    return Column(
      children: [
        // Movement Type Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              FilterChip(
                label: const Text('All Movements', style: TextStyle(fontSize: 11)),
                selected: service.selectedMovementTypeFilter == null,
                onSelected: (_) => service.setMovementTypeFilter(null),
                selectedColor: AppTheme.tealSurface,
                checkmarkColor: AppTheme.primaryTeal,
              ),
              const SizedBox(width: 6),
              ...MovementType.values.map((type) {
                final isSelected = service.selectedMovementTypeFilter == type;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(type.label, style: const TextStyle(fontSize: 11)),
                    selected: isSelected,
                    onSelected: (selected) {
                      service.setMovementTypeFilter(selected ? type : null);
                    },
                    selectedColor: AppTheme.tealSurface,
                    checkmarkColor: AppTheme.primaryTeal,
                  ),
                );
              }),
            ],
          ),
        ),

        Expanded(
          child: transactions.isEmpty
              ? _buildEmptyState('No ledger transactions recorded')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final tx = transactions[index];
                    return TransactionCard(tx: tx);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox_outlined, size: 48, color: AppTheme.slateMuted),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppTheme.slateMuted),
            ),
          ],
        ),
      ),
    );
  }
}
