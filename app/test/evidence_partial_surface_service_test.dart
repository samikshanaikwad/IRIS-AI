import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/depth/application/evidence_depth_service.dart';
import 'package:iris/features/depth/domain/depth_visualization.dart';
import 'package:iris/features/depth/domain/evidence_depth.dart';
import 'package:iris/features/evidence/data/evidence_storage.dart';
import 'package:iris/features/evidence/domain/evidence_image.dart';
import 'package:iris/features/evidence/domain/image_coordinate_contract.dart';
import 'package:iris/features/partial_surface/application/evidence_partial_surface_service.dart';
import 'package:iris/features/partial_surface/data/evidence_partial_surface_storage.dart';
import 'package:iris/features/partial_surface/domain/evidence_partial_surface.dart';
import 'package:iris/features/partial_surface/domain/evidence_partial_surface_repository.dart';
import 'package:iris/features/segmentation/application/evidence_segmentation_service.dart';
import 'package:iris/features/segmentation/domain/evidence_segmentation.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory directory;
  late EvidenceStorage evidenceStorage;
  late EvidenceImage evidence;
  late _Repository repository;
  late _Segmentation segmentation;
  late _Depth depth;
  late _Runtime runtime;

  final metadata = ImageCoordinateMetadata.create(
    raw: const ImageExtent(160, 90),
    orientation: IrisExifOrientation.normal,
    canvas: const ImageExtent(32, 32),
    mode: RasterResizeMode.containLetterbox,
    rounding: RasterRounding.floor,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('iris_partial_surface_');
    evidenceStorage = EvidenceStorage(rootProvider: () async => directory);
    const bytes = <int>[1, 2, 3, 4, 5];
    const sourceRelative = 'cases/case/evidence/evidence.jpg';
    final source = File(await evidenceStorage.absolutePath(sourceRelative));
    await source.parent.create(recursive: true);
    await source.writeAsBytes(bytes, flush: true);
    evidence = EvidenceImage(
      id: 'evidence',
      caseId: 'case',
      storedRelativePath: sourceRelative,
      source: EvidenceSource.gallery,
      importedAt: DateTime.utc(2026),
      fileSizeBytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      widthPx: 160,
      heightPx: 90,
    );
    final depthFile = File(await evidenceStorage.absolutePath('depth.f32'));
    await depthFile.writeAsBytes(Uint8List(32 * 32 * 4), flush: true);
    final mask = File(await evidenceStorage.absolutePath('mask.png'));
    await mask.writeAsBytes(const <int>[1], flush: true);
    repository = _Repository();
    segmentation = _Segmentation(_segmentation(evidence, metadata));
    depth = _Depth(_depth(evidence, metadata));
    runtime = _Runtime(directory);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  EvidencePartialSurfaceService service() => EvidencePartialSurfaceService(
    repository: repository,
    storage: EvidencePartialSurfaceStorage(evidenceStorage),
    evidenceStorage: evidenceStorage,
    segmentation: segmentation,
    depth: depth,
    runtime: runtime,
    queue: EvidencePartialSurfaceQueue(),
  );

  test(
    'persists current visible-only mesh with source, mask and depth provenance',
    () async {
      final partial = service();
      final analysis = await partial.generate(evidence);

      expect(analysis.parts, hasLength(1));
      expect(analysis.parts.single.className, 'motorcycle');
      expect(analysis.sourceEvidenceSha256, evidence.sha256);
      expect(
        analysis.depthFileSha256,
        await _hashFile(File(await evidenceStorage.absolutePath('depth.f32'))),
      );
      expect(runtime.calls, 1);

      final loaded = await partial.load(evidence);
      expect(loaded.state, EvidencePartialSurfaceState.current);
      final mesh = await partial.read(loaded.analysis!.parts.single);
      expect(mesh.vertices, hasLength(3));
      expect(mesh.triangles, hasLength(1));
      expect(mesh.vertices.first.argb, 0xffe46f26);
      expect(
        mesh.vertices.every((vertex) => vertex.u >= 0 && vertex.u <= 1),
        isTrue,
      );
    },
  );

  test('changed mask provenance marks a saved visible surface stale', () async {
    final partial = service();
    await partial.generate(evidence);
    segmentation.analysis = _segmentation(
      evidence,
      metadata,
      maskSha: 'c' * 64,
    );

    expect(
      (await partial.load(evidence)).state,
      EvidencePartialSurfaceState.stale,
    );
  });

  test(
    'mismatched image orientation never invokes native surface generation',
    () async {
      depth.analysis = _depth(
        evidence,
        ImageCoordinateMetadata.create(
          raw: const ImageExtent(160, 90),
          orientation: IrisExifOrientation.rotate90Clockwise,
          canvas: const ImageExtent(32, 32),
          mode: RasterResizeMode.containLetterbox,
          rounding: RasterRounding.floor,
        ),
      );

      await expectLater(
        service().generate(evidence),
        throwsA(isA<EvidencePartialSurfaceInsufficient>()),
      );
      expect(runtime.calls, 0);
      expect(repository.value, isNull);
    },
  );

  test(
    'invalid native artifact hash never creates a valid surface record',
    () async {
      runtime.wrongHash = true;
      await expectLater(service().generate(evidence), throwsStateError);
      expect(repository.value, isNull);
    },
  );

  test(
    'invalid mesh triangle never becomes a valid persisted surface',
    () async {
      runtime.invalidTriangle = true;
      await expectLater(service().generate(evidence), throwsFormatException);
      expect(repository.value, isNull);
    },
  );

  test(
    'missing current depth fails closed without a synthetic surface',
    () async {
      depth.state = DepthState.notAnalyzed;
      await expectLater(
        service().generate(evidence),
        throwsA(isA<EvidencePartialSurfaceInsufficient>()),
      );
      expect(runtime.calls, 0);
    },
  );
}

