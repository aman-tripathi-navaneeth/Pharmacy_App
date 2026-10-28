import '../../../l10n/translations.dart';

/// Which actions may be queued offline, and how their conflicts may be resolved.
///
/// "Only explicitly supported operations may be queued" (spec §3). Each domain
/// owner adds their operation here once the matching server handler exists.
class OfflineOperationSpec {
  const OfflineOperationSpec({
    required this.module,
    required this.operationType,
    required this.title,
    required this.moduleLabel,
    this.allowKeepDeviceVersion = false,
    this.fieldLabels = const {},
  });

  final String module;
  final String operationType;

  /// Human label, e.g. "Stock movement".
  final String title;

  /// Module label shown in lists, e.g. "Inventory".
  final String moduleLabel;

  /// Whether "Keep this device version" is a permitted conflict resolution.
  /// Ledger-style operations (stock, sales, payments) must never overwrite.
  final bool allowKeepDeviceVersion;

  /// Labels for payload fields shown on the conflict screen.
  final Map<String, String> fieldLabels;

  /// Translated names, falling back to the English given here.
  String get displayTitle => trOrNull('catalog.$module.$operationType') ?? title;

  String fieldLabel(String key) =>
      trOrNull('catalog.field.$module.$key') ?? fieldLabels[key] ?? key[0].toUpperCase() + key.substring(1);

  String get key => '$module.$operationType';
}

class OfflineCatalog {
  const OfflineCatalog(this._specs);

  final Map<String, OfflineOperationSpec> _specs;

  static final OfflineCatalog standard = OfflineCatalog.of(const [
    OfflineOperationSpec(
      module: 'inventory',
      operationType: 'stock_movement',
      title: 'Stock movement',
      moduleLabel: 'Inventory',
    ),
    OfflineOperationSpec(
      module: 'shop',
      operationType: 'profile_update',
      title: 'Shop profile edit',
      moduleLabel: 'Shop profile',
      allowKeepDeviceVersion: true,
      fieldLabels: {'name': 'Shop name', 'phone': 'Shop phone', 'address': 'Address', 'email': 'Email'},
    ),
  ]);

  factory OfflineCatalog.of(List<OfflineOperationSpec> specs) =>
      OfflineCatalog({for (final s in specs) s.key: s});

  OfflineOperationSpec? lookup(String module, String operationType) => _specs['$module.$operationType'];

  bool isSupported(String module, String operationType) => lookup(module, operationType) != null;

  String moduleLabel(String module) =>
      trOrNull('catalog.module.$module') ??
      _specs.values.where((s) => s.module == module).map((s) => s.moduleLabel).firstOrNull ??
      module[0].toUpperCase() + module.substring(1);
}
