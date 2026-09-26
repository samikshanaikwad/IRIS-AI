import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:iris/app/theme/iris_theme.dart';
import 'package:iris/core/widgets/iris_button.dart';
import 'package:iris/features/evidence/domain/evidence_image.dart';
import 'package:iris/features/evidence_quality/application/evidence_quality_controller.dart';
import 'package:iris/features/evidence_quality/application/evidence_quality_service.dart';
import 'package:iris/features/evidence_quality/domain/evidence_quality_assessment.dart';
import 'package:iris/features/evidence_quality/presentation/evidence_quality_section.dart';
import 'package:iris/features/evidence_quality/processing/image_quality_analyzer.dart';

void main() {
  Future<void> pumpSection(
    WidgetTester tester,
    EvidenceQualityOperations operations,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: IrisTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: EvidenceQualitySection(
                controller: EvidenceQualityController(
                  evidence: _evidence,
                  operations: operations,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('not assessed is distinct and explains non-AI scope', (
    WidgetTester tester,
  ) async {
    await pumpSection(tester, _TestOperations());

    expect(find.textContaining('Not assessed'), findsOneWidget);
    expect(find.text('Assess Quality'), findsOneWidget);
    expect(
      find.textContaining('do not determine whether an accident occurred'),
      findsOneWidget,
    );
    expect(find.textContaining('AI confidence'), findsNothing);
    expect(find.textContaining('Accident detected'), findsNothing);
    expect(find.textContaining('Reconstruction complete'), findsNothing);
  });

  testWidgets('ready result renders real metrics and reassess action', (
    WidgetTester tester,
  ) async {
    await pumpSection(
      tester,
      _TestOperations(
        snapshot: EvidenceQualitySnapshot.current(
          _assessment(readiness: EvidenceReadiness.ready),
        ),
      ),
    );

    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Integrity: Verified'), findsOneWidget);
    expect(find.textContaining('1280 × 720 px'), findsOneWidget);
    expect(find.textContaining('156.25 Laplacian variance'), findsOneWidget);
    expect(find.text('128.50 / 255'), findsOneWidget);
    expect(find.text('3.0%'), findsOneWidget);
    expect(find.text('2.0%'), findsOneWidget);
    expect(find.text('Reassess Quality'), findsOneWidget);
    expect(
      find.text('No configured technical quality limitations were found.'),
      findsOneWidget,
    );
  });

  testWidgets('limitations render deterministic finding explanation', (
    WidgetTester tester,
  ) async {
    await pumpSection(
      tester,
      _TestOperations(
        snapshot: EvidenceQualitySnapshot.current(
          _assessment(
            readiness: EvidenceReadiness.usableWithLimitations,
            findings: const <EvidenceQualityFinding>[
              EvidenceQualityFinding(
                code: EvidenceQualityFindingCode.possibleBlur,
                severity: EvidenceQualitySeverity.warning,
                metric: EvidenceQualityMetric.sharpness,
                measuredValue: 42,
                threshold: 100,
                unit: 'Laplacian variance',
                explanation:
                    'Sharpness is below the current IRIS analysis threshold.',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Usable with limitations'), findsOneWidget);
    expect(
      find.text('Sharpness is below the current IRIS analysis threshold.'),
      findsOneWidget,
    );
  });

  testWidgets('not usable integrity mismatch is visibly explained', (
    WidgetTester tester,
  ) async {
    await pumpSection(
      tester,
      _TestOperations(
        snapshot: EvidenceQualitySnapshot.current(
          _assessment(
            readiness: EvidenceReadiness.notUsable,
            integrity: EvidenceIntegrityState.mismatch,
            findings: const <EvidenceQualityFinding>[
              EvidenceQualityFinding(
                code: EvidenceQualityFindingCode.integrityMismatch,
                severity: EvidenceQualitySeverity.critical,
                metric: EvidenceQualityMetric.integrity,
                explanation:
                    'The stored evidence bytes no longer match the SHA-256 recorded at import.',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Not usable'), findsOneWidget);
    expect(find.text('Integrity: Changed / hash mismatch'), findsOneWidget);
    expect(find.textContaining('no longer match the SHA-256'), findsOneWidget);
  });

  testWidgets(
    'assessment displays indeterminate progress and disables repeat',
    (WidgetTester tester) async {
      final Completer<EvidenceQualityAssessment> completer =
          Completer<EvidenceQualityAssessment>();
      final _TestOperations operations = _TestOperations(
        onAssess: () => completer.future,
      );
      await pumpSection(tester, operations);

      await tester.tap(
        find.byKey(const ValueKey<String>('assess-evidence-quality-button')),
      );
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Assessing quality…'), findsOneWidget);
      final IrisSecondaryButton button = tester.widget<IrisSecondaryButton>(
        find.byKey(const ValueKey<String>('assess-evidence-quality-button')),
      );
      expect(button.onPressed, isNull);
      expect(operations.assessCalls, 1);

      completer.complete(_assessment(readiness: EvidenceReadiness.ready));
      await tester.pumpAndSettle();
      expect(find.text('Ready'), findsOneWidget);
      expect(operations.assessCalls, 1);
    },
  );

  testWidgets('stale assessment requires reassessment without stale metrics', (
    WidgetTester tester,
  ) async {
    await pumpSection(
      tester,
      _TestOperations(
        snapshot: EvidenceQualitySnapshot.stale(
          _assessment(readiness: EvidenceReadiness.ready),
        ),
      ),
    );

    expect(find.textContaining('Reassessment needed'), findsOneWidget);
    expect(find.text('Reassess Quality'), findsOneWidget);
    expect(find.textContaining('1280 × 720 px'), findsNothing);
  });

  testWidgets('persistence failure is reported without a saved result', (
    WidgetTester tester,
  ) async {
    await pumpSection(
      tester,
      _TestOperations(
        onAssess: () async => throw EvidenceQualityPersistenceException(
          StateError('Controlled persistence failure.'),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('assess-evidence-quality-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Quality checks completed, but the assessment could not be saved.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Not assessed'), findsOneWidget);
    expect(find.text('Ready'), findsNothing);
  });
}

class _TestOperations implements EvidenceQualityOperations {
  _TestOperations({
    this.snapshot = const EvidenceQualitySnapshot.notAssessed(),
    this.onAssess,
  });

  final EvidenceQualitySnapshot snapshot;
  final Future<EvidenceQualityAssessment> Function()? onAssess;
  int assessCalls = 0;

  @override
  Future<EvidenceQualityAssessment> assess(EvidenceImage evidence) {
    assessCalls++;
    final Future<EvidenceQualityAssessment> Function()? callback = onAssess;
    return callback == null
        ? Future<EvidenceQualityAssessment>.value(
            _assessment(readiness: EvidenceReadiness.ready),
          )
        : callback();
  }

  @override
  Future<EvidenceQualitySnapshot> load(EvidenceImage evidence) async =>
      snapshot;
}

final EvidenceImage _evidence = EvidenceImage(
  id: 'test-evidence',
  caseId: 'test-case',
  storedRelativePath: 'test.png',
  source: EvidenceSource.gallery,
  importedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  fileSizeBytes: 2048,
  sha256: _testHash,
);

const String _testHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

EvidenceQualityAssessment _assessment({
  required EvidenceReadiness readiness,
  EvidenceIntegrityState integrity = EvidenceIntegrityState.verified,
  List<EvidenceQualityFinding> findings = const <EvidenceQualityFinding>[],
}) => EvidenceQualityAssessment(
  evidenceId: _evidence.id,
  assessedAt: DateTime.utc(2026, 9, 27),
  algorithmVersion: FlutterImageQualityAnalyzer.algorithmVersion,
  expectedSha256: _testHash,
  assessedSha256: integrity == EvidenceIntegrityState.mismatch
      ? 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
      : _testHash,
  fileState: EvidenceFileState.available,
  decodeState: EvidenceDecodeState.decoded,
  integrityState: integrity,
  readiness: readiness,
  fileSizeBytes: 2048,
  originalWidth: 1280,
  originalHeight: 720,
  analysisWidth: 1024,
  analysisHeight: 576,
  orientation: EvidenceOrientation.landscape,
  sharpnessValue: 156.25,
  meanLuminance: 128.5,
  darkClippedFraction: 0.03,
  brightClippedFraction: 0.02,
  findings: findings,
);
