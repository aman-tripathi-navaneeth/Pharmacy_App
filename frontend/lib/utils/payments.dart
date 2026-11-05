import 'dart:convert';
import 'dart:typed_data';

/// Helpers shared by Settings (owner payment setup) and New Bill (customer
/// payment). Everything is plain UPI, so no payment gateway is needed: the
/// owner saves a UPI ID and the app turns the bill amount into a scannable
/// UPI QR that any Indian banking app understands.

/// Builds a UPI deep link with the amount baked in, e.g.
/// `upi://pay?pa=shop@okhdfcbank&pn=Shop&am=120.00&cu=INR&tn=INV-...`.
/// Returns null when the owner has not saved a UPI ID yet.
String? buildUpiUri({
  required String? upiId,
  String? payeeName,
  required double? amount,
  String? note,
  String? transactionRef,
}) {
  final id = (upiId ?? '').trim();
  if (id.isEmpty) return null;
  final parameters = <String, String>{
    'pa': id,
    if ((payeeName ?? '').trim().isNotEmpty) 'pn': payeeName!.trim(),
    if (amount != null && amount > 0) 'am': amount.toStringAsFixed(2),
    'cu': 'INR',
    if ((note ?? '').trim().isNotEmpty) 'tn': note!.trim(),
    if ((transactionRef ?? '').trim().isNotEmpty) 'tr': transactionRef!.trim(),
  };
  return 'upi://pay?${parameters.entries.map((entry) => '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}').join('&')}';
}

/// Turns a `data:image/png;base64,...` value into bytes for `Image.memory`.
Uint8List? decodeDataImage(String? dataUrl) {
  if (dataUrl == null || dataUrl.isEmpty) return null;
  final comma = dataUrl.indexOf(',');
  if (comma < 0) return null;
  try {
    return base64Decode(dataUrl.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

/// Validates a basic UPI handle (name@bank) before saving.
bool isValidUpiId(String value) {
  return RegExp(r'^[A-Za-z0-9._-]{2,}@[A-Za-z]{2,}$').hasMatch(value.trim());
}
