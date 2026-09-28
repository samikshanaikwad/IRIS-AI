import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/multiview/domain/multiview_pair_analysis.dart';

void main() {
  test('canonical pair id is independent of selection order', () {
    expect(canonicalPairId('evidence-b', 'evidence-a'), 'evidence-a::evidence-b');
    expect(canonicalPairId('evidence-a', 'evidence-b'), 'evidence-a::evidence-b');
  });

  test('stale analysis is detected from changed evidence provenance', () {
    final analysis = MultiViewPairAnalysis(
      id: 'a:b',
      caseId: 'case',
      evidenceAId: 'a',
      evidenceBId: 'b',
      evidenceASha256: 'sha-a',
      evidenceBSha256: 'sha-b',
      featureCountA: 10,
      featureCountB: 10,
      candidateMatchCount: 5,
      acceptedMatchCount: 4,
      verifiedInlierCount: 3,
      inlierRatio: .75,
      status: MultiViewStatus.verifiedCorrespondence,
      correspondences: const [],
      analyzedAt: DateTime(2026),
    );
    expect(analysis.isStale('sha-a', 'sha-b'), isFalse);
    expect(analysis.isStale('changed', 'sha-b'), isTrue);
  });
}
