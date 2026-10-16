import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/evidence/application/evidence_acquisition_service.dart';
import 'package:iris/features/evidence/application/evidence_controller.dart';
import 'package:iris/features/evidence/data/evidence_storage.dart';
import 'package:iris/features/evidence/domain/evidence_image.dart';
import 'package:iris/features/evidence/domain/evidence_repository.dart';
import 'package:iris/features/scenarios/application/accident_scenario_service.dart';
import 'package:iris/features/scenarios/domain/accident_scenario.dart';
import 'package:iris/features/scenarios/presentation/accident_scenario_section.dart';

void main() {
  testWidgets(
    'production section starts fail-closed without canned scenarios',
    (tester) async {
      final repository = _EvidenceRepository();
      final controller = EvidenceController(
        caseId: 'case-1',
        repository: repository,
        storage: EvidenceStorage(),
        acquisition: EvidenceAcquisitionService(
          repository: repository,
          storage: EvidenceStorage(),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccidentScenarioSection(
              caseId: 'case-1',
              service: _Operations(),
              evidenceController: controller,
            ),
          ),
        ),
      );
      expect(find.textContaining('Not assessed'), findsOneWidget);
      expect(find.textContaining('rear-end'), findsNothing);
      expect(find.textContaining('frontal'), findsNothing);
      expect(
        find.textContaining('collision with a fixed object'),
        findsNothing,
      );
      controller.dispose();
    },
  );

  testWidgets('insufficient analysis shows no unsupported conclusion', (
    tester,
  ) async {
    final repository = _EvidenceRepository();
    final controller = EvidenceController(
      caseId: 'case-1',
      repository: repository,
      storage: EvidenceStorage(),
      acquisition: EvidenceAcquisitionService(
        repository: repository,
        storage: EvidenceStorage(),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccidentScenarioSection(
            caseId: 'case-1',
            service: _Operations(),
            evidenceController: controller,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Review scenario evidence'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate evidence-grounded hypotheses'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Insufficient evidence'),
      findsAtLeastNWidgets(1),
    );
    expect(find.textContaining('Possible rear-end'), findsNothing);
    controller.dispose();
  });
}

class _Operations implements AccidentScenarioOperations {
  AccidentScenarioAnalysis? value;
  @override
  Future<ScenarioWorkspace> load(String caseId) async => ScenarioWorkspace(
    evidence: const [],
    observations: const [],
    analysis: value,
  );
  @override
  Future<AccidentScenarioAnalysis> generate(String caseId) async {
    value = AccidentScenarioAnalysis(
      caseId: caseId,
      engineVersion: AccidentScenarioService.engineVersion,
      inputFingerprint: 'a' * 64,
      state: ScenarioAnalysisState.insufficientEvidence,
      hypotheses: const [],
      generatedAt: DateTime.utc(2026),
    );
    return value!;
  }

  @override
  Future<void> addObservation({
    required String caseId,
    required EvidenceImage evidence,
    required ScenarioObservationKind kind,
    required String subjectLabel,
    required String note,
  }) => throw UnimplementedError();
  @override
  Future<void> deleteObservation(String id) => throw UnimplementedError();
}

class _EvidenceRepository implements EvidenceRepository {
  @override
  Future<List<EvidenceImage>> getForCase(String caseId) async => const [];
  @override
  Future<EvidenceImage?> getById(String id) async => null;
  @override
  Future<EvidenceImage> add(EvidenceImage evidence) =>
      throw UnimplementedError();
  @override
  Future<bool> delete(String id) => throw UnimplementedError();
  @override
  Future<EvidenceImage?> findDuplicate({
    required String caseId,
    required String sha256,
  }) => throw UnimplementedError();
}
