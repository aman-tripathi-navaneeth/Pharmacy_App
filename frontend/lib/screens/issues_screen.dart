import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api_session.dart';
import '../widgets/app_shell.dart';

/// Owner-facing screen: report an issue to the super admin and track the
/// status of every report they have raised.
class IssuesScreen extends StatefulWidget {
  const IssuesScreen({super.key});

  @override
  State<IssuesScreen> createState() => _IssuesScreenState();
}

class _IssuesScreenState extends State<IssuesScreen> {
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _category = 'APP_BUG';
  bool _isSubmitting = false;
  List<dynamic> _issues = [];
  bool _isLoading = true;

  static const Map<String, String> _categoryLabels = {
    'BILLING': 'Billing problem',
    'STOCK': 'Stock or inventory',
    'APP_BUG': 'App not working',
    'OTHER': 'Something else',
  };

  @override
  void initState() {
    super.initState();
    _loadIssues();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadIssues() async {
    setState(() => _isLoading = true);
    try {
      final response = await http
          .get(Uri.parse('$_apiBaseUrl/api/issues'), headers: ApiSession.headers)
          .timeout(const Duration(seconds: 8));
      if (mounted && response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() => _issues = data['items'] as List<dynamic>? ?? []);
      }
    } catch (_) {
      // List stays empty; the error bar shows below.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitIssue() async {
    if (_titleController.text.trim().length < 4 ||
        _descriptionController.text.trim().length < 4) {
      return;
    }
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/api/issues'),
            headers: ApiSession.headers,
            body: jsonEncode({
              'title': _titleController.text.trim(),
              'description': _descriptionController.text.trim(),
              'category': _category,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (response.statusCode == 201) {
        _titleController.clear();
        _descriptionController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Issue reported. The admin will look into it.'),
          ),
        );
        await _loadIssues();
      } else {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message']?.toString() ?? 'Could not report issue'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection error. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'RESOLVED':
        return const Color(0xFF1F7A45);
      case 'IN_PROGRESS':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFFDC2626);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      selectedTab: -1,
      showBack: true,
      body: RefreshIndicator(
        onRefresh: _loadIssues,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ---- Report form --------------------------------------------
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.report_problem_outlined,
                        color: Color(0xFF0B4F3A),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Report a new issue',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _titleController,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Issue title',
                      hintText: 'e.g. Bill total shows wrong after discount',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final entry in _categoryLabels.entries)
                        DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _category = value ?? 'APP_BUG'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 4,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: 'What happened?',
                      hintText: 'Describe the problem so the admin can fix it fast',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0B4F3A),
                      ),
                      onPressed: _isSubmitting ||
                              _titleController.text.trim().length < 4 ||
                              _descriptionController.text.trim().length < 4
                          ? null
                          : _submitIssue,
                      icon: _isSubmitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_outlined),
                      label: const Text('Send to admin'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Your reports',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_issues.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No reports yet. You are all set!')),
              )
            else
              for (final issue in _issues)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              issue['title']?.toString() ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor(issue['status']?.toString()),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              (issue['status']?.toString() ?? '')
                                  .replaceAll('_', ' '),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if ((issue['resolutionNote'] as String?)?.isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Admin: ${issue['resolutionNote']}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
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
}

/// Super-admin screen: monitor every owner issue and move them to
/// IN_PROGRESS / RESOLVED with an optional note. No one reports to the super
/// admin, so this is purely a monitoring console.
class AdminIssuesScreen extends StatefulWidget {
  const AdminIssuesScreen({super.key});

  @override
  State<AdminIssuesScreen> createState() => _AdminIssuesScreenState();
}

class _AdminIssuesScreenState extends State<AdminIssuesScreen> {
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  String _statusFilter = 'OPEN';
  List<dynamic> _issues = [];
  bool _isLoading = true;

  static const Map<String, String> _statusLabels = {
    'OPEN': 'Open',
    'IN_PROGRESS': 'In progress',
    'RESOLVED': 'Resolved',
  };

  @override
  void initState() {
    super.initState();
    _loadIssues();
  }

  Future<void> _loadIssues() async {
    setState(() => _isLoading = true);
    try {
      final response = await http
          .get(
            Uri.parse('$_apiBaseUrl/api/issues?status=$_statusFilter'),
            headers: ApiSession.headers,
          )
          .timeout(const Duration(seconds: 8));
      if (mounted && response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() => _issues = data['items'] as List<dynamic>? ?? []);
      }
    } catch (_) {
      // Keep whatever is loaded; the empty state shows below.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateStatus(Map<String, dynamic> issue, String next) async {
    final noteController = TextEditingController(
      text: issue['resolutionNote']?.toString() ?? '',
    );
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Mark as ${_statusLabels[next] ?? next}?'),
        content: TextField(
          controller: noteController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Note for the owner (optional)',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(noteController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    noteController.dispose();
    if (note == null) return;
    try {
      final response = await http
          .patch(
            Uri.parse(
              '$_apiBaseUrl/api/issues/${issue['_id']}/status',
            ),
            headers: ApiSession.headers,
            body: jsonEncode({'status': next, 'note': note}),
          )
          .timeout(const Duration(seconds: 8));
      if (mounted && response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Marked ${_statusLabels[next] ?? next}')),
        );
        await _loadIssues();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update issue')),
        );
      }
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'RESOLVED':
        return const Color(0xFF1F7A45);
      case 'IN_PROGRESS':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFFDC2626);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('Issue reports'),
        backgroundColor: const Color(0xFF0B4F3A),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<String>(
              segments: [
                for (final entry in _statusLabels.entries)
                  ButtonSegment(value: entry.key, label: Text(entry.value)),
              ],
              selected: {_statusFilter},
              onSelectionChanged: (selection) {
                setState(() => _statusFilter = selection.first);
                _loadIssues();
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _issues.isEmpty
                ? Center(
                    child: Text('No ${_statusLabels[_statusFilter] ?? _statusFilter} issues. All caught up!'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: _issues.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final issue = _issues[index] as Map<String, dynamic>;
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    issue['title']?.toString() ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _statusColor(
                                      issue['status']?.toString(),
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    (issue['status']?.toString() ?? '')
                                        .replaceAll('_', ' '),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              issue['description']?.toString() ?? '',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF334155),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'From: ${issue['createdByName'] ?? 'Owner'}'
                              ' · ${(issue['category'] ?? 'OTHER')}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: () => _updateStatus(
                                    issue,
                                    issue['status'] == 'IN_PROGRESS'
                                        ? 'OPEN'
                                        : 'IN_PROGRESS',
                                  ),
                                  child: Text(
                                    issue['status'] == 'IN_PROGRESS'
                                        ? 'Reopen'
                                        : 'Start work',
                                  ),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF1F7A45),
                                  ),
                                  onPressed: () =>
                                      _updateStatus(issue, 'RESOLVED'),
                                  child: const Text('Mark resolved'),
                                ),
                              ],
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