EvidenceSegmentationAnalysis _segmentation(
  EvidenceImage evidence,
  ImageCoordinateMetadata metadata, {
  String? maskSha,
}) => EvidenceSegmentationAnalysis(
  id: 'segmentation',
  evidenceId: evidence.id,
  caseId: evidence.caseId,
  sourceEvidenceSha256: evidence.sha256,
  detectionAnalysisId: 'task007',
  detectorSha256: 'd' * 64,
  detectorContractVersion: 'task007-v1',
  modelId: EvidenceSegmentationModel.id,
  modelSourceCommit: EvidenceSegmentationModel.sourceCommit,
  modelCheckpointSha256: EvidenceSegmentationModel.checkpointSha256,
  encoderSha256: EvidenceSegmentationModel.encoderSha256,
  decoderSha256: EvidenceSegmentationModel.decoderSha256,
  coordinateMetadata: metadata,
  analyzedAt: DateTime.utc(2026),
  overlayFileRelativePath: 'overlay.png',
  overlaySha256: 'e' * 64,
  masks: <EvidenceSegmentationMask>[
    EvidenceSegmentationMask(
      id: 'mask',
      detectionIndex: 0,
      classId: 3,
      className: 'motorcycle',
      detectionScore: .9,
      promptLeft: .2,
      promptTop: .2,
      promptRight: .8,
      promptBottom: .8,
      maskFileRelativePath: 'mask.png',
      maskSha256: maskSha ?? 'b' * 64,
      maskPixelCount: 10,
    ),
  ],
);

EvidenceDepthAnalysis _depth(
  EvidenceImage evidence,
  ImageCoordinateMetadata metadata,
) => EvidenceDepthAnalysis(
  evidenceId: evidence.id,
  evidenceSha256: evidence.sha256,
  artifactSha256: 'a' * 64,
  analyzedAt: DateTime.utc(2026),
  width: metadata.oriented.width,
  height: metadata.oriented.height,
  depthWidth: 32,
  depthHeight: 32,
  depthPath: 'depth.f32',
  min: 0,
  max: 1,
  mean: .5,
  coordinateMetadata: metadata,
);

class _Repository implements EvidencePartialSurfaceRepository {
  EvidencePartialSurfaceAnalysis? value;

  @override
  Future<EvidencePartialSurfaceAnalysis?> get(String evidenceId) async => value;

  @override
  Future<void> save(EvidencePartialSurfaceAnalysis analysis) async {
    value = analysis;
  }
}

class _Segmentation implements EvidenceSegmentationOperations {
  _Segmentation(this.analysis);
  EvidenceSegmentationAnalysis analysis;

