enum EvidenceFileState {
  available('available', 'Available'),
  missing('missing', 'Missing'),
  unreadable('unreadable', 'Unreadable');

  const EvidenceFileState(this.storageValue, this.displayLabel);

  final String storageValue;
  final String displayLabel;

  static EvidenceFileState fromStorage(String value) => values.firstWhere(
    (EvidenceFileState state) => state.storageValue == value,
    orElse: () => throw FormatException('Unknown evidence file state: $value'),
  );
}

enum EvidenceDecodeState {
  decoded('decoded', 'Decoded'),
  failed('failed', 'Decode failed'),
  notAttempted('not_attempted', 'Not attempted');

  const EvidenceDecodeState(this.storageValue, this.displayLabel);

  final String storageValue;
  final String displayLabel;

  static EvidenceDecodeState fromStorage(String value) => values.firstWhere(
    (EvidenceDecodeState state) => state.storageValue == value,
    orElse: () =>
        throw FormatException('Unknown evidence decode state: $value'),
  );
}

enum EvidenceIntegrityState {
  verified('verified', 'Verified'),
  mismatch('mismatch', 'Changed / hash mismatch'),
  unavailable('unavailable', 'Unavailable');

  const EvidenceIntegrityState(this.storageValue, this.displayLabel);

  final String storageValue;
  final String displayLabel;

  static EvidenceIntegrityState fromStorage(String value) => values.firstWhere(
    (EvidenceIntegrityState state) => state.storageValue == value,
    orElse: () =>
        throw FormatException('Unknown evidence integrity state: $value'),
  );
}

enum EvidenceReadiness {
  ready('ready', 'Ready'),
  usableWithLimitations('usable_with_limitations', 'Usable with limitations'),
  notUsable('not_usable', 'Not usable');

  const EvidenceReadiness(this.storageValue, this.displayLabel);

  final String storageValue;
  final String displayLabel;

  static EvidenceReadiness fromStorage(String value) => values.firstWhere(
    (EvidenceReadiness state) => state.storageValue == value,
    orElse: () => throw FormatException('Unknown evidence readiness: $value'),
  );
}

enum EvidenceOrientation {
  portrait('portrait', 'Portrait'),
  landscape('landscape', 'Landscape'),
  square('square', 'Square');

  const EvidenceOrientation(this.storageValue, this.displayLabel);

  final String storageValue;
  final String displayLabel;

  static EvidenceOrientation fromStorage(String value) => values.firstWhere(
    (EvidenceOrientation orientation) => orientation.storageValue == value,
    orElse: () => throw FormatException('Unknown evidence orientation: $value'),
  );
}

enum EvidenceQualitySeverity {
  info('info'),
  warning('warning'),
  critical('critical');

  const EvidenceQualitySeverity(this.storageValue);

  final String storageValue;

  static EvidenceQualitySeverity fromStorage(String value) => values.firstWhere(
    (EvidenceQualitySeverity severity) => severity.storageValue == value,
    orElse: () =>
        throw FormatException('Unknown evidence finding severity: $value'),
  );
}

enum EvidenceQualityMetric {
  fileAvailability('file_availability'),
  readability('readability'),
  decoding('decoding'),
  integrity('integrity'),
  resolution('resolution'),
  sharpness('sharpness'),
  brightness('brightness'),
  darkClipping('dark_clipping'),
  brightClipping('bright_clipping'),
  processing('processing');

  const EvidenceQualityMetric(this.storageValue);

  final String storageValue;

  static EvidenceQualityMetric fromStorage(String value) => values.firstWhere(
    (EvidenceQualityMetric metric) => metric.storageValue == value,
    orElse: () => throw FormatException('Unknown evidence metric: $value'),
  );
}

enum EvidenceQualityFindingCode {
  fileMissing('file_missing'),
  unreadable('unreadable'),
  decodeFailed('decode_failed'),
  integrityMismatch('integrity_mismatch'),
  lowResolution('low_resolution'),
  possibleBlur('possible_blur'),
  veryDark('very_dark'),
  veryBright('very_bright'),
  darkClipping('dark_clipping'),
  brightClipping('bright_clipping'),
  assessmentFailed('assessment_failed');

  const EvidenceQualityFindingCode(this.storageValue);

  final String storageValue;

  static EvidenceQualityFindingCode fromStorage(String value) =>
      values.firstWhere(
        (EvidenceQualityFindingCode code) => code.storageValue == value,
        orElse: () =>
            throw FormatException('Unknown evidence finding code: $value'),
      );
}

class EvidenceQualityFinding {
  const EvidenceQualityFinding({
    required this.code,
    required this.severity,
    required this.metric,
    required this.explanation,
    this.measuredValue,
    this.threshold,
    this.unit,
  });

  final EvidenceQualityFindingCode code;
  final EvidenceQualitySeverity severity;
  final EvidenceQualityMetric metric;
  final double? measuredValue;
  final double? threshold;
  final String? unit;
  final String explanation;
}

class EvidenceQualityAssessment {
  const EvidenceQualityAssessment({
    required this.evidenceId,
    required this.assessedAt,
    required this.algorithmVersion,
    required this.expectedSha256,
    required this.fileState,
    required this.decodeState,
    required this.integrityState,
    required this.readiness,
    required this.findings,
    this.assessedSha256,
    this.fileSizeBytes,
    this.originalWidth,
    this.originalHeight,
    this.analysisWidth,
    this.analysisHeight,
    this.orientation,
    this.sharpnessValue,
    this.meanLuminance,
    this.darkClippedFraction,
    this.brightClippedFraction,
  });

  final String evidenceId;
  final DateTime assessedAt;
  final String algorithmVersion;
  final String expectedSha256;
  final String? assessedSha256;
  final EvidenceFileState fileState;
  final EvidenceDecodeState decodeState;
  final EvidenceIntegrityState integrityState;
  final EvidenceReadiness readiness;
  final int? fileSizeBytes;
  final int? originalWidth;
  final int? originalHeight;
  final int? analysisWidth;
  final int? analysisHeight;
  final EvidenceOrientation? orientation;
  final double? sharpnessValue;
  final double? meanLuminance;
  final double? darkClippedFraction;
  final double? brightClippedFraction;
  final List<EvidenceQualityFinding> findings;

  int? get pixelCount => originalWidth == null || originalHeight == null
      ? null
      : originalWidth! * originalHeight!;

  double? get megapixels {
    final int? pixels = pixelCount;
    return pixels == null ? null : pixels / 1000000;
  }
}

enum EvidenceQualitySnapshotState { current, notAssessed, stale, unavailable }

class EvidenceQualitySnapshot {
  const EvidenceQualitySnapshot._(this.state, this.assessment);

  const EvidenceQualitySnapshot.current(EvidenceQualityAssessment assessment)
    : this._(EvidenceQualitySnapshotState.current, assessment);

  const EvidenceQualitySnapshot.notAssessed()
    : this._(EvidenceQualitySnapshotState.notAssessed, null);

  const EvidenceQualitySnapshot.stale(EvidenceQualityAssessment assessment)
    : this._(EvidenceQualitySnapshotState.stale, assessment);

  const EvidenceQualitySnapshot.unavailable()
    : this._(EvidenceQualitySnapshotState.unavailable, null);

  final EvidenceQualitySnapshotState state;
  final EvidenceQualityAssessment? assessment;
}
