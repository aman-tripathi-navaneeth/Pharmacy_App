import 'dart:async';
import 'dart:convert';

import 'package:barcode/barcode.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../api_session.dart';
import '../utils/responsive.dart';
import '../l10n/strings.dart';
import '../utils/payments.dart';
import '../utils/toast.dart';
import '../widgets/app_shell.dart';

const Color _darkGreen = Color(0xFF0B4F3A);
const Color _darkGreenSoft = Color(0xFFE6F0EB);

class NewBillScreen extends StatefulWidget {
  const NewBillScreen({super.key});

  @override
  State<NewBillScreen> createState() => _NewBillScreenState();
}

class _NewBillScreenState extends State<NewBillScreen> {
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  final _customerSearch = TextEditingController();
  final _customerName = TextEditingController();
  final _customerPhone = TextEditingController();
  final _medicineSearch = TextEditingController();
  final _discount = TextEditingController(text: '0');
  final _tax = TextEditingController(text: '0');
  final _paid = TextEditingController();
  final _notes = TextEditingController();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechReady = false;
  bool _listening = false;
  String _listeningFor = '';

  Timer? _debounce;
  bool _isSaving = false;
  bool _loadingHistory = false;
  String _paymentStatus = 'PAID';
  String _paymentMethod = 'CASH';
  Map<String, dynamic>? _customer;
  Map<String, dynamic>? _shop;
  Map<String, dynamic>? _history;
  List<dynamic> _customerResults = [];
  List<dynamic> _medicineResults = [];
  final List<Map<String, dynamic>> _lines = [];

