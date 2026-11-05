import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ModulePlaceholderScreen extends StatelessWidget {
  final int moduleNumber;
  final String title;
  final String scope;
  final String member;
  final String integrationWithInventory;

  const ModulePlaceholderScreen({
    super.key,
    required this.moduleNumber,
    required this.title,
    required this.scope,
    required this.member,
    required this.integrationWithInventory,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.slateBorder.withOpacity(0.4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.handyman_outlined,
                  size: 48,
                  color: AppTheme.slateMuted,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Module $moduleNumber: $title',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slateDark,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.amberLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Assigned to Member $member (Module $moduleNumber)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.amberWarning,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.slateBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Module Scope',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slateHeading,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      scope,
                      style: const TextStyle(fontSize: 12, color: AppTheme.slateBody, height: 1.4),
                    ),
                    const Divider(height: 24),
                    const Text(
                      'Integration Contract with Module 5 (Inventory):',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryTeal,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      integrationWithInventory,
                      style: const TextStyle(fontSize: 12, color: AppTheme.slateMuted, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back to Inventory (Module 5)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
