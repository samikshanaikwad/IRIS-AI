enum MultiViewStatus { verifiedCorrespondence, insufficientFeatures, insufficientMatches, geometricVerificationFailed, error }

class MultiViewPairAnalysis {
  const MultiViewPairAnalysis({required this.id, required this.caseId, required this.evidenceAId, required this.evidenceBId, required this.evidenceASha256, required this.evidenceBSha256, required this.featureCountA, required this.featureCountB, required this.candidateMatchCount, required this.acceptedMatchCount, required this.verifiedInlierCount, required this.inlierRatio, required this.status, required this.correspondences, required this.analyzedAt, this.message, this.imageWidthA = 640, this.imageHeightA = 640, this.imageWidthB = 640, this.imageHeightB = 640});
  final String id, caseId, evidenceAId, evidenceBId, evidenceASha256, evidenceBSha256;
  final int featureCountA, featureCountB, candidateMatchCount, acceptedMatchCount, verifiedInlierCount;
  final double inlierRatio;
  final MultiViewStatus status;
  final List<List<double>> correspondences;
  final DateTime analyzedAt;
  final String? message;
  final int imageWidthA, imageHeightA, imageWidthB, imageHeightB;
  bool isStale(String a, String b) => a != evidenceASha256 || b != evidenceBSha256;
}

String canonicalPairId(String a, String b) => a.compareTo(b) < 0 ? '$a::$b' : '$b::$a';
String statusFromNative(String value) => value;
