import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/modules/inventory_batches_stock_ledger/models/batch_model.dart';
import 'package:pharmacy_app/modules/inventory_batches_stock_ledger/models/enums.dart';
import 'package:pharmacy_app/modules/inventory_batches_stock_ledger/models/expiry_tier_model.dart';
import 'package:pharmacy_app/modules/inventory_batches_stock_ledger/models/low_stock_alert_model.dart';
import 'package:pharmacy_app/modules/inventory_batches_stock_ledger/models/stock_balance_model.dart';
import 'package:pharmacy_app/modules/inventory_batches_stock_ledger/models/stock_transaction_model.dart';
import 'package:pharmacy_app/modules/inventory_batches_stock_ledger/models/audit_model.dart';
import 'package:pharmacy_app/modules/inventory_batches_stock_ledger/services/inventory_service.dart';

void main() {
  group('InventoryService Unit Tests', () {
    late InventoryService service;

    setUp(() {
      service = InventoryService();
    });

    test('Initial store state defaults to STR-001 with seeded records', () {
      expect(service.currentStoreId, equals('STR-001'));
      expect(service.currentStoreName, contains('Balaji Medical'));
      expect(service.currentStoreBatches.isNotEmpty, isTrue);
      expect(service.currentStoreBalances.isNotEmpty, isTrue);
      expect(service.currentStoreTransactions.isNotEmpty, isTrue);
    });

    test('Store switching maintains store isolation', () {
      final initialStore1BatchesCount = service.currentStoreBatches.length;
      expect(initialStore1BatchesCount, greaterThan(0));

      service.switchStore('STR-002');
      expect(service.currentStoreId, equals('STR-002'));
      expect(service.currentStoreName, contains('Apollo Corner'));

      // Store 2 only has 1 initial seeded batch
      expect(service.currentStoreBatches.length, equals(1));
      expect(service.currentStoreBatches.first.batchNumber, equals('DL-24B02'));

      // Switch back to Store 1
      service.switchStore('STR-001');
      expect(service.currentStoreBatches.length, equals(initialStore1BatchesCount));
    });

    test('Batches are strictly sorted by FEFO (earliest expiry first)', () {
      final batches = service.currentStoreBatches;
      for (int i = 0; i < batches.length - 1; i++) {
        expect(
          batches[i].expiryDate.isBefore(batches[i + 1].expiryDate) ||
              batches[i].expiryDate.isAtSameMomentAs(batches[i + 1].expiryDate),
          isTrue,
          reason: 'Batches must be in ascending order of expiry date',
        );
      }
    });

    test('Search filter properly scopes batches and transactions', () {
      service.setSearchQuery('Dolo');
      expect(service.currentStoreBatches.every((b) => b.productName.contains('Dolo')), isTrue);

      service.setSearchQuery('non-existent-medicine');
      expect(service.currentStoreBatches.isEmpty, isTrue);
      expect(service.currentStoreBalances.isEmpty, isTrue);

      service.setSearchQuery('');
      expect(service.currentStoreBatches.isNotEmpty, isTrue);
    });

    test('Movement type filter filters ledger accurately', () {
      service.setMovementTypeFilter(MovementType.purchaseIn);
      expect(
        service.currentStoreTransactions.every((t) => t.movementType == MovementType.purchaseIn),
        isTrue,
      );

      service.setMovementTypeFilter(MovementType.salesReportOut);
      expect(
        service.currentStoreTransactions.every((t) => t.movementType == MovementType.salesReportOut),
        isTrue,
      );

      service.setMovementTypeFilter(null);
      expect(service.currentStoreTransactions.length, greaterThan(1));
    });

    test('KPI metrics calculate expected values', () {
      expect(service.totalStockUnits, greaterThan(0));
      expect(service.activeBatchesCount, greaterThan(0));
      expect(service.expiredBatchesCount, greaterThanOrEqualTo(0));
      expect(service.totalTransactionsCount, greaterThan(0));
    });

    test('Register new batch enforces uppercase and unique constraint', () {
      final error = service.registerNewBatch(
        productId: 'PROD-001',
        batchNumber: 'new-lot-99',
        expiryDate: DateTime.now().add(const Duration(days: 365)),
        mrp: 50.0,
        purchaseRate: 35.0,
        initialQuantity: 100.0,
        baseUnit: 'tablet',
      );
      expect(error, isNull);

      // Verify batch was created with uppercase batch number and unit
      final created = service.currentStoreBatches.firstWhere((b) => b.batchNumber == 'NEW-LOT-99');
      expect(created.baseUnit, equals('TABLET'));

      // Verify duplicate batch registration is rejected
      final duplicateError = service.registerNewBatch(
        productId: 'PROD-001',
        batchNumber: 'new-lot-99',
        expiryDate: DateTime.now().add(const Duration(days: 365)),
        mrp: 50.0,
        purchaseRate: 35.0,
        initialQuantity: 50.0,
        baseUnit: 'tablet',
      );
      expect(duplicateError, isNotNull);
      expect(duplicateError, contains('already exists'));
    });

    test('Post stock movement enforces sign rules and rejects duplicate idempotency key', () {
      final initialTxCount = service.currentStoreTransactions.length;

      // Inward movement must result in positive quantity
      final inwardError = service.postStockMovement(
        productId: 'PROD-001',
        batchId: null,
        movementType: MovementType.purchaseIn,
        quantity: 50.0,
        sourceDocumentType: SourceDocumentType.purchaseInvoice,
        documentNumber: 'INV-TEST-001',
        notes: 'Test inward',
        idempotencyKey: 'TEST-IDEM-001',
      );
      expect(inwardError, isNull);
      expect(service.currentStoreTransactions.length, equals(initialTxCount + 1));
      expect(service.currentStoreTransactions.first.quantity, equals(50.0));

      // Duplicate idempotency key must be rejected
      final duplicateIdemError = service.postStockMovement(
        productId: 'PROD-001',
        batchId: null,
        movementType: MovementType.purchaseIn,
        quantity: 50.0,
        sourceDocumentType: SourceDocumentType.purchaseInvoice,
        documentNumber: 'INV-TEST-002',
        notes: 'Duplicate test',
        idempotencyKey: 'TEST-IDEM-001',
      );
      expect(duplicateIdemError, isNotNull);
      expect(duplicateIdemError, contains('Duplicate idempotency key'));
    });

    test('Backend connectivity toggle switches status gracefully', () {
      expect(service.isBackendConnected, isTrue);
      service.toggleBackendStatus();
      expect(service.isBackendConnected, isFalse);
      expect(service.backendDbStatus, contains('offline cache mode'));

      service.toggleBackendStatus();
      expect(service.isBackendConnected, isTrue);
    });

    test('Model serialization and deserialization roundtrip', () {
      final batch = BatchItem(
        id: 'B999',
        storeId: 'STR-001',
        productId: 'PROD-001',
        productName: 'Dolo 650mg Tablet',
        batchNumber: 'TEST-BATCH-01',
        expiryDate: DateTime(2027, 6, 30),
        mrp: 45.0,
        purchaseRate: 30.0,
        currentQuantity: 100.0,
        baseUnit: 'TABLET',
      );
      final batchJson = batch.toJson();
      final batchParsed = BatchItem.fromJson(batchJson);
      expect(batchParsed.batchNumber, equals('TEST-BATCH-01'));
      expect(batchParsed.mrp, equals(45.0));

      final balance = StockBalanceItem(
        storeId: 'STR-001',
        productId: 'PROD-001',
        productName: 'Dolo 650mg Tablet',
        totalQuantity: 250.0,
        baseUnit: 'TABLET',
        activeBatchCount: 3,
        isLowStock: false,
      );
      final balanceJson = balance.toJson();
      final balanceParsed = StockBalanceItem.fromJson(balanceJson);
      expect(balanceParsed.totalQuantity, equals(250.0));
      expect(balanceParsed.activeBatchCount, equals(3));

      final tx = StockTransactionItem(
        id: 'TX-999',
        storeId: 'STR-001',
        productId: 'PROD-001',
        productName: 'Dolo 650mg Tablet',
        movementType: MovementType.salesReportOut,
        quantity: -15.0,
        sourceDocumentType: SourceDocumentType.salesReport,
        sourceDocumentId: 'REP-001',
        idempotencyKey: 'IDEM-TX-999',
      );
      final txJson = tx.toJson();
      final txParsed = StockTransactionItem.fromJson(txJson);
      expect(txParsed.quantity, equals(-15.0));
      expect(txParsed.movementType, equals(MovementType.salesReportOut));
      expect(txParsed.isOutward, isTrue);
    });

    test('Phase 4: Reversal transaction reverses stock and appends compensating ledger entry', () async {
      final batch = service.currentStoreBatches.firstWhere((b) => b.productId == 'PROD-001' && b.currentQuantity > 20);
      final initialQty = batch.currentQuantity;
      final initialTxCount = service.currentStoreTransactions.length;

      // 1. Post sales deduction (-10)
      final saleErr = service.postStockMovement(
        productId: 'PROD-001',
        batchId: batch.id,
        movementType: MovementType.salesReportOut,
        quantity: -10.0,
        sourceDocumentType: SourceDocumentType.salesReport,
        documentNumber: 'SALE-REV-TEST',
        notes: 'Sales test',
        idempotencyKey: 'IDEM-SALE-REV-001',
      );
      expect(saleErr, isNull);
      expect(batch.currentQuantity, equals(initialQty - 10.0));
      expect(service.currentStoreTransactions.length, equals(initialTxCount + 1));

      final saleTx = service.currentStoreTransactions.first;
      expect(saleTx.idempotencyKey, equals('IDEM-SALE-REV-001'));

      // 2. Post reversal of the sales transaction
      final revErr = await service.postReversalAsync(
        originalTransactionId: saleTx.id,
        reason: 'Customer return reversal',
        idempotencyKey: 'IDEM-REV-REV-001',
      );
      expect(revErr, isNull);

      // Verify stock restored
      expect(batch.currentQuantity, equals(initialQty));

      // Verify reversal transaction is recorded with positive quantity
      final latestTx = service.currentStoreTransactions.first;
      expect(latestTx.movementType, equals(MovementType.reversal));
      expect(latestTx.quantity, equals(10.0));
      expect(latestTx.notes, contains('Customer return reversal'));

      // Verify original sale transaction is still preserved
      expect(service.currentStoreTransactions.any((t) => t.id == saleTx.id), isTrue);
    });

    test('Phase 5: convertUnits computes standard and custom packaging multipliers', () {
      // 1. Strip -> Tablet (10x)
      final r1 = service.convertUnits(fromUnit: 'STRIP', toUnit: 'TABLET', quantity: 5.0);
      expect(r1.convertedQuantity, equals(50.0));
      expect(r1.conversionFactor, equals(10.0));

      // 2. Box -> Tablet (100x)
      final r2 = service.convertUnits(fromUnit: 'BOX', toUnit: 'TABLET', quantity: 2.0);
      expect(r2.convertedQuantity, equals(200.0));
      expect(r2.conversionFactor, equals(100.0));

      // 3. Custom factor override
      final r3 = service.convertUnits(
        fromUnit: 'BLISTER',
        toUnit: 'CAPSULE',
        quantity: 3.0,
        customFactor: 15.0,
      );
      expect(r3.convertedQuantity, equals(45.0));
      expect(r3.conversionFactor, equals(15.0));

      // 4. Identity
      final r4 = service.convertUnits(fromUnit: 'TABLET', toUnit: 'TABLET', quantity: 12.0);
      expect(r4.convertedQuantity, equals(12.0));
      expect(r4.conversionFactor, equals(1.0));
    });

    test('Phase 5: previewFefoAllocationAsync accurately prioritizes unexpired batches', () async {
      service.toggleBackendStatus(); // Switch to in-memory mode for deterministic unit test
      final preview = await service.previewFefoAllocationAsync(
        productId: 'PROD-001',
        quantity: 6.0,
        unit: 'STRIP', // 6 strips = 60 tablets
      );

      expect(preview.productId, equals('PROD-001'));
      expect(preview.requestedQuantity, equals(6.0));
      expect(preview.baseQuantityRequired, equals(60.0));
      expect(preview.isFullyFulfillable, isTrue);
      expect(preview.allocations.isNotEmpty, isTrue);

      // Verify allocated lots are unexpired
      for (final alloc in preview.allocations) {
        expect(alloc.isExpired, isFalse);
        expect(alloc.allocatedQuantity, greaterThan(0));
      }
    });

    test('Phase 5: fefoDispenseAsync splits deduction and creates inferred ledger records', () async {
      service.toggleBackendStatus(); // Switch to in-memory mode
      final initialTxCount = service.currentStoreTransactions.length;
      final preview = await service.previewFefoAllocationAsync(
        productId: 'PROD-001',
        quantity: 2.0,
        unit: 'STRIP', // 20 tablets
      );
      expect(preview.isFullyFulfillable, isTrue);

      final err = await service.fefoDispenseAsync(
        productId: 'PROD-001',
        quantity: 2.0,
        unit: 'STRIP',
        sourceDocumentType: SourceDocumentType.salesReport,
        documentNumber: 'FEFO-EOD-01',
        idempotencyKey: 'IDEM-FEFO-TEST-001',
      );
      expect(err, isNull);

      // Verify ledger transactions were created with isInferred: true
      final latestTx = service.currentStoreTransactions.first;
      expect(latestTx.isInferred, isTrue);
      expect(latestTx.movementType, equals(MovementType.salesReportOut));
      expect(latestTx.idempotencyKey, contains('IDEM-FEFO-TEST-001'));
      expect(service.currentStoreTransactions.length, greaterThan(initialTxCount));
    });

    test('Phase 6: fetchExpiryBucketsAsync computes 5-tier classification and at-risk capital', () async {
      service.toggleBackendStatus(); // in-memory
      final res = await service.fetchExpiryBucketsAsync();

      expect(res.storeId, equals('STR-001'));
      expect(res.buckets.length, equals(5));
      expect(res.totalActiveBatches, greaterThan(0));
      expect(res.totalAtRiskUnits, greaterThan(0));
      expect(res.totalAtRiskPurchaseValue, greaterThan(0));

      final expiredBucket = res.buckets.firstWhere((b) => b.tier == ExpiryTierEnum.expired);
      expect(expiredBucket.batchCount, greaterThanOrEqualTo(1)); // B104 is expired
      expect(expiredBucket.totalUnits, greaterThan(0));

      final criticalBucket = res.buckets.firstWhere((b) => b.tier == ExpiryTierEnum.critical30);
      expect(criticalBucket.batchCount, greaterThanOrEqualTo(1)); // B102 is expiring in 22 days
    });

    test('Phase 6: fetchExpiryBucketsAsync filters by tier parameter', () async {
      service.toggleBackendStatus(); // in-memory
      final resExpired = await service.fetchExpiryBucketsAsync(tier: ExpiryTierEnum.expired);
      expect(resExpired.batches.every((b) => b.tier == ExpiryTierEnum.expired), isTrue);

      final resSafe = await service.fetchExpiryBucketsAsync(tier: ExpiryTierEnum.safe);
      expect(resSafe.batches.every((b) => b.tier == ExpiryTierEnum.safe), isTrue);
    });

    test('Phase 6: segregateExpiredBatchAsync quarantines expired batch and logs audit transaction', () async {
      service.toggleBackendStatus(); // in-memory
      final expiredBatch = service.currentStoreBatches.firstWhere((b) => b.isExpired && b.currentQuantity > 0);
      final initialTxCount = service.currentStoreTransactions.length;
      final originalQty = expiredBatch.currentQuantity;

      final err = await service.segregateExpiredBatchAsync(
        batchId: expiredBatch.id,
        idempotencyKey: 'IDEM-TEST-QUAR-001',
        reason: 'Expired stock audit segregation',
      );
      expect(err, isNull);

      // Verify active quantity became 0
      final updatedBatch = service.currentStoreBatches.firstWhere((b) => b.id == expiredBatch.id);
      expect(updatedBatch.currentQuantity, equals(0.0));

      // Verify ledger transaction was appended
      expect(service.currentStoreTransactions.length, equals(initialTxCount + 1));
      final latestTx = service.currentStoreTransactions.first;
      expect(latestTx.movementType, equals(MovementType.adjustmentSubtract));
      expect(latestTx.sourceDocumentType, equals(SourceDocumentType.stockAudit));
      expect(latestTx.quantity, equals(-originalQty));
      expect(latestTx.documentNumber, contains(expiredBatch.batchNumber));
    });

    test('Phase 6: segregateExpiredBatchAsync rejects unexpired batches', () async {
      service.toggleBackendStatus(); // in-memory
      final unexpiredBatch = service.currentStoreBatches.firstWhere((b) => !b.isExpired && b.currentQuantity > 0);

      final err = await service.segregateExpiredBatchAsync(
        batchId: unexpiredBatch.id,
        idempotencyKey: 'IDEM-TEST-QUAR-FAIL',
      );
      expect(err, isNotNull);
      expect(err, contains('not expired'));
    });

    test('Phase 6: returnToSupplierAsync deducts stock and appends return-out ledger entry', () async {
      service.toggleBackendStatus(); // in-memory
      final batch = service.currentStoreBatches.firstWhere((b) => b.currentQuantity >= 20);
      final initialQty = batch.currentQuantity;
      final initialTxCount = service.currentStoreTransactions.length;

      final err = await service.returnToSupplierAsync(
        batchId: batch.id,
        supplierId: 'SUP-DISTRIBUTOR-01',
        quantity: 10.0,
        returnReason: 'Near Expiry Agreement',
        idempotencyKey: 'IDEM-RET-TEST-001',
        creditNoteNumber: 'CN-TEST-999',
      );
      expect(err, isNull);

      // Verify batch stock reduced by 10
      final updatedBatch = service.currentStoreBatches.firstWhere((b) => b.id == batch.id);
      expect(updatedBatch.currentQuantity, equals(initialQty - 10.0));

      // Verify return-out transaction in ledger
      expect(service.currentStoreTransactions.length, equals(initialTxCount + 1));
      final latestTx = service.currentStoreTransactions.first;
      expect(latestTx.movementType, equals(MovementType.returnOut));
      expect(latestTx.sourceDocumentType, equals(SourceDocumentType.supplierReturn));
      expect(latestTx.quantity, equals(-10.0));
      expect(latestTx.documentNumber, equals('CN-TEST-999'));
    });

    test('Phase 6: returnToSupplierAsync guards against overdraft and duplicate idempotency', () async {
      service.toggleBackendStatus(); // in-memory
      final batch = service.currentStoreBatches.firstWhere((b) => b.currentQuantity > 0);

      // Overdraft rejection
      final overdraftErr = await service.returnToSupplierAsync(
        batchId: batch.id,
        supplierId: 'SUP-DISTRIBUTOR-01',
        quantity: batch.currentQuantity + 500.0,
        returnReason: 'Overdraft test',
        idempotencyKey: 'IDEM-RET-OVERDRAFT',
      );
      expect(overdraftErr, isNotNull);
      expect(overdraftErr, contains('exceeds active batch quantity'));

      // Post valid return
      final validErr = await service.returnToSupplierAsync(
        batchId: batch.id,
        supplierId: 'SUP-DISTRIBUTOR-01',
        quantity: 1.0,
        returnReason: 'Valid test',
        idempotencyKey: 'IDEM-RET-DUP-CHECK',
      );
      expect(validErr, isNull);

      // Duplicate idempotency rejection
      final dupErr = await service.returnToSupplierAsync(
        batchId: batch.id,
        supplierId: 'SUP-DISTRIBUTOR-01',
        quantity: 1.0,
        returnReason: 'Duplicate attempt',
        idempotencyKey: 'IDEM-RET-DUP-CHECK',
      );
      expect(dupErr, isNotNull);
      expect(dupErr, contains('Duplicate idempotency key'));
    });

    test('Phase 7: Dynamic StockAlertSeverity classification based on unexpired stock vs thresholds', () {
      final balances = service.currentStoreBalances;
      expect(balances.isNotEmpty, isTrue);

      for (final item in balances) {
        if (item.unexpiredQuantity <= 0) {
          expect(item.severity, equals(StockAlertSeverityEnum.outOfStock));
        } else if (item.unexpiredQuantity <= item.safetyStockLevel) {
          expect(item.severity, equals(StockAlertSeverityEnum.criticalLow));
        } else if (item.unexpiredQuantity <= item.reorderThreshold) {
          expect(item.severity, equals(StockAlertSeverityEnum.reorderRecommended));
        } else {
          expect(item.severity, equals(StockAlertSeverityEnum.adequate));
        }
      }
    });

    test('Phase 7: Expired stock is excluded from unexpired stock balance calculations', () {
      final now = DateTime.now();
      service.registerNewBatch(
        productId: 'PROD-003',
        batchNumber: 'EXP-TEST-999',
        expiryDate: now.subtract(const Duration(days: 30)),
        initialQuantity: 500.0,
        baseUnit: 'TABLET',
        purchaseRate: 20.0,
        mrp: 35.0,
      );

      final balance = service.currentStoreBalances.firstWhere((b) => b.productId == 'PROD-003');
      expect(balance.hasExpiredBatches, isTrue);
      expect(balance.totalQuantity, greaterThanOrEqualTo(500.0));
      expect(balance.unexpiredQuantity, lessThan(balance.totalQuantity));
    });

    test('Phase 7: updateProductThresholdsAsync validates safety_stock <= reorder_point', () async {
      service.toggleBackendStatus(); // offline mode
      final err = await service.updateProductThresholdsAsync(
        productId: 'PROD-001',
        reorderPoint: 50.0,
        safetyStockLevel: 60.0,
        reorderQuantity: 100.0,
      );
      expect(err, isNotNull);
      expect(err, contains('Safety stock level cannot exceed reorder point'));
    });

    test('Phase 7: Custom threshold overrides persist and dynamically alter balance severity', () async {
      service.toggleBackendStatus(); // offline mode
      
      var item = service.currentStoreBalances.firstWhere((b) => b.productId == 'PROD-001');
      final currentUnexpired = item.unexpiredQuantity;

      final err = await service.updateProductThresholdsAsync(
        productId: 'PROD-001',
        reorderPoint: currentUnexpired + 200.0,
        safetyStockLevel: 10.0,
        reorderQuantity: 250.0,
        leadTimeDays: 4,
      );
      expect(err, isNull);

      final config = await service.fetchProductThresholdAsync('PROD-001');
      expect(config.reorderPoint, equals(currentUnexpired + 200.0));
      expect(config.safetyStockLevel, equals(10.0));
      expect(config.reorderQuantity, equals(250.0));
      expect(config.leadTimeDays, equals(4));

      item = service.currentStoreBalances.firstWhere((b) => b.productId == 'PROD-001');
      expect(item.reorderThreshold, equals(currentUnexpired + 200.0));
      expect(item.safetyStockLevel, equals(10.0));
      if (currentUnexpired > 10.0) {
        expect(item.severity, equals(StockAlertSeverityEnum.reorderRecommended));
      }
    });

    test('Phase 7: Severity filter accurately filters currentStoreBalances', () {
      service.setStockAlertSeverityFilter(StockAlertSeverityEnum.outOfStock);
      expect(service.selectedStockAlertSeverityFilter, equals(StockAlertSeverityEnum.outOfStock));
      for (final item in service.currentStoreBalances) {
        expect(item.severity, equals(StockAlertSeverityEnum.outOfStock));
      }

      service.setStockAlertSeverityFilter(null);
      expect(service.selectedStockAlertSeverityFilter, isNull);
    });

    test('Phase 7: fetchLowStockAlertsAsync calculates replenishment recommendations', () async {
      service.toggleBackendStatus(); // offline mode
      final res = await service.fetchLowStockAlertsAsync();

      expect(res.storeId, equals('STR-001'));
      expect(res.totalMonitoredProducts, greaterThan(0));
      expect(res.alerts.isNotEmpty, isTrue);

      for (final alert in res.alerts) {
        if (alert.severity != StockAlertSeverityEnum.adequate) {
          expect(alert.suggestedReorderQuantity, greaterThan(0));
          expect(alert.suggestedReorderQuantity, greaterThanOrEqualTo(alert.reorderQuantity));
        }
      }
    });

    // --- Phase 8: Physical Stock Audits & Cycle Counts ---

    test('Phase 8: createAuditSessionAsync initializes session with snapshot expected items', () async {
      service.toggleBackendStatus(); // offline mode
      final session = await service.createAuditSessionAsync(
        title: 'Monthly Tablet Audit',
        auditType: AuditTypeEnum.fullAudit,
        assignedTo: 'AUDITOR-01',
      );

      expect(session, isNotNull);
      expect(session!.title, equals('Monthly Tablet Audit'));
      expect(session.status, equals(AuditStatusEnum.inProgress));
      expect(session.totalItemsExpected, greaterThan(0));
      expect(session.totalItemsCounted, equals(0));
      expect(service.auditSessions.isNotEmpty, isTrue);
    });

    test('Phase 8: fetchAuditSessionByIdAsync masks system quantities when blind=true', () async {
      service.toggleBackendStatus(); // offline mode
      final session = await service.createAuditSessionAsync(
        title: 'Blind Test Session',
        auditType: AuditTypeEnum.cycleCount,
      );

      // Record count of Dolo (seeded with 320 units) -> physical count is 310 (-10 shortage)
      await service.recordAuditCountsAsync(session!.id, [
        {
          'product_id': 'PROD-001',
          'batch_number': 'DL-24A01',
          'counted_quantity': 310.0,
          'discrepancy_reason': 'DAMAGE',
        }
      ]);

      // 1. Blind retrieval: expected stock is hidden
      final blindSession = await service.fetchAuditSessionByIdAsync(session.id, blind: true);
      expect(blindSession, isNotNull);
      final itemBlind = blindSession!.items!.first;
      expect(itemBlind.systemQuantity, isNull);
      expect(itemBlind.discrepancyQuantity, isNull);
      expect(itemBlind.countedQuantity, equals(310.0));

      // 2. Open retrieval: expected stock and discrepancy revealed
      final openSession = await service.fetchAuditSessionByIdAsync(session.id, blind: false);
      expect(openSession, isNotNull);
      final itemOpen = openSession!.items!.first;
      expect(itemOpen.systemQuantity, equals(320.0));
      expect(itemOpen.discrepancyQuantity, equals(-10.0));
      expect(itemOpen.discrepancyValue, equals(-220.0)); // -10 * 22.0
    });

    test('Phase 8: fetchAuditDiscrepanciesAsync calculates surplus and shortage valuations', () async {
      service.toggleBackendStatus(); // offline mode
      final session = await service.createAuditSessionAsync(
        title: 'Financial Variance Test',
        auditType: AuditTypeEnum.fullAudit,
      );

      // Record a shortage (-5 units @ 22.0 = -110.0)
      await service.recordAuditCountsAsync(session!.id, [
        {
          'product_id': 'PROD-001',
          'batch_number': 'DL-24A01',
          'counted_quantity': 315.0,
          'discrepancy_reason': 'THEFT_SHRINKAGE',
        }
      ]);

      final report = await service.fetchAuditDiscrepanciesAsync(session.id);
      expect(report, isNotNull);
      expect(report!.totalCounted, equals(1));
      expect(report.totalDiscrepant, equals(1));
      expect(report.totalShortageValue, equals(110.0));
      expect(report.netVarianceValue, equals(-110.0));
      expect(report.discrepantItems.first.batchNumber, equals('DL-24A01'));
    });

    test('Phase 8: reconcileAuditSessionAsync updates ledger and adjusts batch stock', () async {
      service.toggleBackendStatus(); // offline mode
      final session = await service.createAuditSessionAsync(
        title: 'Reconcile Execution Test',
        auditType: AuditTypeEnum.cycleCount,
      );

      // Record shortage of 15 units on Dolo DL-24A01 (current = 320 -> count = 305)
      await service.recordAuditCountsAsync(session!.id, [
        {
          'product_id': 'PROD-001',
          'batch_number': 'DL-24A01',
          'counted_quantity': 305.0,
          'discrepancy_reason': 'DAMAGE',
        }
      ]);

      final recon = await service.reconcileAuditSessionAsync(
        auditId: session.id,
        approvedBy: 'PHARMACIST-IN-CHARGE',
        idempotencyKey: 'IDEM-TEST-RECON-01',
        notes: 'Damage write-off approved',
      );

      expect(recon, isNotNull);
      expect(recon!.status, equals('RECONCILED'));
      expect(recon.ledgerTransactionsPosted, equals(1));
      expect(recon.totalShortageQty, equals(15.0));

      // Batch stock is updated to 305
      final updatedBatch = service.currentStoreBatches.firstWhere((b) => b.batchNumber == 'DL-24A01');
      expect(updatedBatch.currentQuantity, equals(305.0));

      // Stock transaction is posted
      final latestTx = service.currentStoreTransactions.first;
      expect(latestTx.movementType, equals(MovementType.adjustmentSubtract));
      expect(latestTx.quantity, equals(-15.0));
      expect(latestTx.sourceDocumentType, equals(SourceDocumentType.stockAudit));
    });

    test('Phase 8: cancelAuditSessionAsync marks session as cancelled', () async {
      service.toggleBackendStatus(); // offline mode
      final session = await service.createAuditSessionAsync(
        title: 'Audit to Cancel',
        auditType: AuditTypeEnum.fullAudit,
      );

      final cancelled = await service.cancelAuditSessionAsync(session!.id, reason: 'Shift ended early');
      expect(cancelled, isNotNull);
      expect(cancelled!.status, equals(AuditStatusEnum.cancelled));
      expect(cancelled.notes, contains('Shift ended early'));
    });
  });
}

