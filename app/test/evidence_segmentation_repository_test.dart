import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/database/iris_database.dart';
import 'package:iris/features/cases/data/sqlite_case_repository.dart';
import 'package:iris/features/evidence/data/sqlite_evidence_repository.dart';
import 'package:iris/features/evidence/domain/evidence_image.dart';
import 'package:iris/features/evidence/domain/image_coordinate_contract.dart';
import 'package:iris/features/segmentation/data/sqlite_evidence_segmentation_repository.dart';
import 'package:iris/features/segmentation/domain/evidence_segmentation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'segmentation analysis and masks persist and reload losslessly',
    () async {
      final directory = await Directory.systemTemp.createTemp('iris_seg_repo_');
      final database = IrisDatabase(
        factory: databaseFactoryFfi,
        databasePath: path.join(directory.path, 'iris.db'),
      );
      addTearDown(() async {
        await database.close();
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final incidentCase = await SqliteCaseRepository(
        database,
      ).createCase(title: 'Segmentation persistence');
      final evidence = EvidenceImage(
        id: 'evidence',
        caseId: incidentCase.id,
        storedRelativePath: 'cases/${incidentCase.id}/evidence/evidence.jpg',
        source: EvidenceSource.gallery,
        importedAt: DateTime.utc(2026),
        fileSizeBytes: 4,
        sha256: 'a' * 64,
      );
      await SqliteEvidenceRepository(database).add(evidence);
      final repository = SqliteEvidenceSegmentationRepository(database);
      final metadata = ImageCoordinateMetadata.create(
        raw: const ImageExtent(1600, 900),
        orientation: IrisExifOrientation.normal,
        canvas: const ImageExtent(320, 320),
        mode: RasterResizeMode.containLetterbox,
        rounding: RasterRounding.floor,
      );
      final analysis = EvidenceSegmentationAnalysis(
        id: 'analysis',
        evidenceId: evidence.id,
        caseId: incidentCase.id,
        sourceEvidenceSha256: evidence.sha256,
        detectionAnalysisId: 'detection',
        detectorSha256: 'b' * 64,
        detectorContractVersion: 'detector-v1',
        modelId: EvidenceSegmentationModel.id,
        modelSourceCommit: EvidenceSegmentationModel.sourceCommit,
        modelCheckpointSha256: EvidenceSegmentationModel.checkpointSha256,
        encoderSha256: EvidenceSegmentationModel.encoderSha256,
        decoderSha256: EvidenceSegmentationModel.decoderSha256,
        coordinateMetadata: metadata,
        analyzedAt: DateTime.utc(2026, 10, 15),
        overlayFileRelativePath: 'derived/overlay.png',
        overlaySha256: 'c' * 64,
        encoderMs: 2100,
        decoderMs: 220,
        totalMs: 7600,
        sampledPeakPssKb: 900000,
        baselinePssKb: 180000,
        masks: <EvidenceSegmentationMask>[
          EvidenceSegmentationMask(
            id: 'mask',
            detectionIndex: 2,
            classId: 3,
            className: 'motorcycle',
            detectionScore: 0.91,
            promptLeft: 10,
            promptTop: 20,
            promptRight: 500,
            promptBottom: 700,
            maskFileRelativePath: 'derived/mask.png',
            maskSha256: 'd' * 64,
            maskPixelCount: 1234,
            predictedQuality: 0.88,
          ),
        ],
      );

      await repository.save(analysis);
      final reloaded = await repository.get(evidence.id);

      expect(reloaded, isNotNull);
      expect(reloaded!.modelCheckpointSha256, analysis.modelCheckpointSha256);
      expect(reloaded.coordinateMetadata.toJson(), metadata.toJson());
      expect(reloaded.sampledPeakPssKb, 900000);
      expect(reloaded.masks.single.detectionIndex, 2);
      expect(reloaded.masks.single.maskSha256, 'd' * 64);
    },
  );
}
