import 'package:flutter/material.dart';
import '../../core/widgets/module_placeholder.dart';

class CatalogueModuleScreen extends StatelessWidget {
  const CatalogueModuleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholderScreen(
      moduleNumber: 2,
      title: 'Medicine Catalogue, Search & Units',
      scope: 'Medicine/product records, generic synonyms, units, and pack-to-base conversion factors.',
      member: '2',
      integrationWithInventory: 'Supplies product_id, base_unit definitions (TABLET, BOTTLE, etc.), and unit conversion factors for batch registration.',
    );
  }
}
