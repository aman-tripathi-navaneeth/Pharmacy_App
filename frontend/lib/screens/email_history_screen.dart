import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api_session.dart';
import '../utils/toast.dart';

/// Full history of the emails the app sent: who they went to, which template
/// triggered them and whether the SMTP hand-off succeeded. Every attempt is
/// stored in the database, so nothing disappears from this list.
class EmailHistoryScreen extends StatefulWidget {
  const EmailHistoryScreen({super.key});

  @override
  State<EmailHistoryScreen> createState() => _EmailHistoryScreenState();
}

class _EmailHistoryScreenState extends State<EmailHistoryScreen> {
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  bool _isLoading = true;
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _smtp = {};
  String? _statusFilter;
  String? _error;
  bool _busy = false;

  bool get _isAdmin => ApiSession.user['role'] == 'SUPER_ADMIN';

  @override
  void initState() {
    super.initState();
    _load();
    _loadSmtpStatus();
  }

  Future<void> _loadSmtpStatus() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_apiBaseUrl/api/emails/status'),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 || !mounted) return;
      setState(
        () => _smtp = jsonDecode(response.body) as Map<String, dynamic>,
      );
    } catch (error) {
      debugPrint('Could not read SMTP status: $error');
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final query = _statusFilter == null
          ? ''
          : '?status=${Uri.encodeQueryComponent(_statusFilter!)}';
      final response = await http
          .get(
            Uri.parse('$_apiBaseUrl/api/emails$query'),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception('Could not load emails (${response.statusCode})');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>? ?? [];
      if (!mounted) return;
      setState(() {
        _items = items.whereType<Map<String, dynamic>>().toList();
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('Failed to load email history: $error');
      if (!mounted) return;
      setState(() {
        _error = 'Could not load email history. Try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _resend(Map<String, dynamic> item) async {
    final id = item['_id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() => _busy = true);
    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/api/emails/$id/resend'),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(data['message'] ?? 'Resend failed');
      }
      final email = data['email'] as Map<String, dynamic>?;
      final status = email?['status']?.toString() ?? 'SENT';
      if (!mounted) return;
      AppToast.show(
        context,
        status == 'SENT' ? 'Email sent again' : 'Resend status: $status',
        success: status == 'SENT',
      );
      await _load();
    } catch (error) {
      debugPrint('Resend failed: $error');
      if (!mounted) return;
      AppToast.show(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        success: false,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendTest() async {
    final controller = TextEditingController(
      text: ApiSession.user['emailNormalized']?.toString() ?? '',
    );
    final address = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Send a test email'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Send to'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (address == null || address.isEmpty) return;

    setState(() => _busy = true);
    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/api/emails/test'),
            headers: ApiSession.headers,
            body: jsonEncode({'to': address}),
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(data['message'] ?? 'Test email failed');
      }
      final email = data['email'] as Map<String, dynamic>?;
      final status = email?['status']?.toString() ?? 'SENT';
      if (!mounted) return;
      AppToast.show(
        context,
        status == 'SENT'
            ? 'Test email sent to $address'
            : 'Test email status: $status',
        success: status == 'SENT',
      );
      await _load();
    } catch (error) {
      debugPrint('Test email failed: $error');
      if (!mounted) return;
      AppToast.show(
        context,
        error.toString().replaceFirst('Exception: ', ''),
        success: false,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'SENT':
        return const Color(0xFF059669);
      case 'FAILED':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFFB45309);
    }
  }

  String _templateLabel(String? template) {
    switch (template) {
      case 'credentials':
        return 'Credentials';
      case 'first_login':
        return 'First login';
      case 'action_required':
        return 'Action required';
      case 'issue_raised':
        return 'Issue raised';
      case 'issue_status':
        return 'Issue status';
      case 'test':
        return 'Test';
      default:
        return template ?? 'Email';
    }
  }

  String _timeLabel(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '';
    final diff = DateTime.now().difference(parsed.toLocal());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return parsed.toLocal().toIso8601String().substring(0, 10);
  }

  @override
  Widget build(BuildContext context) {
    final configured = _smtp['configured'] == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Email history'),
        actions: [
          if (_isAdmin)
            IconButton(
              tooltip: 'Send a test email',
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              onPressed: _busy ? null : _sendTest,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: configured
                    ? const Color(0xFFECFDF5)
                    : const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: configured
                      ? const Color(0xFFA7F3D0)
                      : const Color(0xFFFCD34D),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    configured
                        ? Icons.mark_email_read_outlined
                        : Icons.mail_outline_rounded,
                    color: configured
                        ? const Color(0xFF059669)
                        : const Color(0xFFB45309),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      configured
                          ? 'SMTP ready: ${_smtp['host']}:${_smtp['port']} · from ${_smtp['fromEmail']}'
                          : 'SMTP is not configured. Emails are recorded in this history but not delivered.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final filter in <String?>[null, 'SENT', 'FAILED', 'SKIPPED'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(filter ?? 'All'),
                        selected: _statusFilter == filter,
                        onSelected: (_) {
                          setState(() => _statusFilter = filter);
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _items.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.mail_outline, size: 48),
                          SizedBox(height: 12),
                          Text('No emails yet'),
                          Text(
                            'Credentials, first-login and issue emails show up here.',
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final status = item['status']?.toString() ?? 'SKIPPED';
                        final recipient =
                            item['recipientEmail']?.toString() ??
                            item['recipientName']?.toString() ??
                            'no address';
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              Icons.mail_outline_rounded,
                              color: _statusColor(status),
                            ),
                            title: Text(
                              item['subject']?.toString() ?? 'Email',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_templateLabel(item['template']?.toString())} · $recipient',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _timeLabel(item['createdAt']?.toString()),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                if (item['errorMessage'] != null &&
                                    item['errorMessage'].toString().isNotEmpty)
                                  Text(
                                    item['errorMessage'].toString(),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFFDC2626),
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _statusColor(status).withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: _statusColor(status),
                                    ),
                                  ),
                                ),
                                if (_isAdmin)
                                  IconButton(
                                    tooltip: 'Send again',
                                    icon: const Icon(Icons.refresh, size: 18),
                                    onPressed: _busy
                                        ? null
                                        : () => _resend(item),
                                  ),
                              ],
                            ),
                            onTap: () => _showDetails(item),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showDetails(Map<String, dynamic> item) {
    final preview = item['bodyPreview']?.toString() ?? '';
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(item['subject']?.toString() ?? 'Email'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detail('Template', item['template']?.toString()),
                _detail('To', item['recipientEmail']?.toString()),
                _detail('Status', item['status']?.toString()),
                _detail('Sent at', item['sentAt']?.toString()),
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Preview',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    preview,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
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
  }

  Widget _detail(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
