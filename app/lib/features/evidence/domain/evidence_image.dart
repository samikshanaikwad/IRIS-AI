enum EvidenceSource {
  camera('camera', 'Camera'),
  gallery('gallery', 'Gallery');

  const EvidenceSource(this.storageValue, this.displayLabel);

  final String storageValue;
  final String displayLabel;

  static EvidenceSource fromStorage(String value) {
    return EvidenceSource.values.firstWhere(
      (EvidenceSource source) => source.storageValue == value,
      orElse: () => throw FormatException('Unknown evidence source: $value'),
    );
  }
}

class EvidenceImage {
  const EvidenceImage({
    required this.id,
    required this.caseId,
    required this.storedRelativePath,
    required this.source,
    required this.importedAt,
    required this.fileSizeBytes,
    required this.sha256,
    this.originalDisplayName,
    this.capturedAt,
    this.mimeType,
    this.widthPx,
    this.heightPx,
  });

  final String id;
  final String caseId;
  final String storedRelativePath;
  final String? originalDisplayName;
  final EvidenceSource source;
  final DateTime? capturedAt;
  final DateTime importedAt;
  final String? mimeType;
  final int? widthPx;
  final int? heightPx;
  final int fileSizeBytes;
  final String sha256;
}
