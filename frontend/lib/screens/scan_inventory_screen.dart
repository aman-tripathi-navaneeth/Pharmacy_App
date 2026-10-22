import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../api_session.dart';
import '../utils/responsive.dart';
import '../widgets/app_shell.dart';

class ScanInventoryScreen extends StatefulWidget {
  const ScanInventoryScreen({super.key, required this.userRole, this.storeId});

  final String userRole;
  final String? storeId;

  @override
  State<ScanInventoryScreen> createState() => _ScanInventoryScreenState();
}

class _ScanInventoryScreenState extends State<ScanInventoryScreen> {
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  final _scannerController =
      kIsWeb || (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS)
      ? MobileScannerController()
      : null;
  final _barcodeController = TextEditingController();
  List<dynamic> _shops = [];
  List<dynamic> _items = [];
  String? _selectedStoreId;
  bool _isLoading = true;
  bool _isHandlingScan = false;
  String? _error;

  bool get _isAdmin => widget.userRole == 'SUPER_ADMIN';
  bool get _scannerSupported =>
      kIsWeb || (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS);

  @override
  void initState() {
    super.initState();
    _selectedStoreId = _isAdmin
        ? null
        : widget.storeId ?? ApiSession.user['ownerStoreId'] as String?;
    if (_isAdmin) {
      _loadShops();
    } else if (_selectedStoreId != null) {
      _loadItems();
    } else {
      _isLoading = false;
      _error = 'Your account is not linked to a shop.';
    }
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  Uri _itemsUri({String? itemId}) {
    final path = itemId == null
        ? '$_apiBaseUrl/api/inventory/items'
        : '$_apiBaseUrl/api/inventory/items/$itemId';
    return Uri.parse(path).replace(
      queryParameters: _isAdmin && _selectedStoreId != null
          ? {'storeId': _selectedStoreId!}
          : null,
    );
  }

  Future<void> _loadShops() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await http
          .get(
            Uri.parse('$_apiBaseUrl/api/admin/shops?page=1&pageSize=50'),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('Could not load shop list');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (mounted) {
        setState(() => _shops = data['items'] as List<dynamic>? ?? []);
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load shops. Try again.');
      debugPrint('Failed to load shops for inventory: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadItems() async {
    if (_selectedStoreId == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await http
          .get(_itemsUri(), headers: ApiSession.headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('Could not load inventory');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (mounted) {
        setState(() => _items = data['items'] as List<dynamic>? ?? []);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not load inventory. Try again.');
      }
      debugPrint('Failed to load inventory: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_isHandlingScan || _selectedStoreId == null) return;
    String? value;
    for (final barcode in capture.barcodes) {
      if (barcode.rawValue != null && barcode.rawValue!.trim().isNotEmpty) {
        value = barcode.rawValue!.trim();
        break;
      }
    }
    if (value == null) return;

    _isHandlingScan = true;
    _barcodeController.text = value;
    try {
      await _scannerController?.stop();
    } catch (_) {
      // The camera may not be available on desktop or before permission is granted.
    }
    await _showItemForm(barcode: value);
    _isHandlingScan = false;
    if (mounted && _selectedStoreId != null) {
      try {
        await _scannerController?.start();
      } catch (_) {
        // Manual barcode entry remains available when the camera cannot restart.
      }
    }
  }

  String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<void> _showItemForm({
    String? barcode,
    Map<String, dynamic>? item,
  }) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(
      text: item?['medicineName']?.toString() ?? '',
    );
    final codeController = TextEditingController(
      text: item?['barcode']?.toString() ?? barcode ?? '',
    );
    final batchController = TextEditingController(
      text: item?['batchNumber']?.toString() ?? '',
    );
    final quantityController = TextEditingController(
      text: item?['quantity']?.toString() ?? '1',
    );
    final priceController = TextEditingController(
      text: item?['sellingPrice']?.toString() ?? '',
    );
    final reorderController = TextEditingController(
      text: item?['reorderLevel']?.toString() ?? '10',
    );
    final initialExpiry =
        DateTime.tryParse(item?['expiryDate']?.toString() ?? '') ??
        DateTime.now().add(const Duration(days: 365));
    final expiryController = TextEditingController(
      text: _formatDate(initialExpiry),
    );

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          item == null ? 'Add inventory item' : 'Edit inventory item',
        ),
        content: SizedBox(
          width: dialogWidth(dialogContext, 440),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _formField(nameController, 'Medicine name'),
                  _formField(codeController, 'Barcode'),
                  _formField(batchController, 'Batch number'),
                  _formField(
                    quantityController,
                    'Quantity',
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        int.tryParse(value ?? '') == null ||
                            int.parse(value!) < 0
                        ? 'Enter a valid non-negative quantity'
                        : null,
                  ),
                  _formField(
                    priceController,
                    'Selling price',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) =>
                        double.tryParse(value ?? '') == null ||
                            double.parse(value!) < 0
                        ? 'Enter a valid price'
                        : null,
                  ),
                  _formField(
                    reorderController,
                    'Low-stock threshold',
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        int.tryParse(value ?? '') == null ||
                            int.parse(value!) < 0
                        ? 'Enter a valid threshold'
                        : null,
                  ),
                  TextFormField(
                    controller: expiryController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Expiry date',
                      suffixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    onTap: () async {
                      final selected = await showDatePicker(
                        context: dialogContext,
                        initialDate:
                            DateTime.tryParse(expiryController.text) ??
                            initialExpiry,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (selected != null) {
                        expiryController.text = _formatDate(selected);
                      }
                    },
                    validator: (value) => DateTime.tryParse(value ?? '') == null
                        ? 'Select an expiry date'
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(dialogContext).pop({
                'medicineName': nameController.text.trim(),
                'barcode': codeController.text.trim(),
                'batchNumber': batchController.text.trim(),
                'quantity': int.parse(quantityController.text),
                'sellingPrice': double.parse(priceController.text),
                'reorderLevel': int.parse(reorderController.text),
                'expiryDate': DateTime.parse(expiryController.text)
                    .toIso8601String(),
              });
            },
            child: Text(item == null ? 'Save item' : 'Save changes'),
          ),
        ],
      ),
    );

    for (final controller in [
      nameController,
      codeController,
      batchController,
      quantityController,
      priceController,
      reorderController,
      expiryController,
    ]) {
      controller.dispose();
    }

    if (result == null || _selectedStoreId == null) return;
    await _saveItem(result, item);
  }

  Widget _formField(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label),
        validator:
            validator ??
            (value) =>
                value == null || value.trim().isEmpty ? 'Required' : null,
      ),
    );
  }

  Future<void> _saveItem(
    Map<String, dynamic> values,
    Map<String, dynamic>? item,
  ) async {
    try {
      final body = {...values, if (_isAdmin) 'storeId': _selectedStoreId};
      final uri = item == null
          ? _itemsUri()
          : _itemsUri(itemId: item['_id'].toString());
      final response = item == null
          ? await http.post(
              uri,
              headers: ApiSession.headers,
              body: jsonEncode(body),
            )
          : await http.patch(
              uri,
              headers: ApiSession.headers,
              body: jsonEncode(body),
            );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final message = data['message'];
        throw Exception(
          message is String ? message : 'Could not save inventory item',
        );
      }
      await _loadItems();
      if (item == null && ApiSession.notificationSoundsEnabled) {
        SystemSound.play(SystemSoundType.alert);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              item == null ? 'Inventory item added' : 'Inventory item updated',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Save failed: ${error.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }
    }
  }

  Future<void> _openTemplatePicker() async {
    if (_selectedStoreId == null) return;
    try {
      final response = await http
          .get(
            Uri.parse('$_apiBaseUrl/api/inventory/templates'),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (response.statusCode != 200) {
        throw Exception('Could not load templates');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final templates = data['templates'] as List<dynamic>? ?? [];
      if (templates.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No templates available')));
        return;
      }
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Add stock from template'),
          children: [
            for (final template in templates)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.of(dialogContext)
                        .pop(template as Map<String, dynamic>),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template['name']?.toString() ?? 'Template',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        template['description']?.toString() ?? '',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      Text(
                        '${(template['items'] as List<dynamic>?)?.length ?? 0} items ready to import',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF0B4F3A),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
      if (selected != null) await _importTemplate(selected);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load templates. Try again.')),
        );
      }
      debugPrint('Template load failed: $error');
    }
  }

  Future<void> _importTemplate(Map<String, dynamic> template) async {
    final items = template['items'] as List<dynamic>? ?? [];
    final quantityController = TextEditingController(text: '0');
    final batchController = TextEditingController(
      text:
          'B${DateTime.now().toIso8601String().substring(2, 10).replaceAll('-', '')}',
    );
    final monthsController = TextEditingController(text: '12');
    final formKey = GlobalKey<FormState>();
    // Owner tick-list: everything is ticked by default; untick what the
    // shop does not stock so only real shelf items are imported.
    final Set<String> selectedBarcodes = {
      for (final item in items)
        if (item is Map<String, dynamic>) item['barcode']?.toString() ?? '',
    }..remove('');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Import "${template['name']}"'),
        content: SizedBox(
          width: dialogWidth(dialogContext, 440),
          child: StatefulBuilder(
            builder: (dialogContext, setDialogState) => Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tick only the items your shop stocks. Prices, expiry and quantity can be edited after import.',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: selectedBarcodes.length == items.length,
                        onChanged: (all) => setDialogState(() {
                          if (all == true) {
                            selectedBarcodes
                              ..clear()
                              ..addAll(
                                [
                                  for (final item in items)
                                    if (item is Map<String, dynamic>)
                                      item['barcode']?.toString() ?? '',
                                ]..remove(''),
                              );
                          } else {
                            selectedBarcodes.clear();
                          }
                        }),
                      ),
                      Text(
                        '${selectedBarcodes.length} of ${items.length} items selected',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  Flexible(
                    child: SizedBox(
                      height: 200,
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final item in items)
                            if (item is Map<String, dynamic>)
                              CheckboxListTile(
                                dense: true,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                value: selectedBarcodes.contains(
                                  item['barcode']?.toString(),
                                ),
                                title: Text(
                                  item['medicineName']?.toString() ?? 'Item',
                                ),
                                subtitle: Text('MRP ₹${item['sellingPrice']}'),
                                onChanged: (checked) => setDialogState(() {
                                  final code =
                                      item['barcode']?.toString() ?? '';
                                  if (checked == true) {
                                    selectedBarcodes.add(code);
                                  } else {
                                    selectedBarcodes.remove(code);
                                  }
                                }),
                              ),
                        ],
                      ),
                    ),
                  ),
                  _formField(
                    quantityController,
                    'Inward quantity per item',
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        int.tryParse(value ?? '') == null ||
                            int.parse(value!) < 0
                        ? 'Enter a valid quantity'
                        : null,
                  ),
                  _formField(batchController, 'Batch prefix'),
                  _formField(
                    monthsController,
                    'Default expiry (months from today)',
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        int.tryParse(value ?? '') == null ||
                            (int.parse(value!) < 1 || int.parse(value) > 60)
                        ? '1 to 60 months'
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogContext).pop(true);
              }
            },
            child: const Text('Import selection'),
          ),
        ],
      ),
    );
    // Capture before dispose; the dialog is gone either way.
    final quantityText = quantityController.text.trim();
    final batchText = batchController.text.trim();
    final monthsText = monthsController.text.trim();
    final chosenBarcodes = selectedBarcodes.toList();
    quantityController.dispose();
    batchController.dispose();
    monthsController.dispose();
    if (confirmed != true) return;

    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/api/inventory/import-template'),
            headers: ApiSession.headers,
            body: jsonEncode({
              'templateId': template['id'],
              if (_isAdmin) 'storeId': _selectedStoreId,
              'quantity': int.parse(quantityText),
              'batchNumber': batchText,
              'expiryMonthsAhead': int.parse(monthsText),
              'selectedBarcodes': chosenBarcodes,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final created = data['created'] as int? ?? 0;
        final skipped = data['skipped'] as List<dynamic>? ?? const [];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              skipped.isEmpty
                  ? '$created items imported. Edit prices and expiry anytime.'
                  : '$created imported · ${skipped.length} already in stock',
            ),
          ),
        );
        await _loadItems();
      } else {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message']?.toString() ?? 'Import failed'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import failed. Try again.')),
        );
      }
      debugPrint('Template import failed: $error');
    }
  }

  /// OCR flow: pick a supplier-bill photo, read it with the server OCR
  /// engine, let the owner tick/fix the suggested lines, then bulk add.
  Future<void> _scanSupplierBill() async {
    if (_selectedStoreId == null) return;
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.image,
        dialogTitle: 'Pick a photo of the supplier bill',
      );
      if (picked.isEmpty) return;
      final file = picked.single;
      final bytes = await file.xFile.readAsBytes();

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_apiBaseUrl/api/inventory/scan-bill').replace(
          queryParameters: _isAdmin ? {'storeId': _selectedStoreId!} : null,
        ),
      );
      request.headers['Authorization'] = ApiSession.accessToken == null
          ? ''
          : 'Bearer ${ApiSession.accessToken}';
      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: file.name),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reading the bill photo...')),
      );
      final streamed = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final response = await http.Response.fromStream(streamed);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final lines = data['lines'] as List<dynamic>? ?? [];
        if (lines.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No readable lines found. Add stock manually.'),
            ),
          );
          return;
        }
        await _showOcrReview(lines);
      } else {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message']?.toString() ?? 'Bill scan failed'),
          ),
        );
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bill scan timed out. Try again.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bill scan failed. Try again.')),
        );
      }
      debugPrint('Bill scan failed: $error');
    }
  }

  Future<void> _showOcrReview(List<dynamic> lines) async {
    // Lines with a parsed price start ticked; lines without one are shown
    // ticked off so the owner sets a real price for them first.
    final Set<int> selected = {
      for (var i = 0; i < lines.length; i++)
        if ((lines[i] as Map<String, dynamic>)['sellingPrice'] != null) i,
    };
    final quantityControllers = [
      for (final line in lines)
        TextEditingController(
          text: (line as Map<String, dynamic>)['quantity']?.toString() ?? '0',
        ),
    ];
    final priceControllers = [
      for (final line in lines)
        TextEditingController(text: line['sellingPrice']?.toString() ?? ''),
    ];

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Stock found on the bill'),
          content: SizedBox(
            width: dialogWidth(dialogContext, 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tick the lines to add and fix quantity or price where the OCR guessed wrong.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ),
                Flexible(
                  child: SizedBox(
                    height: 320,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: lines.length,
                      itemBuilder: (context, index) {
                        final line = lines[index] as Map<String, dynamic>;
                        return Row(
                          children: [
                            Checkbox(
                              value: selected.contains(index),
                              onChanged: (checked) => setDialogState(() {
                                if (checked == true) {
                                  selected.add(index);
                                } else {
                                  selected.remove(index);
                                }
                              }),
                            ),
                            Expanded(
                              flex: 5,
                              child: Text(
                                line['medicineName']?.toString() ?? 'Line',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller: quantityControllers[index],
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Qty',
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: priceControllers[index],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Price',
                                  prefixText: '₹',
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(true),
              child: Text('Add ${selected.length} lines'),
            ),
          ],
        ),
      ),
    );

    final chosen = [
      for (var i = 0; i < lines.length; i++)
        if (selected.contains(i)) i,
    ];
    final invalid = chosen
        .where(
          (i) =>
              int.tryParse(quantityControllers[i].text) == null ||
              double.tryParse(priceControllers[i].text) == null ||
              double.parse(priceControllers[i].text) <= 0,
        )
        .toList();
    for (final controller in [...quantityControllers, ...priceControllers]) {
      controller.dispose();
    }
    if (save != true || chosen.isEmpty) return;
    if (!mounted) return;
    if (invalid.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Set a quantity and a price above 0 for all ${invalid.length} selected lines first.',
          ),
        ),
      );
      return;
    }

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final payload = [
      for (final i in chosen)
        {
          'medicineName':
              (lines[i] as Map<String, dynamic>)['medicineName']?.toString() ??
              'Bill item ${i + 1}',
          'barcode': 'OCR$stamp$i',
          'batchNumber': 'OCR-${stamp.toString().substring(6)}',
          'quantity': int.parse(quantityControllers[i].text.trim()),
          'sellingPrice': double.parse(priceControllers[i].text.trim()),
          'expiryDate': DateTime.now()
              .add(const Duration(days: 365))
              .toIso8601String(),
        },
    ];
    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/api/inventory/items/bulk').replace(
              queryParameters: _isAdmin ? {'storeId': _selectedStoreId!} : null,
            ),
            headers: ApiSession.headers,
            body: jsonEncode({
              'items': [
                for (final item in payload)
                  {...item, if (_isAdmin) 'storeId': _selectedStoreId},
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${data['created'] ?? payload.length} bill lines added to stock.',
            ),
          ),
        );
        await _loadItems();
      } else {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['message']?.toString() ?? 'Could not save bill lines',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save bill lines. Try again.'),
          ),
        );
      }
      debugPrint('OCR bulk add failed: $error');
    }
  }

  Future<void> _adjustStock(Map<String, dynamic> item, String type) async {
    if (_selectedStoreId == null) return;
    final quantityController = TextEditingController();
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final isInward = type == 'IN';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isInward ? 'Add stock (inward)' : 'Reduce stock (outward)'),
        content: SizedBox(
          width: dialogWidth(dialogContext, 380),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${item['medicineName']} · ${item['quantity']} in stock now',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF334155),
                  ),
                ),
                _formField(
                  quantityController,
                  isInward ? 'Quantity received' : 'Quantity removed',
                  keyboardType: TextInputType.number,
                  validator: (value) =>
                      int.tryParse(value ?? '') == null || int.parse(value!) < 1
                      ? 'Enter 1 or more'
                      : null,
                ),
                TextFormField(
                  controller: reasonController,
                  decoration: InputDecoration(
                    labelText: isInward
                        ? 'Supplier bill / reason (optional)'
                        : 'Sold, damaged, expired... (optional)',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: isInward
                  ? const Color(0xFF1F7A45)
                  : const Color(0xFFDC2626),
            ),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogContext).pop(true);
              }
            },
            child: Text(isInward ? 'Add inward' : 'Remove outward'),
          ),
        ],
      ),
    );
    // Capture before dispose; the dialog is gone either way.
    final quantityText = quantityController.text.trim();
    final reasonText = reasonController.text.trim().isEmpty
        ? null
        : reasonController.text.trim();
    quantityController.dispose();
    reasonController.dispose();
    if (confirmed != true) return;

    try {
      final response = await http
          .post(
            Uri.parse(
              '$_apiBaseUrl/api/inventory/items/${item['_id']}/adjust',
            ).replace(
              queryParameters: _isAdmin ? {'storeId': _selectedStoreId!} : null,
            ),
            headers: ApiSession.headers,
            body: jsonEncode({
              'type': type,
              'quantity': int.parse(quantityText),
              'reason': reasonText,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final updated = data['item'] as Map<String, dynamic>?;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Stock ${isInward ? 'added' : 'removed'}. Now ${updated?['quantity'] ?? '?'} in stock.',
            ),
          ),
        );
        await _loadItems();
      } else {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message']?.toString() ?? 'Adjustment failed'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Adjustment failed. Try again.')),
        );
      }
      debugPrint('Stock adjust failed: $error');
    }
  }

  /// Outward/inward reporting: every stock move on this item with its
  /// reason, quantity and running balance.
  Future<void> _showMovements(Map<String, dynamic> item) async {
    if (_selectedStoreId == null) return;
    try {
      final response = await http
          .get(
            Uri.parse(
              '$_apiBaseUrl/api/inventory/items/${item['_id']}/movements',
            ).replace(
              queryParameters: _isAdmin ? {'storeId': _selectedStoreId!} : null,
            ),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (response.statusCode != 200) {
        throw Exception('Could not load movements');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final movements = data['items'] as List<dynamic>? ?? [];
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Stock report · ${item['medicineName']}'),
          content: SizedBox(
            width: dialogWidth(dialogContext, 460),
            child: movements.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No movements recorded yet. Sales at the counter and inward/outward additions will appear here.',
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: movements.length,
                    itemBuilder: (context, index) {
                      final m = movements[index] as Map<String, dynamic>;
                      final isIn = m['movementType'] == 'IN';
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          isIn
                              ? Icons.south_west_rounded
                              : Icons.north_east_rounded,
                          color: isIn
                              ? const Color(0xFF1F7A45)
                              : const Color(0xFFDC2626),
                        ),
                        title: Text(
                          isIn
                              ? 'Inward ${m['quantity']}'
                              : 'Outward ${m['quantity']}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'Balance ${m['balanceAfter']}'
                          '${m['reason'] != null ? ' · ${m['reason']}' : ''}'
                          '${m['createdAt'] != null ? ' · ${m['createdAt'].toString().split('T').first}' : ''}',
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load stock movements')),
        );
      }
      debugPrint('Movements load failed: $error');
    }
  }

  Future<void> _archiveItem(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive inventory item?'),
        content: const Text(
          'The item will be removed from the active inventory list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final response = await http.delete(
        _itemsUri(itemId: item['_id'].toString()),
        headers: ApiSession.headers,
      );
      if (response.statusCode != 200) throw Exception('Could not archive item');
      await _loadItems();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inventory item archived')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Archive failed: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedShop = _shops.where(
      (shop) => shop['_id'] == _selectedStoreId,
    );
    final selectedShopName = selectedShop.isEmpty
        ? 'Select a shop to manage inventory'
        : selectedShop.first['shopName']?.toString() ?? 'Selected shop';

    return AppShell(
      selectedTab: 2,
      showBack: true,
      body: Column(
        children: [
          if (_isAdmin)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: DropdownButtonFormField<String>(
                initialValue: _selectedStoreId,
                decoration: const InputDecoration(
                  labelText: 'Shop',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final shop in _shops)
                    DropdownMenuItem<String>(
                      value: shop['_id']?.toString(),
                      child: Text(
                        shop['shopName']?.toString() ?? 'Medical shop',
                      ),
                    ),
                ],
                onChanged: (value) {
                  setState(() => _selectedStoreId = value);
                  if (value != null) _loadItems();
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                selectedShopName,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 220,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _selectedStoreId == null
                    ? const ColoredBox(
                        color: Color(0xFFE2E8F0),
                        child: Center(
                          child: Text('Select a shop to start scanning'),
                        ),
                      )
                    : _scannerSupported
                    ? MobileScanner(
                        controller: _scannerController,
                        onDetect: _handleBarcode,
                        errorBuilder: (context, error) => ColoredBox(
                          color: const Color(0xFFE2E8F0),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Camera unavailable. Enter the barcode manually below.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                        overlayBuilder: (context, constraints) => Center(
                          child: Container(
                            width: constraints.maxWidth * 0.72,
                            height: 90,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      )
                    : ColoredBox(
                        color: const Color(0xFFE2E8F0),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Camera scanning is not available on this device. Enter the barcode manually below.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _barcodeController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Barcode',
                      prefixIcon: Icon(Icons.qr_code_2),
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (value) {
                      if (value.trim().isNotEmpty) {
                        _showItemForm(barcode: value.trim());
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Add item using barcode',
                  onPressed:
                      _selectedStoreId == null ||
                          _barcodeController.text.trim().isEmpty
                      ? null
                      : () => _showItemForm(
                          barcode: _barcodeController.text.trim(),
                        ),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Inventory entries',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Tooltip(
                  message: _selectedStoreId == null
                      ? 'Select a shop first'
                      : 'Add stock from a ready-made template',
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF0B4F3A),
                    ),
                    onPressed: _selectedStoreId == null
                        ? null
                        : _openTemplatePicker,
                    icon: const Icon(Icons.playlist_add_rounded, size: 18),
                    label: const Text('Add from template'),
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: _selectedStoreId == null ? 'Select a shop first' : 'Photograph the supplier bill and import the stock lines',
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF1F7A45),
                    ),
                    onPressed: _selectedStoreId == null
                        ? null
                        : _scanSupplierBill,
                    icon: const Icon(Icons.document_scanner_outlined, size: 18),
                    label: const Text('Scan bill'),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh inventory',
                  onPressed: _selectedStoreId == null ? null : _loadItems,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _selectedStoreId == null
                ? const Center(child: Text('Select a shop to view inventory'))
                : _items.isEmpty
                ? const Center(child: Text('No inventory items yet'))
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index] as Map<String, dynamic>;
                      return ListTile(
                        leading: Icon(
                          Icons.medication_outlined,
                          color:
                              (item['quantity'] as num?) != null &&
                                  item['quantity'] <=
                                      (item['reorderLevel'] ?? 10)
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF0B4F3A),
                        ),
                        title: Text(
                          item['medicineName']?.toString() ?? 'Medicine',
                        ),
                        subtitle: Text(
                          'Qty ${item['quantity']} · Batch ${item['batchNumber']} · ₹${item['sellingPrice']} · Exp ${item['expiryDate']?.toString().split('T').first}',
                        ),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Inventory item actions',
                          onSelected: (action) {
                            if (action == 'edit') _showItemForm(item: item);
                            if (action == 'in') _adjustStock(item, 'IN');
                            if (action == 'out') _adjustStock(item, 'OUT');
                            if (action == 'movements') {
                              _showMovements(item);
                            }
                            if (action == 'archive') _archiveItem(item);
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'in',
                              child: Text('Add stock (inward)'),
                            ),
                            PopupMenuItem(
                              value: 'out',
                              child: Text('Remove stock (outward)'),
                            ),
                            PopupMenuItem(
                              value: 'movements',
                              child: Text('View stock movements'),
                            ),
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                              value: 'archive',
                              child: Text('Archive'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
