import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/batch_model.dart';
import '../models/enums.dart';
import '../models/expiry_tier_model.dart';
import '../models/fefo_allocation_model.dart';
import '../models/low_stock_alert_model.dart';
import '../models/stock_balance_model.dart';
import '../models/stock_transaction_model.dart';
import '../models/unit_conversion_model.dart';
import '../models/audit_model.dart';

class InventoryService extends ChangeNotifier {
  // Store Scoping
  String _currentStoreId = 'STR-001';
  final Map<String, String> availableStores = {
    'STR-001': 'Balaji Medical & General Stores (Main)',
    'STR-002': 'Apollo Corner Pharmacy (Branch 2)',
  };

  // Backend Connectivity status & HTTP Config
  String _baseUrl = 'http://127.0.0.1:8000/api/v1';
  bool _isBackendConnected = true;
  String _backendDbStatus = 'connected (PostgreSQL - pharmacy_store_dev)';
  bool _isSyncing = false;

  // Search & Filter
  String _searchQuery = '';
  MovementType? _selectedMovementTypeFilter;
  ExpiryTierEnum? _selectedExpiryTierFilter;
  StockAlertSeverityEnum? _selectedStockAlertSeverityFilter;

  // Custom Product Thresholds Cache: '$storeId-$productId' -> config
  final Map<String, ProductThresholdConfigModel> _customThresholds = {};

  // Phase 8: Physical Stock Audits
  final List<AuditSessionModel> _auditSessions = [];
  final Map<String, List<AuditCountItemModel>> _auditSessionCounts = {};

  List<AuditSessionModel> get auditSessions => List.unmodifiable(_auditSessions);

  // In-memory persistent data store
  final List<BatchItem> _batches = [];
  final List<StockTransactionItem> _transactions = [];

  // Catalogue Product Definitions
  final List<Map<String, dynamic>> catalogueProducts = [
    {
      'id': 'PROD-001',
      'name': 'Dolo 650mg Tablet',
      'unit': 'TABLET',
      'threshold': 100.0,
      'category': 'Analgesic / Antipyretic',
    },
    {
      'id': 'PROD-002',
      'name': 'Augmentin 625 Duo Tablet',
      'unit': 'TABLET',
      'threshold': 30.0,
      'category': 'Antibiotic',
    },
    {
      'id': 'PROD-003',
      'name': 'Azithral 500mg Tablet',
      'unit': 'TABLET',
      'threshold': 25.0,
      'category': 'Antibiotic',
    },
    {
      'id': 'PROD-004',
      'name': 'Pan-D Capsule',
      'unit': 'CAPSULE',
      'threshold': 40.0,
      'category': 'Antacid / PPI',
    },
    {
      'id': 'PROD-005',
      'name': 'Glycomet-GP 1 Forte',
      'unit': 'TABLET',
      'threshold': 50.0,
      'category': 'Antidiabetic',
    },
    {
      'id': 'PROD-006',
      'name': 'Ascoril D Plus Cough Syrup (100ml)',
      'unit': 'BOTTLE',
      'threshold': 15.0,
      'category': 'Cough & Cold',
    },
    {
      'id': 'PROD-007',
      'name': 'Betadine 10% Ointment (20g)',
      'unit': 'TUBE',
      'threshold': 10.0,
      'category': 'Antiseptic',
    },
    {
      'id': 'PROD-008',
      'name': 'Cetirizine 10mg Tablet',
      'unit': 'TABLET',
      'threshold': 60.0,
      'category': 'Antihistamine',
    },
  ];

  InventoryService() {
    _seedInitialData();
  }

  // Getters
  String get currentStoreId => _currentStoreId;
  String get currentStoreName => availableStores[_currentStoreId] ?? _currentStoreId;
  bool get isBackendConnected => _isBackendConnected;
  String get backendDbStatus => _backendDbStatus;
  String get searchQuery => _searchQuery;
  MovementType? get selectedMovementTypeFilter => _selectedMovementTypeFilter;
  String get baseUrl => _baseUrl;
  bool get isSyncing => _isSyncing;

