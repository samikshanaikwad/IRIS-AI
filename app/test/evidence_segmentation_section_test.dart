import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/evidence/domain/evidence_image.dart';
import 'package:iris/core/widgets/iris_button.dart';
import 'package:iris/features/segmentation/application/evidence_segmentation_controller.dart';
import 'package:iris/features/segmentation/application/evidence_segmentation_service.dart';
import 'package:iris/features/segmentation/domain/evidence_segmentation.dart';
import 'package:iris/features/segmentation/presentation/evidence_segmentation_section.dart';

void main() {
  final evidence = EvidenceImage(
    id: 'evidence',
    caseId: 'case',
    storedRelativePath: 'evidence.jpg',
    source: EvidenceSource.gallery,
    importedAt: _date,
    fileSizeBytes: 1,
    sha256: _sha,
  );

  testWidgets('release gate is explicit and disables segmentation execution', (
    tester,
  ) async {
    final operations = _Operations(enabled: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EvidenceSegmentationSection(
            controller: EvidenceSegmentationController(
              evidence: evidence,
              operations: operations,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('redistribution'), findsOneWidget);
    final button = tester.widget<IrisPrimaryButton>(
      find.byKey(const ValueKey<String>('run-evidence-segmentation')),
    );
    expect(button.onPressed, isNull);
    expect(operations.analyzeCalls, 0);
  });

  testWidgets('evidence action reports unsupported without a fallback mask', (
    tester,
  ) async {
    final operations = _Operations(enabled: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EvidenceSegmentationSection(
            controller: EvidenceSegmentationController(
              evidence: evidence,
              operations: operations,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('run-evidence-segmentation')),
    );
    await tester.pumpAndSettle();

    expect(operations.analyzeCalls, 1);
    expect(find.textContaining('No qualified vehicle'), findsOneWidget);
  });
}

class _Operations implements EvidenceSegmentationOperations {
  _Operations({required this.enabled});
  final bool enabled;
  int analyzeCalls = 0;

  @override
  bool get executionEnabled => enabled;

  @override
  Future<EvidenceSegmentationAnalysis> analyze(
    EvidenceImage evidence, {
    EvidenceSegmentationCancellation? cancellation,
    void Function()? onStarted,
  }) async {
    analyzeCalls++;
    onStarted?.call();
    throw const EvidenceSegmentationUnavailable(
      'No qualified vehicle detection is available; no fallback mask was saved.',
    );
  }

  @override
  Future<EvidenceSegmentationSnapshot> load(EvidenceImage evidence) async =>
      const EvidenceSegmentationSnapshot(EvidenceSegmentationState.notAnalyzed);

  @override
  Future<String> overlayAbsolutePath(
    EvidenceSegmentationAnalysis analysis,
  ) async => throw UnsupportedError('No overlay in this fixture.');
}

final _date = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
const _sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