  @override
  bool get executionEnabled => true;

  @override
  Future<EvidenceSegmentationAnalysis> analyze(
    EvidenceImage evidence, {
    EvidenceSegmentationCancellation? cancellation,
    void Function()? onStarted,
  }) => throw UnimplementedError();

  @override
  Future<EvidenceSegmentationSnapshot> load(EvidenceImage evidence) async =>
      EvidenceSegmentationSnapshot(
        EvidenceSegmentationState.current,
        analysis: analysis,
      );

  @override
  Future<String> overlayAbsolutePath(EvidenceSegmentationAnalysis analysis) =>
      throw UnimplementedError();
}

class _Depth implements EvidenceDepthOperations {
  _Depth(this.analysis);
  EvidenceDepthAnalysis analysis;
  DepthState state = DepthState.analyzed;

  @override
  Future<EvidenceDepthAnalysis> analyze(EvidenceImage evidence) =>
      throw UnimplementedError();

  @override
  Future<EvidenceDepthSnapshot> load(EvidenceImage evidence) async =>
      EvidenceDepthSnapshot(
        state,
        analysis: state == DepthState.analyzed ? analysis : null,
      );

  @override
  Future<EvidenceDepthVisualization> loadVisualization(
    EvidenceDepthAnalysis analysis,
  ) => throw UnimplementedError();
}

class _Runtime implements EvidencePartialSurfaceRuntime {
  _Runtime(this.directory);
  final Directory directory;
  int calls = 0;
  bool wrongHash = false;
  bool invalidTriangle = false;

  @override
  Future<Map<String, Object?>> generate({
    required String sourceAbsolutePath,
    required String depthAbsolutePath,
    required String outputId,
    required ImageCoordinateMetadata depthMetadata,
    required List<Map<String, Object>> masks,
  }) async {
    calls++;
    final output = File(path.join(directory.path, '$outputId.ips'));
    await output.writeAsBytes(
      _meshBytes(invalidTriangle: invalidTriangle),
      flush: true,
    );
    final hash = await _hashFile(output);
    return <String, Object?>{
      'status': 'PARTIAL_SURFACES_GENERATED_ON_DEVICE',
      'processingVersion': EvidencePartialSurfaceProcessing.version,
      'coordinateContractVersion': depthMetadata.contractVersion,
      'surfaceResults': <Object?>[
        <String, Object?>{
          'status': 'SURFACE_READY',
          'maskId': 'mask',
          'meshPath': output.path,
          'meshSha256': wrongHash ? '0' * 64 : hash,
          'vertexCount': 3,
          'triangleCount': 1,
        },
      ],
      'totalMs': 9.0,
      'baselinePssKb': 1,
      'sampledPeakPssKb': 2,
    };
  }
}

Uint8List _meshBytes({bool invalidTriangle = false}) {
  final bytes = Uint8List(16 + 3 * 32 + 12);
  final data = ByteData.sublistView(bytes);
  data
    ..setUint32(0, 0x49505331, Endian.little)
    ..setUint32(4, 1, Endian.little)
    ..setUint32(8, 3, Endian.little)
    ..setUint32(12, 1, Endian.little);
  const positions = <List<double>>[
    <double>[0, 0, 1, .1, .1],
    <double>[1, 0, 1, .9, .1],
    <double>[0, 1, 1, .1, .9],
  ];
  for (var i = 0; i < positions.length; i++) {
    final offset = 16 + i * 32;
    final vertex = positions[i];
    data
      ..setFloat32(offset, vertex[0], Endian.little)
      ..setFloat32(offset + 4, vertex[1], Endian.little)
      ..setFloat32(offset + 8, vertex[2], Endian.little)
      ..setFloat32(offset + 12, vertex[3], Endian.little)
      ..setFloat32(offset + 16, vertex[4], Endian.little)
      ..setUint32(offset + 20, 0xffe46f26, Endian.little);
  }
  final triangle = 16 + 3 * 32;
  data
    ..setUint32(triangle, 0, Endian.little)
    ..setUint32(triangle + 4, 1, Endian.little)
    ..setUint32(triangle + 8, invalidTriangle ? 9 : 2, Endian.little);
  return bytes;
}

Future<String> _hashFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();