  void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    notifyListeners();
  }

  void switchStore(String storeId) {
    if (availableStores.containsKey(storeId) && _currentStoreId != storeId) {
      _currentStoreId = storeId;
      notifyListeners();
      syncAllFromBackend();
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query.trim().toLowerCase();
    notifyListeners();
  }

  void setMovementTypeFilter(MovementType? type) {
    _selectedMovementTypeFilter = type;
    notifyListeners();
  }

  ExpiryTierEnum? get selectedExpiryTierFilter => _selectedExpiryTierFilter;

  void setExpiryTierFilter(ExpiryTierEnum? tier) {
    _selectedExpiryTierFilter = tier;
    notifyListeners();
  }

  StockAlertSeverityEnum? get selectedStockAlertSeverityFilter => _selectedStockAlertSeverityFilter;

  void setStockAlertSeverityFilter(StockAlertSeverityEnum? severity) {
    _selectedStockAlertSeverityFilter = severity;
    notifyListeners();
  }

  void toggleBackendStatus() {
    _isBackendConnected = !_isBackendConnected;
    _backendDbStatus = _isBackendConnected
        ? 'connected (MongoDB Atlas - pharmacy_store_dev)'
        : 'offline cache mode';
    notifyListeners();
    if (_isBackendConnected) {
      syncAllFromBackend();
    }
  }

  // --- Live Backend HTTP Sync (Phase 3) ---

  Future<dynamic> _httpGet(String path) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final uri = Uri.parse('$_baseUrl$path');
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        return jsonDecode(body);
      }
    } catch (e) {
      // Graceful offline fallback
    }
    return null;
  }

  Future<dynamic> _httpPost(String path, Map<String, dynamic> body) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final uri = Uri.parse('$_baseUrl$path');
      final request = await client.postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 4));
      final responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode == 201 || response.statusCode == 200) {
        return jsonDecode(responseBody);
      } else {
        try {
          final err = jsonDecode(responseBody);
          if (err is Map && err['detail'] is Map && err['detail']['message'] != null) {
            return {'error': err['detail']['message']};
          } else if (err is Map && err['detail'] != null) {
            return {'error': err['detail'].toString()};
          }
        } catch (_) {}
        return {'error': 'Server returned ${response.statusCode}'};
      }
    } catch (e) {
      // Graceful offline fallback
      return null;
    }
  }

  /// Verifies connectivity with FastAPI /stores/{store_id}/inventory/connectivity
  Future<bool> checkBackendConnectivity() async {
    final res = await _httpGet('/stores/$_currentStoreId/inventory/connectivity');
    if (res is Map<String, dynamic> && res['status'] == 'route-ready') {
      _isBackendConnected = true;
      final dbName = res['database'] ?? 'pharmacy_store_dev';
      _backendDbStatus = 'connected (MongoDB Atlas - $dbName)';
      notifyListeners();
      return true;
    } else {
      _isBackendConnected = false;
      _backendDbStatus = 'offline cache mode';
      notifyListeners();
      return false;
    }
  }

  /// Fetches inventory balance projections from backend GET /stores/{store_id}/inventory
  Future<void> fetchInventoryFromBackend() async {
    final res = await _httpGet('/stores/$_currentStoreId/inventory?limit=100');
    if (res is Map<String, dynamic> && res['items'] is List) {
      _isBackendConnected = true;
      notifyListeners();
    }
  }

  /// Fetches product batches from backend GET /stores/{store_id}/products/{product_id}/batches
  Future<List<BatchItem>> fetchBatchesFromBackend(String productId) async {
    final res = await _httpGet('/stores/$_currentStoreId/products/$productId/batches');
    if (res is List) {
      return res
          .whereType<Map<String, dynamic>>()
          .map((item) => BatchItem.fromJson(item))
          .toList();
    }
    return [];
  }

  /// Fetches authoritative transactions from backend GET /stores/{store_id}/inventory/transactions
  Future<void> fetchLedgerFromBackend() async {
    final res = await _httpGet('/stores/$_currentStoreId/inventory/transactions?limit=100');
    if (res is Map<String, dynamic> && res['items'] is List) {
      final rawList = res['items'] as List;
      final remoteTxs = rawList
          .whereType<Map<String, dynamic>>()
          .map((item) => StockTransactionItem.fromJson(item))
          .toList();
      if (remoteTxs.isNotEmpty) {
        _transactions.removeWhere((t) => t.storeId == _currentStoreId);
        _transactions.insertAll(0, remoteTxs);
        _isBackendConnected = true;
        notifyListeners();
      }
    }
  }

  /// Synchronizes summary, balances, and ledger from live backend
  Future<void> syncAllFromBackend() async {
    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();

    try {
      final connected = await checkBackendConnectivity();
      if (connected) {
        await Future.wait([
          fetchInventoryFromBackend(),
          fetchLedgerFromBackend(),
        ]);
      }
    } catch (_) {
      // Retain offline cache without failure
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  // Authoritative Batches sorted by FEFO (First-Expired, First-Out)
  List<BatchItem> get currentStoreBatches {
    final filtered = _batches.where((b) {
      if (b.storeId != _currentStoreId) return false;
      if (_selectedExpiryTierFilter != null) {
        final tier = ExpiryTierEnum.fromDays(b.daysUntilExpiry);
        if (tier != _selectedExpiryTierFilter) return false;
      }
      if (_searchQuery.isNotEmpty) {
        final matchesName = b.productName.toLowerCase().contains(_searchQuery);
        final matchesBatch = b.batchNumber.toLowerCase().contains(_searchQuery);
        if (!matchesName && !matchesBatch) return false;
      }
      return true;
    }).toList();

    // FEFO: Sort by expiry date ascending
    filtered.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    return filtered;
  }

  // Authoritative Stock Transactions (Newest first)
  List<StockTransactionItem> get currentStoreTransactions {
    return _transactions.where((t) {
      if (t.storeId != _currentStoreId) return false;
      if (_selectedMovementTypeFilter != null && t.movementType != _selectedMovementTypeFilter) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final matchesName = t.productName.toLowerCase().contains(_searchQuery);
        final matchesBatch = (t.batchNumber ?? '').toLowerCase().contains(_searchQuery);
        final matchesDoc = (t.documentNumber ?? '').toLowerCase().contains(_searchQuery);
        final matchesIdem = t.idempotencyKey.toLowerCase().contains(_searchQuery);
        if (!matchesName && !matchesBatch && !matchesDoc && !matchesIdem) return false;
      }
      return true;
    }).toList();
  }

  // Stock Balance Projections computed dynamically from active batches
  List<StockBalanceItem> get currentStoreBalances {
    final Map<String, List<BatchItem>> grouped = {};
    for (final batch in _batches.where((b) => b.storeId == _currentStoreId)) {
      grouped.putIfAbsent(batch.productId, () => []).add(batch);
    }

    final List<StockBalanceItem> balances = [];

    for (final prod in catalogueProducts) {
      final prodId = prod['id'] as String;
      final prodName = prod['name'] as String;
      final unit = prod['unit'] as String;
      final defaultThreshold = prod['threshold'] as double;

      final custom = _customThresholds['$_currentStoreId-$prodId'];
      final reorderPoint = custom?.reorderPoint ?? defaultThreshold;
      final safetyStock = custom?.safetyStockLevel ?? (defaultThreshold * 0.4);

      final batches = grouped[prodId] ?? [];
      final totalQty = batches.fold<double>(0.0, (sum, b) => sum + b.currentQuantity);
      
      // Filter out only batches that have stock for earliest expiry
      final activeStockBatches = batches.where((b) => b.currentQuantity > 0).toList();
      activeStockBatches.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));

      final earliestExpiry = activeStockBatches.isNotEmpty ? activeStockBatches.first.expiryDate : null;
      final hasExpired = batches.any((b) => b.isExpired && b.currentQuantity > 0);

      // Unexpired vs Expired separation for safety threshold calculation
      final unexpiredBatches = activeStockBatches.where((b) => !b.isExpired).toList();
      final unexpiredQty = unexpiredBatches.fold<double>(0.0, (sum, b) => sum + b.currentQuantity);

      StockAlertSeverityEnum sev;
      if (unexpiredQty <= 0) {
        sev = StockAlertSeverityEnum.outOfStock;
      } else if (unexpiredQty <= safetyStock) {
        sev = StockAlertSeverityEnum.criticalLow;
      } else if (unexpiredQty <= reorderPoint) {
        sev = StockAlertSeverityEnum.reorderRecommended;
      } else {
        sev = StockAlertSeverityEnum.adequate;
      }

      final isLow = unexpiredQty <= reorderPoint;

      if (_selectedStockAlertSeverityFilter != null && sev != _selectedStockAlertSeverityFilter) {
        continue;
      }

      if (_searchQuery.isNotEmpty) {
        final match = prodName.toLowerCase().contains(_searchQuery);
        if (!match) continue;
      }

      balances.add(StockBalanceItem(
        storeId: _currentStoreId,
        productId: prodId,
        productName: prodName,
        totalQuantity: totalQty,
        unexpiredQuantity: unexpiredQty,
        baseUnit: unit,
        activeBatchCount: batches.where((b) => b.currentQuantity > 0).length,
        earliestExpiryDate: earliestExpiry,
        hasExpiredBatches: hasExpired,
        isLowStock: isLow,
        reorderThreshold: reorderPoint,
        safetyStockLevel: safetyStock,
        severity: sev,
      ));
    }

    return balances;
  }

  // KPI Metrics
  int get totalStockUnits {
    return currentStoreBatches.fold<double>(0, (sum, b) => sum + b.currentQuantity).round();
  }

  int get activeBatchesCount {
    return currentStoreBatches.where((b) => b.currentQuantity > 0).length;
  }

  int get expiringSoonCount {
    return currentStoreBatches.where((b) => b.isExpiringSoon && b.currentQuantity > 0).length;
  }

  int get expiredBatchesCount {
    return _batches.where((b) => b.storeId == _currentStoreId && b.isExpired && b.currentQuantity > 0).length;
  }

  int get criticalExpiryCount {
    return _batches
        .where((b) => b.storeId == _currentStoreId && b.currentQuantity > 0 && b.daysUntilExpiry >= 0 && b.daysUntilExpiry <= 30)
        .length;
  }

  int get atRiskUnitsCount {
    return _batches
        .where((b) => b.storeId == _currentStoreId && b.currentQuantity > 0 && b.daysUntilExpiry <= 60)
        .fold<double>(0, (sum, b) => sum + b.currentQuantity)
        .round();
  }

  double get atRiskPurchaseValue {
    return _batches
        .where((b) => b.storeId == _currentStoreId && b.currentQuantity > 0 && b.daysUntilExpiry <= 60)
        .fold<double>(0.0, (sum, b) => sum + (b.currentQuantity * b.purchaseRate));
  }

  double get atRiskMrpValue {
    return _batches
        .where((b) => b.storeId == _currentStoreId && b.currentQuantity > 0 && b.daysUntilExpiry <= 60)
        .fold<double>(0.0, (sum, b) => sum + (b.currentQuantity * b.mrp));
  }

  int get totalTransactionsCount {
    return _transactions.where((t) => t.storeId == _currentStoreId).length;
  }

  int get outOfStockProductsCount {
    int count = 0;
    for (final prod in catalogueProducts) {
      final pid = prod['id'] as String;
      final unexp = _batches
          .where((b) => b.storeId == _currentStoreId && b.productId == pid && b.currentQuantity > 0 && !b.isExpired)
          .fold<double>(0.0, (s, b) => s + b.currentQuantity);
      if (unexp <= 0) count++;
    }
    return count;
  }

  int get lowStockProductsCount {
    int count = 0;
    for (final prod in catalogueProducts) {
      final pid = prod['id'] as String;
      final custom = _customThresholds['$_currentStoreId-$pid'];
      final threshold = custom?.reorderPoint ?? (prod['threshold'] as double? ?? 50.0);
      final unexp = _batches
          .where((b) => b.storeId == _currentStoreId && b.productId == pid && b.currentQuantity > 0 && !b.isExpired)
          .fold<double>(0.0, (s, b) => s + b.currentQuantity);
      if (unexp <= threshold) count++;
    }
    return count;
  }

  // --- Actions ---

  /// Register a new batch (e.g. from Purchase Inward)
  /// Enforces normalization to uppercase and unique (store_id, product_id, batch_number)
  String? registerNewBatch({
    required String productId,
    required String batchNumber,
    required DateTime expiryDate,
    required double mrp,
    required double purchaseRate,
    required double initialQuantity,
    required String baseUnit,
    String? invoiceNumber,
  }) {
    final cleanBatchNum = batchNumber.trim().toUpperCase();
    if (cleanBatchNum.isEmpty) {
      return 'Batch number cannot be empty';
    }

    final product = catalogueProducts.firstWhere(
      (p) => p['id'] == productId,
      orElse: () => {'id': productId, 'name': 'Unknown Medicine', 'unit': baseUnit},
    );

    // Check unique constraint (store_id, product_id, batch_number)
    final existing = _batches.any(
      (b) => b.storeId == _currentStoreId && b.productId == productId && b.batchNumber == cleanBatchNum,
    );
    if (existing) {
      return 'Batch $cleanBatchNum already exists for this medicine in store $_currentStoreId';
    }

    final batchId = 'BATCH-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(999)}';
    final newBatch = BatchItem(
      id: batchId,
      storeId: _currentStoreId,
      productId: productId,
      productName: product['name'] as String,
      batchNumber: cleanBatchNum,
      expiryDate: expiryDate,
      mrp: mrp,
      purchaseRate: purchaseRate,
      currentQuantity: initialQuantity,
      baseUnit: baseUnit.toUpperCase(),
    );

    _batches.add(newBatch);

    // Post initial inward transaction if initial quantity > 0
    if (initialQuantity > 0) {
      final docNum = (invoiceNumber != null && invoiceNumber.trim().isNotEmpty)
          ? invoiceNumber.trim().toUpperCase()
          : 'INV-${DateTime.now().year}-${Random().nextInt(9000) + 1000}';

      final tx = StockTransactionItem(
        id: 'TX-${DateTime.now().millisecondsSinceEpoch}',
        storeId: _currentStoreId,
        productId: productId,
        productName: product['name'] as String,
        batchId: batchId,
        batchNumber: cleanBatchNum,
        movementType: MovementType.purchaseIn,
        quantity: initialQuantity, // Positive for PURCHASE_IN
        baseUnit: baseUnit.toUpperCase(),
        sourceDocumentType: SourceDocumentType.purchaseInvoice,
        sourceDocumentId: 'DOC-${DateTime.now().millisecondsSinceEpoch}',
        documentNumber: docNum,
        idempotencyKey: 'IDEM-INWARD-${DateTime.now().millisecondsSinceEpoch}-${cleanBatchNum}',
        actorId: 'PHARMACIST-01',
        notes: 'Initial inward lot registration from supplier invoice',
      );
      _transactions.insert(0, tx);
    }

    notifyListeners();
    return null; // Success
  }

  /// Post an authoritative stock movement to the ledger with strict sign validation
  String? postStockMovement({
    required String productId,
    required String? batchId,
    required MovementType movementType,
    required double quantity, // User entered quantity
    required SourceDocumentType sourceDocumentType,
    required String documentNumber,
    required String notes,
    required String idempotencyKey,
  }) {
    if (quantity == 0) {
      return 'Movement quantity cannot be zero';
    }

    final product = catalogueProducts.firstWhere(
      (p) => p['id'] == productId,
      orElse: () => {'id': productId, 'name': 'Unknown Medicine', 'unit': 'TABLET'},
    );

    // Enforce Movement Sign Invariants:
    // Inward types must be positive (+), Outward must be negative (-)
    double signedQuantity = quantity;
    if (movementType.isInward == true) {
      if (signedQuantity < 0) {
        signedQuantity = signedQuantity.abs();
      }
    } else if (movementType.isInward == false) {
      if (signedQuantity > 0) {
        signedQuantity = -signedQuantity;
      }
    }

    // Check duplicate idempotency key
    final cleanIdemKey = idempotencyKey.trim();
    if (cleanIdemKey.isEmpty) {
      return 'Idempotency key is required to prevent duplicate stock updates';
    }
    final duplicateKey = _transactions.any(
      (t) => t.storeId == _currentStoreId && t.idempotencyKey == cleanIdemKey,
    );
    if (duplicateKey) {
      return 'Duplicate idempotency key detected: this movement was already posted';
    }

    // Locate batch if specified
    BatchItem? targetBatch;
    if (batchId != null) {
      try {
        targetBatch = _batches.firstWhere((b) => b.id == batchId && b.storeId == _currentStoreId);
      } catch (_) {
        targetBatch = null;
      }
    }

    // If outward movement and batch is specified, check against negative stock
    if (targetBatch != null && signedQuantity < 0) {
      if (targetBatch.currentQuantity + signedQuantity < 0) {
        return 'Insufficient stock in batch ${targetBatch.batchNumber}. Available: ${targetBatch.currentQuantity} ${targetBatch.baseUnit}';
      }
    }

    // Update batch quantity
    if (targetBatch != null) {
      targetBatch.currentQuantity += signedQuantity;
    }

    // Create and record authoritative transaction
    final tx = StockTransactionItem(
      id: 'TX-${DateTime.now().millisecondsSinceEpoch}',
      storeId: _currentStoreId,
      productId: productId,
      productName: product['name'] as String,
      batchId: targetBatch?.id,
      batchNumber: targetBatch?.batchNumber,
      movementType: movementType,
      quantity: signedQuantity,
      baseUnit: targetBatch?.baseUnit ?? (product['unit'] as String),
      sourceDocumentType: sourceDocumentType,
      sourceDocumentId: 'DOC-${DateTime.now().millisecondsSinceEpoch}',
      documentNumber: documentNumber.trim().toUpperCase(),
      idempotencyKey: cleanIdemKey,
      actorId: 'PHARMACIST-01',
      notes: notes.trim(),
      isInferred: targetBatch == null && movementType == MovementType.salesReportOut,
    );

    _transactions.insert(0, tx);
    notifyListeners();
    return null; // Success
  }

  /// Asynchronously registers a batch, validating locally and writing to live backend if connected
  Future<String?> registerNewBatchAsync({
    required String productId,
    required String batchNumber,
    required DateTime expiryDate,
    required double mrp,
    required double purchaseRate,
    required double initialQuantity,
    required String baseUnit,
    String? invoiceNumber,
  }) async {
    final localErr = registerNewBatch(
      productId: productId,
      batchNumber: batchNumber,
      expiryDate: expiryDate,
      mrp: mrp,
      purchaseRate: purchaseRate,
      initialQuantity: initialQuantity,
      baseUnit: baseUnit,
      invoiceNumber: invoiceNumber,
    );
    if (localErr != null) return localErr;

    if (_isBackendConnected) {
      final payload = {
        'product_id': productId,
        'batch_number': batchNumber.trim().toUpperCase(),
        'expiry_date': expiryDate.toIso8601String().split('T').first,
        'mrp': mrp,
        'purchase_rate': purchaseRate,
        'initial_quantity': initialQuantity,
        'base_unit': baseUnit.trim().toUpperCase(),
      };
      final res = await _httpPost('/stores/$_currentStoreId/batches', payload);
      if (res is Map && res['error'] != null) {
        return res['error'] as String;
      }
    }
    return null;
  }

  /// Asynchronously posts a stock movement to the ledger and live backend if connected
  Future<String?> postStockMovementAsync({
    required String productId,
    required String? batchId,
    required MovementType movementType,
    required double quantity,
    required SourceDocumentType sourceDocumentType,
    required String documentNumber,
    required String notes,
    required String idempotencyKey,
  }) async {
    final localErr = postStockMovement(
      productId: productId,
      batchId: batchId,
      movementType: movementType,
      quantity: quantity,
      sourceDocumentType: sourceDocumentType,
      documentNumber: documentNumber,
      notes: notes,
      idempotencyKey: idempotencyKey,
    );
    if (localErr != null) return localErr;

    if (_isBackendConnected) {
      BatchItem? targetBatch;
      if (batchId != null) {
        try {
          targetBatch = _batches.firstWhere((b) => b.id == batchId && b.storeId == _currentStoreId);
        } catch (_) {}
      }

      double signedQty = quantity;
      if (movementType.isInward == true && signedQty < 0) {
        signedQty = signedQty.abs();
      } else if (movementType.isInward == false && signedQty > 0) {
        signedQty = -signedQty;
      }

      final payload = {
        'product_id': productId,
        'batch_id': targetBatch?.id,
        'batch_number': targetBatch?.batchNumber,
        'movement_type': movementType.code,
        'quantity': signedQty,
        'base_unit': targetBatch?.baseUnit ?? 'TABLET',
        'source_document': {
          'document_type': sourceDocumentType.code,
          'document_id': 'DOC-${DateTime.now().millisecondsSinceEpoch}',
          'document_number': documentNumber.trim().toUpperCase(),
        },
        'idempotency_key': idempotencyKey.trim(),
        'notes': notes.trim(),
      };
      final res = await _httpPost('/stores/$_currentStoreId/inventory/movements', payload);
      if (res is Map && res['error'] != null) {
        return res['error'] as String;
      }
      if (res is Map && res['id'] != null) {
        final backendId = res['id'].toString();
        final localIdx = _transactions.indexWhere((t) => t.idempotencyKey == idempotencyKey.trim());
        if (localIdx != -1) {
          final old = _transactions[localIdx];
          _transactions[localIdx] = StockTransactionItem(
            id: backendId,
            storeId: old.storeId,
            productId: old.productId,
            productName: old.productName,
            batchId: old.batchId,
            batchNumber: old.batchNumber,
            movementType: old.movementType,
            quantity: old.quantity,
            baseUnit: old.baseUnit,
            enteredQuantity: old.enteredQuantity,
            enteredUnit: old.enteredUnit,
            conversionFactor: old.conversionFactor,
            sourceDocumentType: old.sourceDocumentType,
            sourceDocumentId: old.sourceDocumentId,
            documentNumber: old.documentNumber,
            idempotencyKey: old.idempotencyKey,
            actorId: old.actorId,
            notes: old.notes,
            isInferred: old.isInferred,
            createdAt: old.createdAt,
          );
        }
      }
    }
    return null;
  }

  /// Asynchronously posts a compensating transaction reversal to the immutable ledger
  Future<String?> postReversalAsync({
    required String originalTransactionId,
    required String reason,
    required String idempotencyKey,
  }) async {
    StockTransactionItem? original;
    try {
      original = _transactions.firstWhere((t) => (t.id == originalTransactionId || t.idempotencyKey == originalTransactionId) && t.storeId == _currentStoreId);
    } catch (_) {
      return 'Original transaction not found';
    }

    final reversalQty = -original.quantity;

    final revTx = StockTransactionItem(
      id: 'TX-REV-${DateTime.now().millisecondsSinceEpoch}',
      storeId: _currentStoreId,
      productId: original.productId,
      productName: original.productName,
      batchId: original.batchId,
      batchNumber: original.batchNumber,
      movementType: MovementType.reversal,
      quantity: reversalQty,
      baseUnit: original.baseUnit,
      sourceDocumentType: SourceDocumentType.manualAdjustment,
      sourceDocumentId: original.id,
      documentNumber: 'REV-${original.documentNumber ?? ''}',
      idempotencyKey: idempotencyKey.trim(),
      actorId: 'PHARMACIST-AUDITOR',
      notes: 'Reversal: $reason',
    );

    if (original.batchId != null) {
      try {
        final b = _batches.firstWhere((b) => b.id == original!.batchId && b.storeId == _currentStoreId);
        b.currentQuantity += reversalQty;
      } catch (_) {}
    }

    _transactions.insert(0, revTx);
    notifyListeners();

    if (_isBackendConnected) {
      final res = await _httpPost('/stores/$_currentStoreId/inventory/movements/reversal', {
        'original_transaction_id': original.idempotencyKey.isNotEmpty ? original.idempotencyKey : originalTransactionId,
        'idempotency_key': idempotencyKey.trim(),
        'reason': reason.trim(),
      });
      if (res is Map && res['error'] != null) {
        final errMsg = res['error'].toString();
        // If the original transaction was a local-only or seeded transaction not present on backend, allow local reversal
        if (!errMsg.toLowerCase().contains('not found')) {
          return errMsg;
        }
      }
    }

    return null;
  }

  // ===========================================================================
  // Phase 5: Multi-Unit Packaging Conversions & FEFO Engine
  // ===========================================================================

  static const Map<String, double> standardPackagingFactors = {
    'STRIP->TABLET': 10.0,
    'BOX->TABLET': 100.0,
    'BOX->CAPSULE': 100.0,
    'BOX->STRIP': 10.0,
    'BOTTLE->ML': 100.0,
    'TABLET->STRIP': 0.1,
    'TABLET->BOX': 0.01,
    'STRIP->BOX': 0.1,
    'ML->BOTTLE': 0.01,
  };

  /// Calculates unit conversion between packaging unit and base unit
  UnitConversionResult convertUnits({
    required String fromUnit,
    required String toUnit,
    required double quantity,
    double? customFactor,
    String? productId,
  }) {
    final cleanFrom = fromUnit.trim().toUpperCase();
    final cleanTo = toUnit.trim().toUpperCase();

    if (customFactor != null && customFactor > 0) {
      return UnitConversionResult(
        fromUnit: cleanFrom,
        toUnit: cleanTo,
        enteredQuantity: quantity,
        convertedQuantity: ((quantity * customFactor) * 10000).round() / 10000,
        conversionFactor: customFactor,
        notes: 'Applied custom conversion factor: 1 $cleanFrom = $customFactor $cleanTo',
      );
    }

    if (cleanFrom == cleanTo) {
      return UnitConversionResult(
        fromUnit: cleanFrom,
        toUnit: cleanTo,
        enteredQuantity: quantity,
        convertedQuantity: quantity,
        conversionFactor: 1.0,
        notes: 'Identical units ($cleanFrom)',
      );
    }

    final key = '$cleanFrom->$cleanTo';
    if (standardPackagingFactors.containsKey(key)) {
      final factor = standardPackagingFactors[key]!;
      return UnitConversionResult(
        fromUnit: cleanFrom,
        toUnit: cleanTo,
        enteredQuantity: quantity,
        convertedQuantity: ((quantity * factor) * 10000).round() / 10000,
        conversionFactor: factor,
        notes: 'Applied standard pharmacy packaging conversion: 1 $cleanFrom = $factor $cleanTo',
      );
    }

    return UnitConversionResult(
      fromUnit: cleanFrom,
      toUnit: cleanTo,
      enteredQuantity: quantity,
      convertedQuantity: quantity,
      conversionFactor: 1.0,
      notes: 'Default 1:1 conversion applied between $cleanFrom and $cleanTo',
    );
  }

  /// Simulates FEFO allocation plan across unexpired batch lots
  Future<FefoAllocationPreview> previewFefoAllocationAsync({
    required String productId,
    required double quantity,
    String? unit,
    double? customFactor,
    bool includeExpired = false,
  }) async {
    // 1. Live Backend HTTP Simulation if connected
    if (_isBackendConnected) {
      final payload = {
        'product_id': productId,
        'quantity': quantity,
        if (unit != null) 'unit': unit.toUpperCase(),
        if (customFactor != null) 'custom_factor': customFactor,
        'include_expired': includeExpired,
      };
      final res = await _httpPost('/stores/$_currentStoreId/inventory/fefo-preview', payload);
      if (res is Map<String, dynamic> && res['error'] == null) {
        return FefoAllocationPreview.fromJson(res);
      }
    }

    // 2. Offline / Local Fallback Simulation
    final activeBatches = _batches
        .where((b) => b.storeId == _currentStoreId && b.productId == productId && b.currentQuantity > 0)
        .toList();
    activeBatches.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));

    final baseUnit = activeBatches.isNotEmpty
        ? activeBatches.first.baseUnit
        : (catalogueProducts.firstWhere(
            (p) => p['id'] == productId,
            orElse: () => {'unit': 'TABLET'},
          )['unit'] as String);

    final enteredUnit = (unit ?? baseUnit).toUpperCase();
    final conversion = convertUnits(
      fromUnit: enteredUnit,
      toUnit: baseUnit,
      quantity: quantity,
      customFactor: customFactor,
    );
    final requiredBaseQty = conversion.convertedQuantity;

    double totalAvail = 0.0;
    for (final b in activeBatches) {
      if (!b.isExpired || includeExpired) {
        totalAvail += b.currentQuantity;
      }
    }

    final List<FefoBatchAllocation> allocations = [];
    double remaining = requiredBaseQty;

    for (final b in activeBatches) {
      if (remaining <= 0) break;
      if (b.isExpired && !includeExpired) continue;
      if (b.currentQuantity <= 0) continue;

      final toAlloc = min(b.currentQuantity, remaining);
      final remainingInBatch = b.currentQuantity - toAlloc;

      allocations.add(
        FefoBatchAllocation(
          batchId: b.id,
          batchNumber: b.batchNumber,
          expiryDate: b.expiryDate,
          allocatedQuantity: toAlloc,
          remainingBatchQuantity: remainingInBatch,
          mrp: b.mrp,
          purchaseRate: b.purchaseRate,
          isExpired: b.isExpired,
        ),
      );

      remaining -= toAlloc;
    }

    final isFulfillable = remaining <= 0.0001;

    return FefoAllocationPreview(
      storeId: _currentStoreId,
      productId: productId,
      requestedQuantity: quantity,
      requestedUnit: enteredUnit,
      baseUnit: baseUnit,
      conversionFactor: conversion.conversionFactor,
      baseQuantityRequired: requiredBaseQty,
      totalAvailableUnexpired: totalAvail,
      allocations: allocations,
      isFullyFulfillable: isFulfillable,
      shortage: remaining > 0.0001 ? remaining : 0.0,
    );
  }

  /// Executes automated outward FEFO sales dispense across unexpired lots
  Future<String?> fefoDispenseAsync({
    required String productId,
    required double quantity,
    String? unit,
    double? customFactor,
    required SourceDocumentType sourceDocumentType,
    required String documentNumber,
    required String idempotencyKey,
    String? notes,
    String? actorId,
  }) async {
    final preview = await previewFefoAllocationAsync(
      productId: productId,
      quantity: quantity,
      unit: unit,
      customFactor: customFactor,
    );

    if (!preview.isFullyFulfillable) {
      return 'Insufficient unexpired stock for product. Available: ${preview.totalAvailableUnexpired.toStringAsFixed(1)} ${preview.baseUnit}, required: ${preview.baseQuantityRequired.toStringAsFixed(1)} ${preview.baseUnit} (Shortage: ${preview.shortage.toStringAsFixed(1)})';
    }

    if (_isBackendConnected) {
      final payload = {
        'product_id': productId,
        'quantity': quantity,
        if (unit != null) 'unit': unit.toUpperCase(),
        if (customFactor != null) 'custom_factor': customFactor,
        'source_document': {
          'document_type': sourceDocumentType.code,
          'document_id': 'DOC-${DateTime.now().millisecondsSinceEpoch}',
          'document_number': documentNumber.trim().toUpperCase(),
        },
        'idempotency_key': idempotencyKey.trim(),
        if (actorId != null) 'actor_id': actorId,
        if (notes != null) 'notes': notes.trim(),
      };
      final res = await _httpPost('/stores/$_currentStoreId/inventory/fefo-dispense', payload);
      if (res is Map && res['error'] != null) {
        return res['error'] as String;
      }
    }

    // Local / In-memory batch deductions & ledger records
    final product = catalogueProducts.firstWhere(
      (p) => p['id'] == productId,
      orElse: () => {'name': productId, 'unit': preview.baseUnit},
    );

    for (int i = 0; i < preview.allocations.length; i++) {
      final alloc = preview.allocations[i];
      final targetBatch = _batches.firstWhere(
        (b) => b.storeId == _currentStoreId && (b.id == alloc.batchId || b.batchNumber == alloc.batchNumber),
        orElse: () => BatchItem(
          id: alloc.batchId,
          storeId: _currentStoreId,
          productId: productId,
          productName: product['name'] as String,
          batchNumber: alloc.batchNumber,
          expiryDate: alloc.expiryDate,
          mrp: alloc.mrp ?? 0.0,
          purchaseRate: alloc.purchaseRate ?? 0.0,
          currentQuantity: alloc.allocatedQuantity,
          baseUnit: preview.baseUnit,
        ),
      );

      targetBatch.currentQuantity -= alloc.allocatedQuantity;

      final sliceIdem = i == 0 ? idempotencyKey.trim() : '${idempotencyKey.trim()}-fefo-$i';
      final tx = StockTransactionItem(
        id: 'TX-FEFO-${DateTime.now().millisecondsSinceEpoch}-$i',
        storeId: _currentStoreId,
        productId: productId,
        productName: product['name'] as String,
        batchId: targetBatch.id,
        batchNumber: targetBatch.batchNumber,
        movementType: MovementType.salesReportOut,
        quantity: -alloc.allocatedQuantity,
        baseUnit: preview.baseUnit,
        sourceDocumentType: sourceDocumentType,
        sourceDocumentId: 'DOC-${DateTime.now().millisecondsSinceEpoch}',
        documentNumber: documentNumber.trim().toUpperCase(),
        idempotencyKey: sliceIdem,
        actorId: actorId ?? 'PHARMACIST-FEFO',
        notes: notes ?? 'FEFO automated outward sales allocation',
        isInferred: true,
      );
      _transactions.insert(0, tx);
    }

    notifyListeners();
    return null;
  }

  // --- Phase 6: Expiry Date Tracking, Near-Expiry Alerts & Waste Minimization ---

  /// Fetches expiry date risk bucket classification and at-risk capital metrics
  Future<ExpiryBucketResponse> fetchExpiryBucketsAsync({ExpiryTierEnum? tier}) async {
    // 1. Live Backend HTTP fetch if connected
    if (_isBackendConnected) {
      final queryParam = tier != null ? '?tier=${tier.code}' : '';
      final res = await _httpGet('/stores/$_currentStoreId/inventory/expiry-buckets$queryParam');
      if (res is Map<String, dynamic> && res['buckets'] is List) {
        return ExpiryBucketResponse.fromJson(res);
      }
    }

    // 2. Offline / Local In-Memory Calculation
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final storeBatches = _batches
        .where((b) => b.storeId == _currentStoreId && b.currentQuantity > 0)
        .toList();

    // Group batches by tier
    final Map<ExpiryTierEnum, List<ExpiryBatchDetail>> bucketBatches = {
      ExpiryTierEnum.expired: [],
      ExpiryTierEnum.critical30: [],
      ExpiryTierEnum.near60: [],
      ExpiryTierEnum.attention90: [],
      ExpiryTierEnum.safe: [],
    };

    final List<ExpiryBatchDetail> allDetails = [];

    for (final b in storeBatches) {
      final exp = DateTime(b.expiryDate.year, b.expiryDate.month, b.expiryDate.day);
      final daysDiff = exp.difference(today).inDays;
      final batchTier = ExpiryTierEnum.fromDays(daysDiff);

      final purchaseVal = b.currentQuantity * b.purchaseRate;
      final mrpVal = b.currentQuantity * b.mrp;

      final detail = ExpiryBatchDetail(
        batchId: b.id,
        batchNumber: b.batchNumber,
        productId: b.productId,
        productName: b.productName,
        expiryDate: b.expiryDate,
        daysUntilExpiry: daysDiff,
        tier: batchTier,
        currentQuantity: b.currentQuantity,
        baseUnit: b.baseUnit,
        mrp: b.mrp,
        purchaseRate: b.purchaseRate,
        atRiskPurchaseValue: purchaseVal,
        atRiskMrpValue: mrpVal,
      );

      bucketBatches[batchTier]!.add(detail);
      allDetails.add(detail);
    }

    // Sort all details by expiry date
    allDetails.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));

    // Construct bucket summaries
    final List<ExpiryBucketItem> bucketSummaries = [
      ExpiryBucketItem(
        tier: ExpiryTierEnum.expired,
        label: 'Expired Stock (Quarantine Needed)',
        daysMin: null,
        daysMax: -1,
        batchCount: bucketBatches[ExpiryTierEnum.expired]!.length,
        totalUnits: bucketBatches[ExpiryTierEnum.expired]!.fold(0.0, (s, i) => s + i.currentQuantity),
        totalPurchaseValue: bucketBatches[ExpiryTierEnum.expired]!.fold(0.0, (s, i) => s + i.atRiskPurchaseValue),
        totalMrpValue: bucketBatches[ExpiryTierEnum.expired]!.fold(0.0, (s, i) => s + i.atRiskMrpValue),
      ),
      ExpiryBucketItem(
        tier: ExpiryTierEnum.critical30,
        label: 'Critical Risk (<30 days)',
        daysMin: 0,
        daysMax: 30,
        batchCount: bucketBatches[ExpiryTierEnum.critical30]!.length,
        totalUnits: bucketBatches[ExpiryTierEnum.critical30]!.fold(0.0, (s, i) => s + i.currentQuantity),
        totalPurchaseValue: bucketBatches[ExpiryTierEnum.critical30]!.fold(0.0, (s, i) => s + i.atRiskPurchaseValue),
        totalMrpValue: bucketBatches[ExpiryTierEnum.critical30]!.fold(0.0, (s, i) => s + i.atRiskMrpValue),
      ),
      ExpiryBucketItem(
        tier: ExpiryTierEnum.near60,
        label: 'High Attention (31-60 days)',
        daysMin: 31,
        daysMax: 60,
        batchCount: bucketBatches[ExpiryTierEnum.near60]!.length,
        totalUnits: bucketBatches[ExpiryTierEnum.near60]!.fold(0.0, (s, i) => s + i.currentQuantity),
        totalPurchaseValue: bucketBatches[ExpiryTierEnum.near60]!.fold(0.0, (s, i) => s + i.atRiskPurchaseValue),
        totalMrpValue: bucketBatches[ExpiryTierEnum.near60]!.fold(0.0, (s, i) => s + i.atRiskMrpValue),
      ),
      ExpiryBucketItem(
        tier: ExpiryTierEnum.attention90,
        label: 'Medium Attention (61-90 days)',
        daysMin: 61,
        daysMax: 90,
        batchCount: bucketBatches[ExpiryTierEnum.attention90]!.length,
        totalUnits: bucketBatches[ExpiryTierEnum.attention90]!.fold(0.0, (s, i) => s + i.currentQuantity),
        totalPurchaseValue: bucketBatches[ExpiryTierEnum.attention90]!.fold(0.0, (s, i) => s + i.atRiskPurchaseValue),
        totalMrpValue: bucketBatches[ExpiryTierEnum.attention90]!.fold(0.0, (s, i) => s + i.atRiskMrpValue),
      ),
      ExpiryBucketItem(
        tier: ExpiryTierEnum.safe,
        label: 'Safe Stock (>90 days)',
        daysMin: 91,
        daysMax: null,
        batchCount: bucketBatches[ExpiryTierEnum.safe]!.length,
        totalUnits: bucketBatches[ExpiryTierEnum.safe]!.fold(0.0, (s, i) => s + i.currentQuantity),
        totalPurchaseValue: bucketBatches[ExpiryTierEnum.safe]!.fold(0.0, (s, i) => s + i.atRiskPurchaseValue),
        totalMrpValue: bucketBatches[ExpiryTierEnum.safe]!.fold(0.0, (s, i) => s + i.atRiskMrpValue),
      ),
    ];

    // Filter by tier if specified
    List<ExpiryBatchDetail> returnedBatches = allDetails;
    if (tier != null) {
      returnedBatches = allDetails.where((b) => b.tier == tier).toList();
    }

    // At risk includes EXPIRED, CRITICAL_30, and NEAR_60
    final atRiskBatches = allDetails.where(
      (b) => b.tier == ExpiryTierEnum.expired || b.tier == ExpiryTierEnum.critical30 || b.tier == ExpiryTierEnum.near60,
    );

    return ExpiryBucketResponse(
      storeId: _currentStoreId,
      totalActiveBatches: storeBatches.length,
      totalAtRiskUnits: atRiskBatches.fold(0.0, (s, b) => s + b.currentQuantity),
      totalAtRiskPurchaseValue: atRiskBatches.fold(0.0, (s, b) => s + b.atRiskPurchaseValue),
      totalAtRiskMrpValue: atRiskBatches.fold(0.0, (s, b) => s + b.atRiskMrpValue),
      buckets: bucketSummaries,
      batches: returnedBatches,
    );
  }

  /// Quarantines and segregates expired batch stock to prevent accidental dispensing
  Future<String?> segregateExpiredBatchAsync({
    required String batchId,
    required String idempotencyKey,
    String? reason,
    String? actorId,
    String? notes,
  }) async {
    final cleanIdem = idempotencyKey.trim();
    if (cleanIdem.isEmpty) {
      return 'Idempotency key is required';
    }

    // 1. Live Backend HTTP execution if connected
    if (_isBackendConnected) {
      final payload = {
        'idempotency_key': cleanIdem,
        'reason': reason ?? 'Quarantine expired stock',
        if (actorId != null && actorId.isNotEmpty) 'actor_id': actorId,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      };
      final res = await _httpPost('/stores/$_currentStoreId/batches/$batchId/segregate-expired', payload);
      if (res is Map<String, dynamic>) {
        if (res['error'] != null) {
          return res['error'] as String;
        }
        // Sync ledger and batches
        await syncAllFromBackend();
        return null;
      }
    }

    // 2. Offline / Local In-Memory Fallback
    final batchIndex = _batches.indexWhere((b) => b.id == batchId && b.storeId == _currentStoreId);
    if (batchIndex == -1) {
      return 'Batch $batchId not found in store $_currentStoreId';
    }

    final targetBatch = _batches[batchIndex];

    // Enforce expiry constraint
    if (!targetBatch.isExpired) {
      return 'Batch ${targetBatch.batchNumber} is not expired (${targetBatch.daysUntilExpiry} days remaining). Only expired stock can be quarantined.';
    }

    if (targetBatch.currentQuantity <= 0) {
      return 'Batch ${targetBatch.batchNumber} has no stock remaining to quarantine';
    }

    // Check duplicate idempotency key
    if (_transactions.any((t) => t.idempotencyKey == cleanIdem)) {
      return 'Duplicate idempotency key: $cleanIdem';
    }

    final segregatedQty = targetBatch.currentQuantity;

    // Deduct batch quantity to 0
    _batches[batchIndex] = BatchItem(
      id: targetBatch.id,
      storeId: targetBatch.storeId,
      productId: targetBatch.productId,
      productName: targetBatch.productName,
      batchNumber: targetBatch.batchNumber,
      expiryDate: targetBatch.expiryDate,
      mrp: targetBatch.mrp,
      purchaseRate: targetBatch.purchaseRate,
      currentQuantity: 0.0,
      baseUnit: targetBatch.baseUnit,
    );

    // Append audit adjustment to ledger
    final tx = StockTransactionItem(
      id: 'TX-SEG-${DateTime.now().millisecondsSinceEpoch}',
      storeId: _currentStoreId,
      productId: targetBatch.productId,
      productName: targetBatch.productName,
      batchId: targetBatch.id,
      batchNumber: targetBatch.batchNumber,
      movementType: MovementType.adjustmentSubtract,
      quantity: -segregatedQty,
      baseUnit: targetBatch.baseUnit,
      sourceDocumentType: SourceDocumentType.stockAudit,
      sourceDocumentId: 'QUAR-${DateTime.now().millisecondsSinceEpoch}',
      documentNumber: 'QUARANTINE-${targetBatch.batchNumber}',
      idempotencyKey: cleanIdem,
      actorId: actorId ?? 'PHARMACIST-QUARANTINE',
      notes: notes ?? reason ?? 'Expired inventory segregated and quarantined to prevent accidental dispensing',
      createdAt: DateTime.now(),
    );

    _transactions.insert(0, tx);
    notifyListeners();
    return null;
  }

  /// Returns inventory stock (e.g., near-expiry or recalled) back to the supplier
  Future<String?> returnToSupplierAsync({
    required String batchId,
    required String supplierId,
    required double quantity,
    required String returnReason,
    required String idempotencyKey,
    String? supplierInvoiceRef,
    String? creditNoteNumber,
    String? actorId,
    String? notes,
  }) async {
    final cleanIdem = idempotencyKey.trim();
    if (cleanIdem.isEmpty) {
      return 'Idempotency key is required';
    }
    if (quantity <= 0) {
      return 'Return quantity must be strictly greater than 0';
    }
    final cleanSupplierId = supplierId.trim();
    if (cleanSupplierId.isEmpty) {
      return 'Supplier ID is required';
    }

    // 1. Live Backend HTTP execution if connected
    if (_isBackendConnected) {
      final payload = {
        'supplier_id': cleanSupplierId,
        'quantity': quantity,
        'return_reason': returnReason,
        'idempotency_key': cleanIdem,
        if (supplierInvoiceRef != null && supplierInvoiceRef.isNotEmpty)
          'supplier_invoice_ref': supplierInvoiceRef,
        if (creditNoteNumber != null && creditNoteNumber.isNotEmpty)
          'credit_note_number': creditNoteNumber,
        if (actorId != null && actorId.isNotEmpty) 'actor_id': actorId,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      };
      final res = await _httpPost('/stores/$_currentStoreId/batches/$batchId/return-to-supplier', payload);
      if (res is Map<String, dynamic>) {
        if (res['error'] != null) {
          return res['error'] as String;
        }
        // Sync ledger and batches
        await syncAllFromBackend();
        return null;
      }
    }

    // 2. Offline / Local In-Memory Fallback
    final batchIndex = _batches.indexWhere((b) => b.id == batchId && b.storeId == _currentStoreId);
    if (batchIndex == -1) {
      return 'Batch $batchId not found in store $_currentStoreId';
    }

    final targetBatch = _batches[batchIndex];

    if (quantity > targetBatch.currentQuantity) {
      return 'Return quantity ($quantity) exceeds active batch quantity (${targetBatch.currentQuantity})';
    }

    // Check duplicate idempotency key
    if (_transactions.any((t) => t.idempotencyKey == cleanIdem)) {
      return 'Duplicate idempotency key: $cleanIdem';
    }

    // Deduct batch quantity
    final remainingQty = targetBatch.currentQuantity - quantity;
    _batches[batchIndex] = BatchItem(
      id: targetBatch.id,
      storeId: targetBatch.storeId,
      productId: targetBatch.productId,
      productName: targetBatch.productName,
      batchNumber: targetBatch.batchNumber,
      expiryDate: targetBatch.expiryDate,
      mrp: targetBatch.mrp,
      purchaseRate: targetBatch.purchaseRate,
      currentQuantity: remainingQty,
      baseUnit: targetBatch.baseUnit,
    );

    // Append return-out transaction to ledger
    final tx = StockTransactionItem(
      id: 'TX-RET-${DateTime.now().millisecondsSinceEpoch}',
      storeId: _currentStoreId,
      productId: targetBatch.productId,
      productName: targetBatch.productName,
      batchId: targetBatch.id,
      batchNumber: targetBatch.batchNumber,
      movementType: MovementType.returnOut,
      quantity: -quantity,
      baseUnit: targetBatch.baseUnit,
      sourceDocumentType: SourceDocumentType.supplierReturn,
      sourceDocumentId: supplierInvoiceRef ?? 'RET-${DateTime.now().millisecondsSinceEpoch}',
      documentNumber: creditNoteNumber ?? 'CN-${DateTime.now().millisecondsSinceEpoch}',
      idempotencyKey: cleanIdem,
      actorId: actorId ?? 'PHARMACIST-RETURN',
      notes: 'Returned $quantity ${targetBatch.baseUnit} to supplier $cleanSupplierId ($returnReason). ${notes ?? ''}'.trim(),
      createdAt: DateTime.now(),
    );

    _transactions.insert(0, tx);
    notifyListeners();
    return null;
  }

  // --- Phase 7: Low Stock Alerts, Reorder Thresholds & Safety Stock Rules ---

  /// Fetches low stock alerts and replenishment recommendations
  Future<LowStockAlertsResponseModel> fetchLowStockAlertsAsync({
    StockAlertSeverityEnum? severity,
    String? search,
  }) async {
    // 1. Live Backend HTTP fetch if connected
    if (_isBackendConnected) {
      final params = <String>[];
      if (severity != null) params.add('severity=${severity.code}');
      if (search != null && search.isNotEmpty) params.add('search=${Uri.encodeComponent(search)}');
      final queryStr = params.isNotEmpty ? '?${params.join('&')}' : '';
      final res = await _httpGet('/stores/$_currentStoreId/inventory/low-stock-alerts$queryStr');
      if (res is Map<String, dynamic> && res['alerts'] is List) {
        return LowStockAlertsResponseModel.fromJson(res);
      }
    }

    // 2. Offline / Local In-Memory Calculation
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final storeBatches = _batches.where((b) => b.storeId == _currentStoreId).toList();
    final Map<String, List<BatchItem>> grouped = {};
    for (final b in storeBatches) {
      grouped.putIfAbsent(b.productId, () => []).add(b);
    }

    final alerts = <LowStockAlertItemModel>[];
    int outOfStock = 0;
    int criticalLow = 0;
    int reorderRecommended = 0;
    int adequate = 0;
    double totalEstCost = 0.0;

    for (final prod in catalogueProducts) {
      final pid = prod['id'] as String;
      final pname = prod['name'] as String;
      final cat = prod['category'] as String?;
      final unit = prod['unit'] as String? ?? 'TABLET';
      final defaultThresh = prod['threshold'] as double? ?? 50.0;

      final custom = _customThresholds['$_currentStoreId-$pid'];
      final reorderPoint = custom?.reorderPoint ?? defaultThresh;
      final safetyStock = custom?.safetyStockLevel ?? (defaultThresh * 0.4);
      final reorderQty = custom?.reorderQuantity ?? 100.0;
      final leadDays = custom?.leadTimeDays ?? 2;

      final batches = grouped[pid] ?? [];
      double unexpStock = 0.0;
      double expStock = 0.0;
      double totalStock = 0.0;
      int activeBatches = 0;
      DateTime? earliestExp;
      double recentCost = 0.0;

      for (final b in batches) {
        if (b.currentQuantity <= 0) continue;
        activeBatches++;
        totalStock += b.currentQuantity;
        if (b.purchaseRate > 0) recentCost = b.purchaseRate;

        final expDate = DateTime(b.expiryDate.year, b.expiryDate.month, b.expiryDate.day);
        if (expDate.isBefore(today)) {
          expStock += b.currentQuantity;
        } else {
          unexpStock += b.currentQuantity;
          if (earliestExp == null || b.expiryDate.isBefore(earliestExp)) {
            earliestExp = b.expiryDate;
          }
        }
      }

      StockAlertSeverityEnum sev;
      if (unexpStock <= 0) {
        sev = StockAlertSeverityEnum.outOfStock;
        outOfStock++;
      } else if (unexpStock <= safetyStock) {
        sev = StockAlertSeverityEnum.criticalLow;
        criticalLow++;
      } else if (unexpStock <= reorderPoint) {
        sev = StockAlertSeverityEnum.reorderRecommended;
        reorderRecommended++;
      } else {
        sev = StockAlertSeverityEnum.adequate;
        adequate++;
      }

      double suggested = 0.0;
      double estCost = 0.0;
      if (sev != StockAlertSeverityEnum.adequate) {
        suggested = max(reorderQty, (reorderPoint * 2.0) - unexpStock);
        estCost = suggested * recentCost;
        totalEstCost += estCost;
      }

      if (severity != null && sev != severity) continue;
      if (search != null && search.isNotEmpty) {
        final term = search.toLowerCase();
        if (!pid.toLowerCase().contains(term) && !pname.toLowerCase().contains(term)) {
          continue;
        }
      }

      alerts.add(LowStockAlertItemModel(
        productId: pid,
        productName: pname,
        category: cat,
        baseUnit: unit,
        currentUnexpiredStock: unexpStock,
        expiredStock: expStock,
        totalStock: totalStock,
        safetyStockLevel: safetyStock,
        reorderPoint: reorderPoint,
        reorderQuantity: reorderQty,
        leadTimeDays: leadDays,
        severity: sev,
        suggestedReorderQuantity: suggested,
        estimatedUnitCost: recentCost,
        estimatedReorderCost: estCost,
        activeBatchCount: activeBatches,
        earliestExpiryDate: earliestExp,
      ));
    }

    alerts.sort((a, b) => a.severity.priority.compareTo(b.severity.priority));

    return LowStockAlertsResponseModel(
      storeId: _currentStoreId,
      totalMonitoredProducts: catalogueProducts.length,
      outOfStockCount: outOfStock,
      criticalLowCount: criticalLow,
      reorderRecommendedCount: reorderRecommended,
      adequateCount: adequate,
      totalEstimatedReorderCost: totalEstCost,
      alerts: alerts,
    );
  }

  /// Sets or updates store-specific reorder point and safety stock thresholds
  Future<String?> updateProductThresholdsAsync({
    required String productId,
    required double reorderPoint,
    required double safetyStockLevel,
    required double reorderQuantity,
    int leadTimeDays = 2,
    double? maxStockLevel,
    String? notes,
  }) async {
    if (safetyStockLevel > reorderPoint) {
      return 'Safety stock level cannot exceed reorder point';
    }

    // 1. Live Backend HTTP execution if connected
    if (_isBackendConnected) {
      final payload = {
        'reorder_point': reorderPoint,
        'safety_stock_level': safetyStockLevel,
        'reorder_quantity': reorderQuantity,
        'lead_time_days': leadTimeDays,
        if (maxStockLevel != null) 'max_stock_level': maxStockLevel,
        if (notes != null) 'notes': notes,
      };
      final res = await _httpPost('/stores/$_currentStoreId/inventory/thresholds/$productId', payload);
      if (res is Map<String, dynamic> && res['error'] != null) {
        return res['error'] as String;
      }
    }

    // 2. Update local custom threshold cache
    _customThresholds['$_currentStoreId-$productId'] = ProductThresholdConfigModel(
      storeId: _currentStoreId,
      productId: productId,
      reorderPoint: reorderPoint,
      safetyStockLevel: safetyStockLevel,
      reorderQuantity: reorderQuantity,
      leadTimeDays: leadTimeDays,
      maxStockLevel: maxStockLevel,
      notes: notes,
      updatedAt: DateTime.now(),
    );

    notifyListeners();
    return null;
  }

  /// Retrieves active threshold configuration for a product
  Future<ProductThresholdConfigModel> fetchProductThresholdAsync(String productId) async {
    if (_isBackendConnected) {
      final res = await _httpGet('/stores/$_currentStoreId/inventory/thresholds/$productId');
      if (res is Map<String, dynamic> && res['reorder_point'] != null) {
        final model = ProductThresholdConfigModel.fromJson(res);
        _customThresholds['$_currentStoreId-$productId'] = model;
        return model;
      }
    }

    final cached = _customThresholds['$_currentStoreId-$productId'];
    if (cached != null) return cached;

    final prod = catalogueProducts.firstWhere(
      (p) => p['id'] == productId,
      orElse: () => {'id': productId, 'name': 'Medicine', 'threshold': 50.0},
    );
    final defThreshold = (prod['threshold'] as num?)?.toDouble() ?? 50.0;

    return ProductThresholdConfigModel(
      storeId: _currentStoreId,
      productId: productId,
      productName: prod['name'] as String?,
      reorderPoint: defThreshold,
      safetyStockLevel: defThreshold * 0.4,
      reorderQuantity: 100.0,
      leadTimeDays: 2,
    );
  }

  // --- Phase 8: Physical Stock Audits, Cycle Counts & Discrepancies ---

  /// Fetches audit sessions for the store
  Future<List<AuditSessionModel>> fetchAuditSessionsAsync({
    AuditStatusEnum? status,
    AuditTypeEnum? type,
  }) async {
    if (_isBackendConnected) {
      final params = <String>[];
      if (status != null) params.add('status=${status.code}');
      if (type != null) params.add('audit_type=${type.code}');
      final queryStr = params.isNotEmpty ? '?${params.join('&')}' : '';
      final res = await _httpGet('/stores/$_currentStoreId/inventory/audits$queryStr');
      if (res is List) {
        final list = res.map((e) => AuditSessionModel.fromJson(e as Map<String, dynamic>)).toList();
        _auditSessions.clear();
        _auditSessions.addAll(list);
        notifyListeners();
        return list;
      }
    }

    var filtered = _auditSessions.where((s) => s.storeId == _currentStoreId);
    if (status != null) filtered = filtered.where((s) => s.status == status);
    if (type != null) filtered = filtered.where((s) => s.auditType == type);
    return filtered.toList();
  }

  /// Initiates a new audit session
  Future<AuditSessionModel?> createAuditSessionAsync({
    required String title,
    AuditTypeEnum auditType = AuditTypeEnum.cycleCount,
    List<String>? scopeProductIds,
    String? notes,
    String? assignedTo,
    String? createdBy,
  }) async {
    if (_isBackendConnected) {
      final payload = {
        'title': title,
        'audit_type': auditType.code,
        if (scopeProductIds != null) 'scope_product_ids': scopeProductIds,
        if (notes != null) 'notes': notes,
        if (assignedTo != null) 'assigned_to': assignedTo,
        if (createdBy != null) 'created_by': createdBy,
      };
      final res = await _httpPost('/stores/$_currentStoreId/inventory/audits', payload);
      if (res is Map<String, dynamic> && res['id'] != null) {
        final session = AuditSessionModel.fromJson(res);
        _auditSessions.insert(0, session);
        notifyListeners();
        return session;
      }
    }

    // Offline fallback
    final activeBatches = _batches.where((b) {
      if (b.storeId != _currentStoreId || b.currentQuantity <= 0) return false;
      if (scopeProductIds != null && scopeProductIds.isNotEmpty) {
        return scopeProductIds.contains(b.productId);
      }
      return true;
    }).toList();

    final newSession = AuditSessionModel(
      id: 'AUD-${DateTime.now().millisecondsSinceEpoch}',
      storeId: _currentStoreId,
      title: title,
      auditType: auditType,
      status: AuditStatusEnum.inProgress,
      scopeProductIds: scopeProductIds,
      totalItemsExpected: activeBatches.length,
      totalItemsCounted: 0,
      discrepancyCount: 0,
      surplusCount: 0,
      shortageCount: 0,
      netVarianceValue: 0.0,
      notes: notes,
      assignedTo: assignedTo,
      createdBy: createdBy,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    _auditSessions.insert(0, newSession);
    _auditSessionCounts[newSession.id] = [];
    notifyListeners();
    return newSession;
  }

  /// Fetches details and counts of an audit session
  Future<AuditSessionModel?> fetchAuditSessionByIdAsync(String auditId, {bool blind = false}) async {
    if (_isBackendConnected) {
      final res = await _httpGet('/stores/$_currentStoreId/inventory/audits/$auditId?blind=$blind');
      if (res is Map<String, dynamic> && res['id'] != null) {
        return AuditSessionModel.fromJson(res);
      }
    }

    final idx = _auditSessions.indexWhere((s) => s.id == auditId && s.storeId == _currentStoreId);
    if (idx == -1) return null;
    final session = _auditSessions[idx];
    final items = _auditSessionCounts[auditId] ?? [];

    List<AuditCountItemModel> mappedItems = items;
    if (blind && session.status != AuditStatusEnum.reconciled) {
      mappedItems = items.map((it) => AuditCountItemModel(
        id: it.id,
        auditId: it.auditId,
        storeId: it.storeId,
        productId: it.productId,
        productName: it.productName,
        batchId: it.batchId,
        batchNumber: it.batchNumber,
        expiryDate: it.expiryDate,
        systemQuantity: null,
        countedQuantity: it.countedQuantity,
        discrepancyQuantity: null,
        unitCost: null,
        discrepancyValue: null,
        discrepancyReason: it.discrepancyReason,
        recountRequired: it.recountRequired,
        notes: it.notes,
        countedBy: it.countedBy,
        status: it.status,
        createdAt: it.createdAt,
      )).toList();
    }

    return AuditSessionModel(
      id: session.id,
      storeId: session.storeId,
      title: session.title,
      auditType: session.auditType,
      status: session.status,
      scopeProductIds: session.scopeProductIds,
      totalItemsExpected: session.totalItemsExpected,
      totalItemsCounted: session.totalItemsCounted,
      discrepancyCount: session.discrepancyCount,
      surplusCount: session.surplusCount,
      shortageCount: session.shortageCount,
      netVarianceValue: session.netVarianceValue,
      notes: session.notes,
      assignedTo: session.assignedTo,
      createdBy: session.createdBy,
      approvedBy: session.approvedBy,
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
      reconciledAt: session.reconciledAt,
      items: mappedItems,
    );
  }

  /// Submits physical count records
  Future<AuditSessionModel?> recordAuditCountsAsync(
    String auditId,
    List<Map<String, dynamic>> items,
  ) async {
    if (_isBackendConnected) {
      final res = await _httpPost('/stores/$_currentStoreId/inventory/audits/$auditId/counts', {'items': items});
      if (res is Map<String, dynamic> && res['id'] != null) {
        final updated = AuditSessionModel.fromJson(res);
        final idx = _auditSessions.indexWhere((s) => s.id == auditId);
        if (idx != -1) _auditSessions[idx] = updated;
        notifyListeners();
        return updated;
      }
    }

    final idx = _auditSessions.indexWhere((s) => s.id == auditId && s.storeId == _currentStoreId);
    if (idx == -1) return null;

    final existingCounts = _auditSessionCounts[auditId] ?? [];
    for (final itemJson in items) {
      final pid = itemJson['product_id'] as String;
      final bnum = (itemJson['batch_number'] as String).trim().toUpperCase();
      final countedQty = (itemJson['counted_quantity'] as num).toDouble();
      final reason = itemJson['discrepancy_reason'] as String? ?? 'NORMAL_DISCREPANCY';

      final matchingBatch = _batches.firstWhere(
        (b) => b.storeId == _currentStoreId && b.productId == pid && b.batchNumber == bnum,
        orElse: () => BatchItem(
          id: '',
          storeId: _currentStoreId,
          productId: pid,
          productName: itemJson['product_name'] as String? ?? pid,
          batchNumber: bnum,
          expiryDate: DateTime.now(),
          mrp: 0.0,
          purchaseRate: 0.0,
          currentQuantity: 0.0,
        ),
      );

      final sysQty = matchingBatch.id.isNotEmpty ? matchingBatch.currentQuantity : 0.0;
      final unitCost = matchingBatch.purchaseRate;
      final delta = countedQty - sysQty;
      final val = delta * unitCost;

      final countItem = AuditCountItemModel(
        id: 'CNT-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(999)}',
        auditId: auditId,
        storeId: _currentStoreId,
        productId: pid,
        productName: itemJson['product_name'] as String? ?? matchingBatch.productName,
        batchId: matchingBatch.id.isNotEmpty ? matchingBatch.id : null,
        batchNumber: bnum,
        expiryDate: matchingBatch.id.isNotEmpty ? matchingBatch.expiryDate : null,
        systemQuantity: sysQty,
        countedQuantity: countedQty,
        discrepancyQuantity: delta,
        unitCost: unitCost,
        discrepancyValue: val,
        discrepancyReason: reason,
        notes: itemJson['notes'] as String?,
        countedBy: itemJson['counted_by'] as String?,
        status: 'COUNTED',
        createdAt: DateTime.now(),
      );

      final existingIdx = existingCounts.indexWhere((c) => c.productId == pid && c.batchNumber == bnum);
      if (existingIdx != -1) {
        existingCounts[existingIdx] = countItem;
      } else {
        existingCounts.add(countItem);
      }
    }
    _auditSessionCounts[auditId] = existingCounts;

    final surplusC = existingCounts.where((c) => (c.discrepancyQuantity ?? 0) > 0).length;
    final shortageC = existingCounts.where((c) => (c.discrepancyQuantity ?? 0) < 0).length;
    final netVal = existingCounts.fold<double>(0.0, (acc, c) => acc + (c.discrepancyValue ?? 0.0));

    final oldSession = _auditSessions[idx];
    final updatedSession = AuditSessionModel(
      id: oldSession.id,
      storeId: oldSession.storeId,
      title: oldSession.title,
      auditType: oldSession.auditType,
      status: AuditStatusEnum.underReview,
      scopeProductIds: oldSession.scopeProductIds,
      totalItemsExpected: oldSession.totalItemsExpected,
      totalItemsCounted: existingCounts.length,
      discrepancyCount: surplusC + shortageC,
      surplusCount: surplusC,
      shortageCount: shortageC,
      netVarianceValue: netVal,
      notes: oldSession.notes,
      assignedTo: oldSession.assignedTo,
      createdBy: oldSession.createdBy,
      createdAt: oldSession.createdAt,
      updatedAt: DateTime.now(),
      items: existingCounts,
    );

    _auditSessions[idx] = updatedSession;
    notifyListeners();
    return updatedSession;
  }

  /// Fetches discrepancy report with variance valuation
  Future<AuditDiscrepancyReportModel?> fetchAuditDiscrepanciesAsync(String auditId) async {
    if (_isBackendConnected) {
      final res = await _httpGet('/stores/$_currentStoreId/inventory/audits/$auditId/discrepancies');
      if (res is Map<String, dynamic> && res['audit_id'] != null) {
        return AuditDiscrepancyReportModel.fromJson(res);
      }
    }

    final idx = _auditSessions.indexWhere((s) => s.id == auditId && s.storeId == _currentStoreId);
    if (idx == -1) return null;
    final session = _auditSessions[idx];
    final counts = _auditSessionCounts[auditId] ?? [];

    final discrepant = counts.where((c) => (c.discrepancyQuantity ?? 0) != 0).toList();
    final surplusVal = discrepant.where((c) => (c.discrepancyQuantity ?? 0) > 0).fold<double>(0.0, (acc, c) => acc + (c.discrepancyValue ?? 0.0));
    final shortageVal = discrepant.where((c) => (c.discrepancyQuantity ?? 0) < 0).fold<double>(0.0, (acc, c) => acc + (c.discrepancyValue ?? 0.0).abs());

    return AuditDiscrepancyReportModel(
      auditId: auditId,
      storeId: _currentStoreId,
      title: session.title,
      status: session.status,
      totalCounted: counts.length,
      totalDiscrepant: discrepant.length,
      totalSurplusValue: surplusVal,
      totalShortageValue: shortageVal,
      netVarianceValue: surplusVal - shortageVal,
      cleanItemsCount: counts.length - discrepant.length,
      discrepantItems: discrepant,
    );
  }

  /// Reconciles audit session, posts adjusting stock transactions, and updates ledger
  Future<AuditReconcileResponseModel?> reconcileAuditSessionAsync({
    required String auditId,
    required String approvedBy,
    required String idempotencyKey,
    String? notes,
  }) async {
    if (_isBackendConnected) {
      final payload = {
        'approved_by': approvedBy,
        'idempotency_key': idempotencyKey,
        if (notes != null) 'notes': notes,
      };
      final res = await _httpPost('/stores/$_currentStoreId/inventory/audits/$auditId/reconcile', payload);
      if (res is Map<String, dynamic> && res['audit_id'] != null) {
        final resp = AuditReconcileResponseModel.fromJson(res);
        final idx = _auditSessions.indexWhere((s) => s.id == auditId);
        if (idx != -1) {
          final s = _auditSessions[idx];
          _auditSessions[idx] = AuditSessionModel(
            id: s.id,
            storeId: s.storeId,
            title: s.title,
            auditType: s.auditType,
            status: AuditStatusEnum.reconciled,
            scopeProductIds: s.scopeProductIds,
            totalItemsExpected: s.totalItemsExpected,
            totalItemsCounted: s.totalItemsCounted,
            discrepancyCount: s.discrepancyCount,
            surplusCount: s.surplusCount,
            shortageCount: s.shortageCount,
            netVarianceValue: s.netVarianceValue,
            notes: s.notes,
            assignedTo: s.assignedTo,
            createdBy: s.createdBy,
            approvedBy: approvedBy,
            createdAt: s.createdAt,
            updatedAt: DateTime.now(),
            reconciledAt: DateTime.now(),
          );
        }
        notifyListeners();
        return resp;
      }
    }

    final idx = _auditSessions.indexWhere((s) => s.id == auditId && s.storeId == _currentStoreId);
    if (idx == -1) return null;
    final session = _auditSessions[idx];
    final counts = _auditSessionCounts[auditId] ?? [];
    final discrepant = counts.where((c) => (c.discrepancyQuantity ?? 0) != 0).toList();

    double totalSurplus = 0.0;
    double totalShortage = 0.0;
    double netFinancial = 0.0;
    final List<String> txIds = [];

    for (final it in discrepant) {
      final delta = it.discrepancyQuantity ?? 0.0;
      final txId = 'TXN-AUD-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(999)}';
      txIds.add(txId);

      if (delta > 0) {
        totalSurplus += delta;
        netFinancial += (it.discrepancyValue ?? 0.0);
      } else {
        totalShortage += delta.abs();
        netFinancial += (it.discrepancyValue ?? 0.0);
      }

      final bIdx = _batches.indexWhere((b) => b.storeId == _currentStoreId && b.productId == it.productId && b.batchNumber == it.batchNumber);
      if (bIdx != -1) {
        final ob = _batches[bIdx];
        _batches[bIdx] = BatchItem(
          id: ob.id,
          storeId: ob.storeId,
          productId: ob.productId,
          productName: ob.productName,
          batchNumber: ob.batchNumber,
          expiryDate: ob.expiryDate,
          mrp: ob.mrp,
          purchaseRate: ob.purchaseRate,
          currentQuantity: max(0.0, ob.currentQuantity + delta),
          baseUnit: ob.baseUnit,
        );
      }

      _transactions.insert(0, StockTransactionItem(
        id: txId,
        storeId: _currentStoreId,
        productId: it.productId,
        productName: it.productName ?? it.productId,
        batchId: it.batchId,
        batchNumber: it.batchNumber,
        movementType: delta > 0 ? MovementType.adjustmentAdd : MovementType.adjustmentSubtract,
        quantity: delta,
        baseUnit: 'TABLET',
        sourceDocumentType: SourceDocumentType.stockAudit,
        sourceDocumentId: auditId,
        documentNumber: session.title,
        idempotencyKey: '$idempotencyKey-${it.id}',
        actorId: approvedBy,
        notes: 'Audit discrepancy reconciliation (${it.discrepancyReason ?? 'NORMAL_DISCREPANCY'}). Approved by $approvedBy',
        createdAt: DateTime.now(),
      ));
    }

    _auditSessions[idx] = AuditSessionModel(
      id: session.id,
      storeId: session.storeId,
      title: session.title,
      auditType: session.auditType,
      status: AuditStatusEnum.reconciled,
      scopeProductIds: session.scopeProductIds,
      totalItemsExpected: session.totalItemsExpected,
      totalItemsCounted: session.totalItemsCounted,
      discrepancyCount: session.discrepancyCount,
      surplusCount: session.surplusCount,
      shortageCount: session.shortageCount,
      netVarianceValue: session.netVarianceValue,
      notes: session.notes,
      assignedTo: session.assignedTo,
      createdBy: session.createdBy,
      approvedBy: approvedBy,
      createdAt: session.createdAt,
      updatedAt: DateTime.now(),
      reconciledAt: DateTime.now(),
    );

    notifyListeners();

    return AuditReconcileResponseModel(
      auditId: auditId,
      status: 'RECONCILED',
      reconciledAt: DateTime.now(),
      approvedBy: approvedBy,
      reconciledItemsCount: discrepant.length,
      ledgerTransactionsPosted: txIds.length,
      totalSurplusQty: totalSurplus,
      totalShortageQty: totalShortage,
      netFinancialAdjustment: netFinancial,
      transactionIds: txIds,
    );
  }

  /// Cancels an audit session
  Future<AuditSessionModel?> cancelAuditSessionAsync(String auditId, {String? reason}) async {
    if (_isBackendConnected) {
      final query = reason != null ? '?reason=${Uri.encodeComponent(reason)}' : '';
      final res = await _httpPost('/stores/$_currentStoreId/inventory/audits/$auditId/cancel$query', {});
      if (res is Map<String, dynamic> && res['id'] != null) {
        final updated = AuditSessionModel.fromJson(res);
        final idx = _auditSessions.indexWhere((s) => s.id == auditId);
        if (idx != -1) _auditSessions[idx] = updated;
        notifyListeners();
        return updated;
      }
    }

    final idx = _auditSessions.indexWhere((s) => s.id == auditId && s.storeId == _currentStoreId);
    if (idx == -1) return null;
    final s = _auditSessions[idx];
    final updated = AuditSessionModel(
      id: s.id,
      storeId: s.storeId,
      title: s.title,
      auditType: s.auditType,
      status: AuditStatusEnum.cancelled,
      scopeProductIds: s.scopeProductIds,
      totalItemsExpected: s.totalItemsExpected,
      totalItemsCounted: s.totalItemsCounted,
      discrepancyCount: s.discrepancyCount,
      surplusCount: s.surplusCount,
      shortageCount: s.shortageCount,
      netVarianceValue: s.netVarianceValue,
      notes: reason != null ? '${s.notes ?? ''} | Cancelled: $reason'.trim() : s.notes,
      assignedTo: s.assignedTo,
      createdBy: s.createdBy,
      createdAt: s.createdAt,
      updatedAt: DateTime.now(),
    );
    _auditSessions[idx] = updated;
    notifyListeners();
    return updated;
  }

  void _seedInitialData() {
    final now = DateTime.now();

    // Store 1: Balaji Medical
    final b1 = BatchItem(
      id: 'B101',
      storeId: 'STR-001',
      productId: 'PROD-001',
      productName: 'Dolo 650mg Tablet',
      batchNumber: 'DL-24A01',
      expiryDate: now.add(const Duration(days: 280)), // 2027
      mrp: 32.50,
      purchaseRate: 22.00,
      currentQuantity: 320.0,
      baseUnit: 'TABLET',
    );

    final b2 = BatchItem(
      id: 'B102',
      storeId: 'STR-001',
      productId: 'PROD-001',
      productName: 'Dolo 650mg Tablet',
      batchNumber: 'DL-23J88',
      expiryDate: now.add(const Duration(days: 22)), // Expiring soon (<30 days)
      mrp: 30.00,
      purchaseRate: 20.50,
      currentQuantity: 45.0,
      baseUnit: 'TABLET',
    );

    final b3 = BatchItem(
      id: 'B103',
      storeId: 'STR-001',
      productId: 'PROD-002',
      productName: 'Augmentin 625 Duo Tablet',
      batchNumber: 'AG-9821',
      expiryDate: now.add(const Duration(days: 190)),
      mrp: 204.00,
      purchaseRate: 155.00,
      currentQuantity: 28.0, // Low stock (< 30)
      baseUnit: 'TABLET',
    );

    final b4 = BatchItem(
      id: 'B104',
      storeId: 'STR-001',
      productId: 'PROD-003',
      productName: 'Azithral 500mg Tablet',
      batchNumber: 'AZ-4410',
      expiryDate: now.subtract(const Duration(days: 5)), // Expired!
      mrp: 119.50,
      purchaseRate: 85.00,
      currentQuantity: 15.0,
      baseUnit: 'TABLET',
    );

    final b5 = BatchItem(
      id: 'B105',
      storeId: 'STR-001',
      productId: 'PROD-004',
      productName: 'Pan-D Capsule',
      batchNumber: 'PD-1102',
      expiryDate: now.add(const Duration(days: 410)),
      mrp: 199.00,
      purchaseRate: 140.00,
      currentQuantity: 110.0,
      baseUnit: 'CAPSULE',
    );

    final b6 = BatchItem(
      id: 'B106',
      storeId: 'STR-001',
      productId: 'PROD-006',
      productName: 'Ascoril D Plus Cough Syrup (100ml)',
      batchNumber: 'ASC-771',
      expiryDate: now.add(const Duration(days: 340)),
      mrp: 135.00,
      purchaseRate: 98.00,
      currentQuantity: 24.0,
      baseUnit: 'BOTTLE',
    );

    _batches.addAll([b1, b2, b3, b4, b5, b6]);

    // Initial Authoritative Transactions for Store 1
    _transactions.addAll([
      StockTransactionItem(
        id: 'TX-1001',
        storeId: 'STR-001',
        productId: 'PROD-001',
        productName: 'Dolo 650mg Tablet',
        batchId: 'B101',
        batchNumber: 'DL-24A01',
        movementType: MovementType.purchaseIn,
        quantity: 350.0,
        baseUnit: 'TABLET',
        sourceDocumentType: SourceDocumentType.purchaseInvoice,
        sourceDocumentId: 'INV-2026-0042',
        documentNumber: 'INV/AP/24-991',
        idempotencyKey: 'IDEM-INIT-1001',
        actorId: 'USER-ADMIN',
        notes: 'Inward purchase from Micro Labs distributor',
        createdAt: now.subtract(const Duration(days: 5)),
      ),
      StockTransactionItem(
        id: 'TX-1002',
        storeId: 'STR-001',
        productId: 'PROD-001',
        productName: 'Dolo 650mg Tablet',
        batchId: 'B101',
        batchNumber: 'DL-24A01',
        movementType: MovementType.salesReportOut,
        quantity: -30.0,
        baseUnit: 'TABLET',
        sourceDocumentType: SourceDocumentType.salesReport,
        sourceDocumentId: 'REP-2026-1014',
        documentNumber: 'EOD-SALES-1014',
        idempotencyKey: 'IDEM-INIT-1002',
        actorId: 'POS-CASHIER',
        notes: 'End-of-day sales report scan deduction',
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      StockTransactionItem(
        id: 'TX-1003',
        storeId: 'STR-001',
        productId: 'PROD-002',
        productName: 'Augmentin 625 Duo Tablet',
        batchId: 'B103',
        batchNumber: 'AG-9821',
        movementType: MovementType.purchaseIn,
        quantity: 50.0,
        baseUnit: 'TABLET',
        sourceDocumentType: SourceDocumentType.purchaseInvoice,
        sourceDocumentId: 'INV-2026-0038',
        documentNumber: 'INV/GSK/8812',
        idempotencyKey: 'IDEM-INIT-1003',
        actorId: 'USER-ADMIN',
        notes: 'Purchase inward from GSK India',
        createdAt: now.subtract(const Duration(days: 8)),
      ),
      StockTransactionItem(
        id: 'TX-1004',
        storeId: 'STR-001',
        productId: 'PROD-002',
        productName: 'Augmentin 625 Duo Tablet',
        batchId: 'B103',
        batchNumber: 'AG-9821',
        movementType: MovementType.salesReportOut,
        quantity: -22.0,
        baseUnit: 'TABLET',
        sourceDocumentType: SourceDocumentType.salesReport,
        sourceDocumentId: 'REP-2026-1015',
        documentNumber: 'EOD-SALES-1015',
        idempotencyKey: 'IDEM-INIT-1004',
        actorId: 'POS-CASHIER',
        notes: 'Sales deduction via EOD report',
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      StockTransactionItem(
        id: 'TX-1005',
        storeId: 'STR-001',
        productId: 'PROD-004',
        productName: 'Pan-D Capsule',
        batchId: 'B105',
        batchNumber: 'PD-1102',
        movementType: MovementType.adjustmentAdd,
        quantity: 10.0,
        baseUnit: 'CAPSULE',
        sourceDocumentType: SourceDocumentType.stockAudit,
        sourceDocumentId: 'AUD-2026-1010',
        documentNumber: 'AUDIT/OCT/01',
        idempotencyKey: 'IDEM-INIT-1005',
        actorId: 'STORE-MANAGER',
        notes: 'Physical count surplus identified during weekly count',
        createdAt: now.subtract(const Duration(hours: 18)),
      ),
    ]);

    // Store 2: Apollo Corner Pharmacy
    final b201 = BatchItem(
      id: 'B201',
      storeId: 'STR-002',
      productId: 'PROD-001',
      productName: 'Dolo 650mg Tablet',
      batchNumber: 'DL-24B02',
      expiryDate: now.add(const Duration(days: 300)),
      mrp: 32.50,
      purchaseRate: 22.00,
      currentQuantity: 150.0,
      baseUnit: 'TABLET',
    );
    _batches.add(b201);
  }
}
