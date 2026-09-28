enum EvidenceClassificationLabel {
  accident('accident', 'Accident'),
  nonAccident('non_accident', 'Non-accident');

  const EvidenceClassificationLabel(this.storageValue, this.displayLabel);
  final String storageValue;
  final String displayLabel;

  static EvidenceClassificationLabel fromStorage(String value) =>
      values.firstWhere(
        (EvidenceClassificationLabel label) => label.storageValue == value,
        orElse: () =>
            throw FormatException('Unknown classification label: $value'),
      );
}

class EvidenceClassification {
  const EvidenceClassification({
    required this.evidenceId,
    required this.evidenceSha256,
    required this.modelId,
    required this.modelTfliteSha256,
    required this.modelContractVersion,
    required this.rawLogit,
    required this.modelScore,
    required this.threshold,
    required this.label,
    required this.analyzedAt,
  });

  final String evidenceId;
  final String evidenceSha256;
  final String modelId;
  final String modelTfliteSha256;
  final String modelContractVersion;
  final double rawLogit;
  final double modelScore;
  final double threshold;
  final EvidenceClassificationLabel label;
  final DateTime analyzedAt;
}

enum EvidenceClassificationState {
  notAnalyzed,
  qualityRequired,
  blocked,
  current,
  stale,
  unavailable,
}

class EvidenceClassificationSnapshot {
  const EvidenceClassificationSnapshot._(
    this.state,
    this.classification, {
    this.qualityHasLimitations = false,
  });
  const EvidenceClassificationSnapshot.notAnalyzed({
    bool qualityHasLimitations = false,
  }) : this._(
         EvidenceClassificationState.notAnalyzed,
         null,
         qualityHasLimitations: qualityHasLimitations,
       );
  const EvidenceClassificationSnapshot.qualityRequired()
    : this._(EvidenceClassificationState.qualityRequired, null);
  const EvidenceClassificationSnapshot.blocked()
    : this._(EvidenceClassificationState.blocked, null);
  const EvidenceClassificationSnapshot.current(
    EvidenceClassification value, {
    bool qualityHasLimitations = false,
  }) : this._(
         EvidenceClassificationState.current,
         value,
         qualityHasLimitations: qualityHasLimitations,
       );
  const EvidenceClassificationSnapshot.stale(
    EvidenceClassification value, {
    bool qualityHasLimitations = false,
  }) : this._(
         EvidenceClassificationState.stale,
         value,
         qualityHasLimitations: qualityHasLimitations,
       );
  const EvidenceClassificationSnapshot.unavailable()
    : this._(EvidenceClassificationState.unavailable, null);
  final EvidenceClassificationState state;
  final EvidenceClassification? classification;
  final bool qualityHasLimitations;
}
