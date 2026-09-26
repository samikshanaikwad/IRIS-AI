enum CaseStatus {
  draft('draft', 'Draft'),
  unknown('unknown', 'Unknown');

  const CaseStatus(this.storageValue, this.displayLabel);

  final String storageValue;
  final String displayLabel;

  static CaseStatus fromStorage(String value) {
    return CaseStatus.values.where((status) {
          return status != CaseStatus.unknown && status.storageValue == value;
        }).firstOrNull ??
        CaseStatus.unknown;
  }
}
