import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:iris/app/theme/iris_theme.dart';
import 'package:iris/core/widgets/iris_page_body.dart';
import 'package:iris/features/classification/application/evidence_classification_controller.dart';
import 'package:iris/features/classification/application/evidence_classification_service.dart';
import 'package:iris/features/classification/domain/evidence_classification.dart';
import 'package:iris/features/evidence/domain/evidence_image.dart';

void main() {
  testWidgets(
    'Analyze Image transitions from analyzing to result without a framework exception',
    (WidgetTester tester) async {
      final Completer<void> release = Completer<void>();
      final EvidenceImage evidence = EvidenceImage(
        id: 'evidence-a',
        caseId: 'case-a',
        storedRelativePath: 'cases/case-a/evidence/evidence-a.jpg',
        source: EvidenceSource.gallery,
        importedAt: DateTime.utc(2026),
        fileSizeBytes: 10,
        sha256: 'a' * 64,
      );
      final _DelayedClassificationOperations operations =
          _DelayedClassificationOperations(release, evidence);
      final EvidenceClassificationController controller =
          EvidenceClassificationController(
            evidence: evidence,
            operations: operations,
          );

      await tester.pumpWidget(
        MaterialApp(
          theme: IrisTheme.dark,
          home: Scaffold(
            body: IrisPageBody(
              children: <Widget>[
                const Text('Evidence Detail'),
                ListenableBuilder(
                  listenable: controller,
                  builder: (BuildContext context, Widget? child) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (controller.analyzing)
                        const CircularProgressIndicator()
                      else
                        Text(
                          controller.snapshot.state.name,
                          key: const ValueKey<String>('classification-state'),
                        ),
                      ElevatedButton(
                        key: const ValueKey<String>('analyze-image'),
                        onPressed: controller.analyze,
                        child: const Text('Analyze Image'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('analyze-image')));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(operations.calls, 1);

      // A second tap while inference is pending must not start another call.
      await tester.tap(find.byKey(const ValueKey<String>('analyze-image')));
      expect(operations.calls, 1);

      release.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('current'), findsOneWidget);
      expect(tester.takeException(), isNull);
      controller.dispose();
    },
  );
}

class _DelayedClassificationOperations
    implements EvidenceClassificationOperations {
  _DelayedClassificationOperations(this.release, this.evidence);
  final Completer<void> release;
  final EvidenceImage evidence;
  int calls = 0;
  EvidenceClassification? saved;

  @override
  Future<EvidenceClassificationSnapshot> load(EvidenceImage value) async {
    final EvidenceClassification? classification = saved;
    if (classification == null) {
      return const EvidenceClassificationSnapshot.notAnalyzed();
    }
    return EvidenceClassificationSnapshot.current(classification);
  }

  @override
  Future<EvidenceClassification> analyze(EvidenceImage value) async {
    calls++;
    await release.future;
    saved = EvidenceClassification(
      evidenceId: evidence.id,
      evidenceSha256: evidence.sha256,
      modelId: 'test-only-model',
      modelTfliteSha256: 'b' * 64,
      modelContractVersion: 'test-only-contract',
      rawLogit: 2,
      modelScore: 0.8807970779778823,
      threshold: 0.8611480594,
      label: EvidenceClassificationLabel.accident,
      analyzedAt: DateTime.utc(2026),
    );
    return saved!;
  }
}
