import 'package:flutter/material.dart';
import '../../core/widgets/module_placeholder.dart';

class AuthenticationModuleScreen extends StatelessWidget {
  const AuthenticationModuleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholderScreen(
      moduleNumber: 1,
      title: 'Authentication, Store Setup & User Roles',
      scope: 'Sign-in, store profile, user roles, access checks and session management.',
      member: '1',
      integrationWithInventory: 'Provides store_id, authenticated user actor_id, and role verification for all inventory ledger movements.',
    );
  }
}
