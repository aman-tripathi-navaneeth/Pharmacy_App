enum TourStepType { info, syncStates, finish }

enum TourStatus {
  inProgress('IN_PROGRESS'),
  completed('COMPLETED'),
  skipped('SKIPPED');

  const TourStatus(this.wire);
  final String wire;

  static TourStatus parse(String s) => values.firstWhere((v) => v.wire == s, orElse: () => inProgress);
}

class TourItem {
  TourItem.fromJson(Map<String, dynamic> j)
      : labelKey = j['labelKey'] as String,
        descriptionKey = j['descriptionKey'] as String,
        tone = j['tone'] as String? ?? 'neutral';

  final String labelKey;
  final String descriptionKey;
  final String tone;
}

class TourStep {
  TourStep.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        type = TourStepType.values.asNameMap()[j['type']] ?? TourStepType.info,
        icon = j['icon'] as String? ?? 'storefront',
        titleKey = j['titleKey'] as String,
        bodyKey = j['bodyKey'] as String?,
        items = [for (final i in j['items'] as List? ?? const []) TourItem.fromJson(i as Map<String, dynamic>)];

  final String id;
  final TourStepType type;
  final String icon;
  final String titleKey;
  final String? bodyKey;
  final List<TourItem> items;
}

/// Versioned tour content: text is translation keys, so it follows the app language.
class TourDefinition {
  TourDefinition({required this.version, required this.steps, this.raw = const {}});

  factory TourDefinition.fromJson(Map<String, dynamic> j) => TourDefinition(
    version: j['version'] as String,
    steps: [for (final s in j['steps'] as List) TourStep.fromJson(s as Map<String, dynamic>)],
    raw: j,
  );

  final String version;
  final List<TourStep> steps;
  final Map<String, dynamic> raw;

  int indexOf(String? stepId) {
    final i = steps.indexWhere((s) => s.id == stepId);
    return i < 0 ? 0 : i;
  }
}

class TourProgress {
  const TourProgress({required this.status, required this.lastStepId});

  factory TourProgress.fromJson(Map<String, dynamic> j) =>
      TourProgress(status: TourStatus.parse(j['status'] as String), lastStepId: j['lastStepId'] as String);

  final TourStatus status;
  final String lastStepId;

  bool get finishedOrSkipped => status != TourStatus.inProgress;

  Map<String, dynamic> toJson() => {'status': status.wire, 'lastStepId': lastStepId};
}