  @override
  void initState() {
    super.initState();
    _loadShop();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _speech.stop();
    for (final controller in [
      _customerSearch,
      _customerName,
      _customerPhone,
      _medicineSearch,
      _discount,
      _tax,
      _paid,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadShop() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_apiBaseUrl/api/shops/me'),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (mounted) {
          final shop = data['shop'] as Map<String, dynamic>?;
          final settings = shop?['paymentSettings'] as Map<String, dynamic>?;
          setState(() {
            _shop = shop;
            // Respect the owner's enabled payment options.
            if (settings?['cashEnabled'] == false) _paymentMethod = 'ONLINE';
            if (settings?['onlineEnabled'] == false) _paymentMethod = 'CASH';
          });
        }
      }
    } catch (error) {
      debugPrint('Could not load shop for invoice: $error');
    }
  }

  Map<String, dynamic> get _paymentSettings =>
      _shop?['paymentSettings'] as Map<String, dynamic>? ?? {};
  String get _upiId => _paymentSettings['upiId']?.toString() ?? '';
  String get _payeeName =>
      _paymentSettings['payeeName']?.toString() ??
      _shop?['shopName']?.toString() ??
      '';
  bool get _cashEnabled => _paymentSettings['cashEnabled'] as bool? ?? true;
  bool get _onlineEnabled => _paymentSettings['onlineEnabled'] as bool? ?? true;

  /// Amount the customer should pay online right now. Full udhaar has no
  /// online amount until the customer settles it.
  double get _onlineAmount {
    if (_paymentStatus == 'CREDIT') return 0;
    if (_paymentStatus == 'PARTIAL') return _paidValue;
    return _total;
  }

  String? get _onlineUpiUri => buildUpiUri(
    upiId: _upiId,
    payeeName: _payeeName,
    amount: _onlineAmount,
    note: 'Pharmacy bill',
  );

  /// Owner-uploaded shop QR used when no UPI ID is configured.
  Uint8List? get _uploadedQr =>
      decodeDataImage(_paymentSettings['qrImage']?.toString());

  double get _subtotal => _lines.fold(
    0,
    (sum, line) =>
        sum +
        ((line['quantity'] as num).toDouble() *
            (line['unitPrice'] as num).toDouble()),
  );

  double get _discountValue => double.tryParse(_discount.text.trim()) ?? 0;
  double get _taxPercent => double.tryParse(_tax.text.trim()) ?? 0;
  double get _taxValue => _subtotal * _taxPercent / 100;
  double get _total =>
      (_subtotal - _discountValue + _taxValue).clamp(0, double.infinity);
  double get _paidValue {
    if (_paymentStatus == 'PAID') return _total;
    return (double.tryParse(_paid.text.trim()) ?? 0).clamp(0, _total);
  }

  double get _due => (_total - _paidValue).clamp(0, double.infinity);

  void _debounced(Future<void> Function() action) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), action);
  }

  Future<void> _searchCustomers(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _customerResults = []);
      return;
    }
    try {
      final response = await http
          .get(
            Uri.parse('$_apiBaseUrl/api/customers')
                .replace(queryParameters: {'search': query.trim()}),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (mounted) {
          setState(
            () => _customerResults = data['items'] as List<dynamic>? ?? [],
          );
        }
      }
    } catch (error) {
      debugPrint('Customer search failed: $error');
    }
  }

  Future<void> _selectCustomer(Map<String, dynamic> customer) async {
    setState(() {
      _customer = customer;
      _customerName.text = customer['name']?.toString() ?? '';
      _customerPhone.text = customer['phone']?.toString() ?? '';
      _customerResults = [];
      _customerSearch.text = customer['name']?.toString() ?? '';
    });
    await _loadHistory(customer['_id'].toString());
  }

  /// Loads the customer's bills and payments. Also used after saving a bill so
  /// the just-created walk-in customer's history appears immediately.
  Future<void> _loadHistory(String customerId) async {
    setState(() => _loadingHistory = true);
    try {
      final response = await http
          .get(
            Uri.parse('$_apiBaseUrl/api/customers/$customerId'),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _history = data;
          final saved = data['customer'];
          if (saved is Map<String, dynamic>) _customer = saved;
        });
      }
    } catch (error) {
      debugPrint('Customer history failed: $error');
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  void _clearCustomer() {
    setState(() {
      _customer = null;
      _history = null;
      _customerSearch.clear();
      _customerName.clear();
      _customerPhone.clear();
      _customerResults = [];
    });
  }

  Future<void> _searchMedicines(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _medicineResults = []);
      return;
    }
    try {
      final response = await http
          .get(
            Uri.parse('$_apiBaseUrl/api/inventory/items')
                .replace(queryParameters: {'search': query.trim()}),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (mounted) {
          setState(
            () => _medicineResults = data['items'] as List<dynamic>? ?? [],
          );
        }
      }
    } catch (error) {
      debugPrint('Medicine search failed: $error');
    }
  }

  void _addInventoryLine(Map<String, dynamic> item) {
    final available = (item['quantity'] as num?)?.toInt() ?? 0;
    if (available <= 0) {
      AppToast.show(context, 'This medicine is out of stock', success: false);
      return;
    }
    setState(() {
      _lines.add({
        'inventoryItemId': item['_id'],
        'medicineName': item['medicineName']?.toString() ?? 'Medicine',
        'batchNumber': item['batchNumber']?.toString(),
        'quantity': 1,
        'unitPrice': (item['sellingPrice'] as num?)?.toDouble() ?? 0,
        'available': available,
      });
      _medicineSearch.clear();
      _medicineResults = [];
    });
  }

  Future<void> _addManualLine() async {
    final name = TextEditingController();
    final price = TextEditingController();
    final quantity = TextEditingController(text: '1');
    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add medicine manually'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Medicine name'),
            ),
            TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Price per unit'),
            ),
            TextField(
              controller: quantity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (added == true && name.text.trim().isNotEmpty) {
      setState(() {
        _lines.add({
          'inventoryItemId': null,
          'medicineName': name.text.trim(),
          'batchNumber': null,
          'quantity': int.tryParse(quantity.text.trim()) ?? 1,
          'unitPrice': double.tryParse(price.text.trim()) ?? 0,
          'available': null,
        });
      });
    }
    name.dispose();
    price.dispose();
    quantity.dispose();
  }

  Future<void> _startVoice({required String target}) async {
    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        onError: (error) => debugPrint('Speech error: ${error.errorMsg}'),
      );
    }
    if (!_speechReady) {
      if (mounted) {
        AppToast.show(context, tr('voiceUnavailable'), success: false);
      }
      return;
    }
    if (_listening) {
      await _speech.stop();
      setState(() {
        _listening = false;
        _listeningFor = '';
      });
      return;
    }
    setState(() {
      _listening = true;
      _listeningFor = target;
    });
    await _speech.listen(
      onResult: (result) {
        final words = result.recognizedWords.trim();
        if (words.isEmpty) return;
        _applyVoiceText(words, target);
        setState(() {});
      },
      listenOptions: stt.SpeechListenOptions(
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        localeId: 'en_IN',
      ),
    );
    if (mounted) {
      setState(() {
        _listening = false;
        _listeningFor = '';
      });
    }
  }

  /// Voice input supports plain names and slash commands. Speech engines
  /// usually read "/" as "slash", so both forms are accepted.
  ///   /customer Ravi      /medicine Dolo 650
  ///   /qty 2              /discount 20      /tax 5      /help
  void _applyVoiceText(String words, String target) {
    final lower = words.toLowerCase();
    final command = RegExp(
      r'^(?:/|slash\s+)(customer|medicine|qty|quantity|discount|tax|help)\b\s*(.*)$',
    ).firstMatch(lower);
    if (command != null) {
      final name = command.group(1)!;
      final argument = command.group(2)?.trim() ?? '';
      switch (name) {
        case 'customer':
          if (argument.isNotEmpty) {
            _customerSearch.text = argument;
            _debounced(() => _searchCustomers(argument));
          }
          return;
        case 'medicine':
          if (argument.isNotEmpty) {
            _medicineSearch.text = argument;
            _debounced(() => _searchMedicines(argument));
          }
          return;
        case 'qty':
        case 'quantity':
          final quantity = int.tryParse(argument);
          if (quantity != null && quantity > 0 && _lines.isNotEmpty) {
            _lines.last['quantity'] = quantity;
            AppToast.show(context, 'Quantity set to $quantity');
          }
          return;
        case 'discount':
          final value = double.tryParse(argument);
          if (value != null && value >= 0) {
            _discount.text = value.toStringAsFixed(0);
          }
          return;
        case 'tax':
          final value = double.tryParse(argument);
          if (value != null && value >= 0 && value <= 100) {
            _tax.text = value.toStringAsFixed(0);
          }
          return;
        case 'help':
          _showVoiceHelp();
          return;
      }
    }
    if (target == 'customer') {
      _customerSearch.text = words;
      _debounced(() => _searchCustomers(words));
    } else {
      _medicineSearch.text = words;
      _debounced(() => _searchMedicines(words));
    }
  }

  void _showVoiceHelp() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.mic_none_rounded, color: _darkGreen),
            const SizedBox(width: 8),
            Text(tr('voiceHelpTitle')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('voiceHelpIntro')),
              const SizedBox(height: 12),
              for (final line in [
                tr('voiceHelpStep1'),
                tr('voiceHelpStep2'),
                tr('voiceHelpStep3'),
                tr('voiceHelpStep4'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: _darkGreen,
                      ),
                      Expanded(child: Text(line)),
                    ],
                  ),
                ),
              const Divider(height: 22),
              Text(
                tr('voiceCommands'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              for (final entry in const [
                ('/customer Ravi', 'Find a saved customer'),
                ('/medicine Dolo 650', 'Search stock medicines'),
                ('/qty 2', 'Set quantity on the last line'),
                ('/discount 20', 'Set the discount amount'),
                ('/tax 5', 'Set the tax percentage'),
                ('/help', 'Show these instructions'),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _darkGreenSoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          entry.$1,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: _darkGreen,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.$2,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                tr('voiceHelpSpeakSlash'),
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(tr('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _bulkAddStock() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bulk add stock'),
        content: SizedBox(
          width: dialogWidth(dialogContext, 540),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'One medicine per line:\n'
                'Name | barcode | batch | expiry (YYYY-MM-DD) | qty | price | reorder',
                style: TextStyle(fontSize: 12, color: Color(0xFF5A6E69)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                minLines: 6,
                maxLines: 10,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Dolo 650 | 8901234567890 | DL2241 | 2028-08-31 | 20 | 30 | 5',
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
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
    if (result != true) {
      controller.dispose();
      return;
    }
    final items = <Map<String, dynamic>>[];
    for (final raw in controller.text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final parts = line.split(RegExp(r'[|\t]')).map((p) => p.trim()).toList();
      if (parts.length < 6) continue;
      final quantity = int.tryParse(parts[4]);
      final price = double.tryParse(parts[5]);
      if (quantity == null || price == null) continue;
      items.add({
        'medicineName': parts[0],
        'barcode': parts[1],
        'batchNumber': parts[2],
        'expiryDate': parts[3],
        'quantity': quantity,
        'sellingPrice': price,
        'reorderLevel': parts.length > 6 ? int.tryParse(parts[6]) ?? 10 : 10,
      });
    }
    controller.dispose();
    if (items.isEmpty) {
      if (mounted) {
        AppToast.show(context, 'No valid lines found', success: false);
      }
      return;
    }
    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/api/inventory/items/bulk'),
            headers: ApiSession.headers,
            body: jsonEncode({'items': items}),
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 201) {
        final failed = (data['failed'] as List<dynamic>?)?.length ?? 0;
        if (mounted) {
          AppToast.show(
            context,
            'Added ${data['created']} items'
            '${failed > 0 ? ' · $failed skipped' : ''}',
            success: failed == 0,
          );
        }
      } else {
        throw Exception(data['message'] ?? 'Bulk upload failed');
      }
    } catch (error) {
      if (mounted) {
        AppToast.show(context, 'Bulk upload failed: $error', success: false);
      }
    }
  }

  Future<void> _saveBill() async {
    if (_lines.isEmpty) {
      AppToast.show(context, 'Add at least one medicine', success: false);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/api/bills'),
            headers: ApiSession.headers,
            body: jsonEncode({
              'customerId': _customer?['_id'],
              'customerName': _customerName.text.trim().isEmpty
                  ? null
                  : _customerName.text.trim(),
              'customerPhone': _customerPhone.text.trim().isEmpty
                  ? null
                  : _customerPhone.text.trim(),
              'items': [
                for (final line in _lines)
                  {
                    'inventoryItemId': line['inventoryItemId'],
                    'medicineName': line['medicineName'],
                    'batchNumber': line['batchNumber'],
                    'quantity': line['quantity'],
                    'unitPrice': line['unitPrice'],
                  },
              ],
              'discount': _discountValue,
              'taxPercent': _taxPercent,
              'paymentStatus': _paymentStatus,
              'paymentMethod': _paymentMethod,
              'paidAmount': _paymentStatus == 'PAID' ? null : _paidValue,
              'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 201) {
        throw Exception(data['message'] ?? 'Could not save bill');
      }
      final bill = data['bill'] as Map<String, dynamic>;
      if (!mounted) return;
      await _showSavedDialog(bill);
      final customerId = bill['customerId']?.toString();
      if (mounted) {
        setState(() {
          _lines.clear();
          _notes.clear();
          _discount.text = '0';
          _tax.text = '0';
          _paid.clear();
          _paymentStatus = 'PAID';
          _paymentMethod = _cashEnabled ? 'CASH' : 'ONLINE';
          if (customerId == null) _history = null;
        });
      }
      if (customerId != null) await _loadHistory(customerId);
    } catch (error) {
      if (mounted) {
        AppToast.show(
          context,
          error.toString().replaceFirst('Exception: ', ''),
          success: false,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showSavedDialog(Map<String, dynamic> bill) async {
    final messenger = ScaffoldMessenger.of(context);
    final double due = (bill['dueAmount'] as num?)?.toDouble() ?? 0;
    final double total = (bill['total'] as num?)?.toDouble() ?? 0;
    final String method = bill['paymentMethod']?.toString() ?? 'CASH';
    final double collectNow = due > 0 ? due : total;
    final String? billUpi = method == 'ONLINE'
        ? buildUpiUri(
            upiId: _upiId,
            payeeName: _payeeName,
            amount: collectNow,
            note: bill['invoiceNumber']?.toString(),
            transactionRef: bill['invoiceNumber']?.toString(),
          )
        : null;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.check_circle_rounded,
          color: _darkGreen,
          size: 42,
        ),
        title: Text(bill['invoiceNumber']?.toString() ?? 'Bill saved'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Total ₹${total.toStringAsFixed(2)}'
                ' · Due ₹${due.toStringAsFixed(2)}'
                '\n${bill['paymentStatus']} · $method',
                textAlign: TextAlign.center,
              ),
              if (billUpi != null) ...[
                const SizedBox(height: 12),
                Text(
                  tr('scanToPay'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '₹${collectNow.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: _darkGreen,
                  ),
                ),
                QrImageView(
                  data: billUpi,
                  size: 160,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: _darkGreen,
                  ),
                ),
                Text(
                  _upiId,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
          FilledButton.icon(
            onPressed: () => _downloadInvoice(bill, messenger),
            icon: const Icon(Icons.picture_as_pdf_rounded),
            label: const Text('Invoice PDF'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadInvoice(
    Map<String, dynamic> bill,
    ScaffoldMessengerState messenger,
  ) async {
    final document = pw.Document();
    final items = bill['items'] as List<dynamic>? ?? [];
    final shop = _shop ?? {};
    final address = shop['address'] as Map<String, dynamic>? ?? {};
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      shop['shopName']?.toString() ?? 'Pharmacy',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      [
                        address['line1'],
                        address['city'],
                        address['state'],
                        address['postalCode'],
                      ].where((v) => v != null).join(', '),
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.Text(
                      shop['phoneE164']?.toString() ?? '',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('INVOICE', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text(
                      bill['invoiceNumber']?.toString() ?? '',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      bill['createdAt']?.toString().split('T').first ?? '',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.Divider(color: PdfColors.green900),
            pw.SizedBox(height: 6),
            pw.Text(
              'Bill to: ${bill['customerName'] ?? 'Walk-in customer'}',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.Text(
              bill['customerPhone']?.toString() ?? '',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: const ['Medicine', 'Batch', 'Qty', 'Rate', 'Amount'],
              data: [
                for (final raw in items)
                  [
                    raw['medicineName']?.toString() ?? '',
                    raw['batchNumber']?.toString() ?? '-',
                    raw['quantity'].toString(),
                    '₹${(raw['unitPrice'] as num).toStringAsFixed(2)}',
                    '₹${(raw['lineTotal'] as num).toStringAsFixed(2)}',
                  ],
              ],
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.green900,
              ),
              cellStyle: const pw.TextStyle(fontSize: 9),
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.green50,
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.SizedBox(
                width: 220,
                child: pw.Column(
                  children: [
                    _pdfTotalRow('Subtotal', bill['subtotal']),
                    _pdfTotalRow(
                      'Discount',
                      -((bill['discount'] as num).toDouble()),
                    ),
                    _pdfTotalRow('Tax', bill['tax']),
                    pw.Divider(),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Total',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          '₹${(bill['total'] as num).toStringAsFixed(2)}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                    _pdfTotalRow('Paid', bill['paidAmount']),
                    _pdfTotalRow('Due', bill['dueAmount']),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Payment',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                        pw.Text(
                          bill['paymentMethod']?.toString() ?? 'CASH',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if ((bill['paymentMethod']?.toString() ?? 'CASH') == 'ONLINE' &&
                _upiId.isNotEmpty) ...[
              pw.SizedBox(height: 12),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.BarcodeWidget(
                        barcode: Barcode.qrCode(),
                        data:
                            buildUpiUri(
                              upiId: _upiId,
                              payeeName: _payeeName,
                              amount: (bill['dueAmount'] as num).toDouble() > 0
                                  ? (bill['dueAmount'] as num).toDouble()
                                  : (bill['total'] as num).toDouble(),
                              note: bill['invoiceNumber']?.toString(),
                              transactionRef: bill['invoiceNumber']?.toString(),
                            ) ??
                            _upiId,
                        width: 84,
                        height: 84,
                      ),
                      pw.Text(
                        'Scan to pay · $_upiId',
                        style: const pw.TextStyle(
                          fontSize: 8,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
            pw.Spacer(),
            pw.Divider(),
            pw.Text(
              'Thank you. Generated by MediManage.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
    );
    final bytes = await document.save();
    try {
      await FileSaver.instance.saveFile(
        name: 'invoice-${bill['invoiceNumber']}',
        bytes: bytes,
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Invoice PDF saved')),
      );
    } catch (error) {
      debugPrint('Invoice save failed: $error');
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save invoice PDF')),
      );
    }
  }

  pw.Widget _pdfTotalRow(String label, Object? value) {
    final amount = (value as num?)?.toDouble() ?? 0;
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
        pw.Text(
          '₹${amount.toStringAsFixed(2)}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      selectedTab: -1,
      showBack: true,
      showNewBillCta: false,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _headerCard(),
                const SizedBox(height: 14),
                _customerCard(),
                if (_history != null) ...[
                  const SizedBox(height: 12),
                  _historyCard(),
                ],
                const SizedBox(height: 14),
                _medicinesCard(),
                const SizedBox(height: 14),
                _paymentCard(),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _saveBill,
                    icon: _isSaving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.receipt_long_rounded),
                    label: Text(
                      _isSaving
                          ? 'Saving…'
                          : 'Save bill · ₹${_total.toStringAsFixed(2)}',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _darkGreen,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _darkGreen,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 30),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'New bill',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Customer, medicines and payment in one screen',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _bulkAddStock,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: const Text('Bulk stock'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _customerCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE1E9E6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Customer',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const Spacer(),
                if (_customer != null)
                  TextButton.icon(
                    onPressed: _clearCustomer,
                    icon: const Icon(Icons.person_remove_outlined, size: 16),
                    label: const Text('Change'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _customerSearch,
              onChanged: (value) => _debounced(() => _searchCustomers(value)),
              decoration: InputDecoration(
                labelText: 'Search saved customer',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  tooltip: 'Speak customer name',
                  onPressed: () => _startVoice(target: 'customer'),
                  icon: Icon(
                    _listening && _listeningFor == 'customer'
                        ? Icons.mic_rounded
                        : Icons.mic_none_rounded,
                    color: _darkGreen,
                  ),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            if (_customerResults.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE1E9E6)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    for (final raw in _customerResults.take(5))
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.person_outline, size: 20),
                        title: Text(raw['name']?.toString() ?? ''),
                        subtitle: Text(raw['phone']?.toString() ?? 'No phone'),
                        trailing: Text(
                          '₹${(raw['balance'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onTap: () =>
                            _selectCustomer(raw as Map<String, dynamic>),
                      ),
                  ],
                ),
              ),
            if (_customer != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: _darkGreen, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${_customer!['name']} · ₹${(_customer!['balance'] as num?)?.toStringAsFixed(2) ?? '0.00'} due',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF5A6E69),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customerName,
                    decoration: const InputDecoration(
                      labelText: 'Customer name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _customerPhone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone (10 digits)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyCard() {
    final bills = _history!['bills'] as List<dynamic>? ?? [];
    final payments = _history!['payments'] as List<dynamic>? ?? [];
    final customer = _history!['customer'] as Map<String, dynamic>? ?? {};
    return Card(
      elevation: 0,
      color: _darkGreenSoft,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history_rounded, color: _darkGreen, size: 18),
                const SizedBox(width: 6),
                const Text(
                  'Customer history',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _darkGreen,
                  ),
                ),
                const Spacer(),
                if (_loadingHistory)
                  const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Udhaar balance ₹${(customer['balance'] as num?)?.toStringAsFixed(2) ?? '0.00'}'
              ' · ${bills.length} bill(s) · ${payments.length} payment(s)',
              style: const TextStyle(fontSize: 12, color: Color(0xFF334A43)),
            ),
            const SizedBox(height: 6),
            for (final raw in bills.take(3))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${raw['invoiceNumber']} · ${raw['createdAt']?.toString().split('T').first ?? ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Text(
                      '₹${(raw['total'] as num?)?.toStringAsFixed(2) ?? ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _medicinesCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE1E9E6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Medicines',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const Spacer(),
                IconButton(
                  tooltip: tr('voiceHelpTitle'),
                  onPressed: _showVoiceHelp,
                  icon: const Icon(Icons.record_voice_over_outlined, size: 20),
                ),
                TextButton.icon(
                  onPressed: _addManualLine,
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('Manual'),
                ),
              ],
            ),
            TextField(
              controller: _medicineSearch,
              onChanged: (value) => _debounced(() => _searchMedicines(value)),
              decoration: InputDecoration(
                labelText: 'Search stock or speak medicine name',
                prefixIcon: const Icon(Icons.medication_outlined),
                suffixIcon: IconButton(
                  tooltip: 'Speak medicine name',
                  onPressed: () => _startVoice(target: 'medicine'),
                  icon: Icon(
                    _listening && _listeningFor == 'medicine'
                        ? Icons.mic_rounded
                        : Icons.mic_none_rounded,
                    color: _darkGreen,
                  ),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            if (_medicineResults.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE1E9E6)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    for (final raw in _medicineResults.take(6))
                      ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.inventory_2_outlined,
                          size: 20,
                        ),
                        title: Text(raw['medicineName']?.toString() ?? ''),
                        subtitle: Text(
                          'Batch ${raw['batchNumber']} · ₹${raw['sellingPrice']} · ${raw['quantity']} left',
                        ),
                        trailing: TextButton(
                          onPressed: () =>
                              _addInventoryLine(raw as Map<String, dynamic>),
                          child: const Text('Add'),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            if (_lines.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text(
                    'No medicines added yet',
                    style: TextStyle(color: Color(0xFF5A6E69)),
                  ),
                ),
              )
            else
              for (var index = 0; index < _lines.length; index++)
                _lineTile(index),
          ],
        ),
      ),
    );
  }

  Widget _lineTile(int index) {
    final line = _lines[index];
    final quantity = line['quantity'] as int;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F9F7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line['medicineName']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '₹${(line['unitPrice'] as num).toStringAsFixed(2)} each'
                  '${line['available'] != null ? ' · ${line['available']} in stock' : ''}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF5A6E69),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: quantity <= 1
                ? null
                : () => setState(() => line['quantity'] = quantity - 1),
            icon: const Icon(Icons.remove_circle_outline, size: 20),
          ),
          Text(
            '$quantity',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => line['quantity'] = quantity + 1),
            icon: const Icon(Icons.add_circle_outline, size: 20),
          ),
          SizedBox(
            width: 72,
            child: Text(
              '₹${((line['unitPrice'] as num) * quantity).toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _lines.removeAt(index)),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _paymentCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE1E9E6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Payment',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 10),
            Text(
              tr('paymentMode'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: [
                if (_cashEnabled)
                  ButtonSegment(
                    value: 'CASH',
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: Text(tr('cash')),
                  ),
                if (_onlineEnabled)
                  ButtonSegment(
                    value: 'ONLINE',
                    icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                    label: Text(tr('online')),
                  ),
              ],
              selected: {_paymentMethod},
              onSelectionChanged: (selection) =>
                  setState(() => _paymentMethod = selection.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: _darkGreen,
                selectedForegroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              tr('paymentStatus'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'PAID', label: Text('Paid')),
                ButtonSegment(value: 'PARTIAL', label: Text('Part')),
                ButtonSegment(value: 'CREDIT', label: Text('Udhaar')),
              ],
              selected: {_paymentStatus},
              onSelectionChanged: (selection) =>
                  setState(() => _paymentStatus = selection.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: _darkGreen,
                selectedForegroundColor: Colors.white,
              ),
            ),
            if (_paymentMethod == 'ONLINE') ...[
              const SizedBox(height: 12),
              _onlinePaymentPanel(),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _discount,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Discount ₹',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _tax,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Tax %',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            if (_paymentStatus == 'PARTIAL') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _paid,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Amount paid now ₹',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const Divider(height: 24),
            _totalRow('Subtotal', _subtotal),
            _totalRow('Discount', -_discountValue),
            _totalRow('Tax', _taxValue),
            _totalRow('Total', _total, strong: true),
            _totalRow('Paid', _paidValue),
            _totalRow('Due', _due),
          ],
        ),
      ),
    );
  }

  /// Customer-facing UPI QR: the bill amount is embedded in the UPI link, so
  /// scanning it opens any UPI app with the amount already filled in.
  Widget _onlinePaymentPanel() {
    if (_onlineAmount <= 0) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _darkGreenSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 20, color: _darkGreen),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr('onlineNothingDue'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    final uploadedQr = _uploadedQr;
    if (_upiId.isEmpty) {
      if (uploadedQr == null) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7E6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFF2D48A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: Color(0xFFB45309),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr('upiNotConfigured'),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: () async {
                  await Navigator.of(context).pushNamed('/settings');
                  // Pick up a UPI ID the owner just saved.
                  await _loadShop();
                },
                icon: const Icon(Icons.settings_outlined, size: 16),
                label: Text(tr('openPaymentSettings')),
              ),
            ],
          ),
        );
      }
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF3FAF7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFBBDCCD)),
        ),
        child: Column(
          children: [
            Text(
              tr('scanToPay'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            Text(
              '₹${_onlineAmount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 24,
                color: _darkGreen,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE1E9E6)),
              ),
              child: Image.memory(uploadedQr, width: 180, height: 180),
            ),
            const SizedBox(height: 6),
            Text(
              tr('customerScansWithUpi'),
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3FAF7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBDCCD)),
      ),
      child: Column(
        children: [
          Text(
            tr('scanToPay'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            '₹${_onlineAmount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 24,
              color: _darkGreen,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE1E9E6)),
            ),
            child: QrImageView(
              data: _onlineUpiUri!,
              size: 180,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: _darkGreen,
              ),
              errorStateBuilder: (context, error) => const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Could not build the UPI QR'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _payeeName.isEmpty ? _upiId : '$_payeeName · $_upiId',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: tr('copyUpiId'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _upiId));
                  if (mounted) AppToast.show(context, tr('upiCopied'));
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
              ),
              Text(
                tr('customerScansWithUpi'),
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, double value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
              fontSize: strong ? 16 : 13,
            ),
          ),
          Text(
            '₹${value.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              fontSize: strong ? 16 : 13,
              color: strong ? _darkGreen : null,
            ),
          ),
        ],
      ),
    );
  }
}
