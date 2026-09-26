import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:iris/features/evidence/domain/evidence_image.dart';
import 'package:iris/features/evidence_quality/domain/evidence_quality_assessment.dart';
import 'package:iris/features/evidence_quality/domain/evidence_quality_thresholds.dart';
import 'package:iris/features/evidence_quality/processing/image_quality_analyzer.dart';

import 'support/quality_image_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late FlutterImageQualityAnalyzer analyzer;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('iris_quality_test_');
    analyzer = FlutterImageQualityAnalyzer(
      clock: () => DateTime.utc(2026, 9, 27, 12),
    );
  });

  tearDown(() async {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  test(
    'valid PNG uses original dimensions and bounded analysis pixels',
    () async {
      final File file = await writeTestPng(
        directory: directory,
        name: 'large.png',
        width: 1600,
        height: 800,
        pattern: TestImagePattern.checker,
        first: const TestRgb(80, 80, 80),
        second: const TestRgb(180, 180, 180),
        checkerSize: 64,
      );
      final EvidenceImage evidence = await _evidence(file);

      final EvidenceQualityAssessment result = await analyzer.analyze(
        evidence: evidence,
        absolutePath: file.path,
      );

      expect(result.integrityState, EvidenceIntegrityState.verified);
      expect(result.decodeState, EvidenceDecodeState.decoded);
      expect(result.originalWidth, 1600);
      expect(result.originalHeight, 800);
      expect(result.analysisWidth, 1024);
      expect(result.analysisHeight, 512);
      expect(result.orientation, EvidenceOrientation.landscape);
      expect(result.fileSizeBytes, await file.length());
      expect(result.algorithmVersion, 'iris-image-quality-v1');
    },
  );

  test('valid JPEG decodes and reports its actual dimensions', () async {
    final File file = await writeTestJpeg(directory, 'fixture.jpg');
    final EvidenceQualityAssessment result = await analyzer.analyze(
      evidence: await _evidence(file, mimeType: 'image/jpeg'),
      absolutePath: file.path,
    );

    expect(result.decodeState, EvidenceDecodeState.decoded);
    expect(result.originalWidth, 4);
    expect(result.originalHeight, 3);
    expect(result.integrityState, EvidenceIntegrityState.verified);
  });

  test('missing file is unavailable and not usable', () async {
    final File file = File(path.join(directory.path, 'missing.png'));
    final EvidenceQualityAssessment result = await analyzer.analyze(
      evidence: _evidenceWithHash(file, '0' * 64),
      absolutePath: file.path,
    );

    expect(result.fileState, EvidenceFileState.missing);
    expect(result.integrityState, EvidenceIntegrityState.unavailable);
    expect(result.readiness, EvidenceReadiness.notUsable);
    expect(result.findings.single.code, EvidenceQualityFindingCode.fileMissing);
  });

  test('corrupt and zero-byte files fail decoding truthfully', () async {
    final File corrupt = await File(
      path.join(directory.path, 'corrupt.png'),
    ).writeAsBytes(<int>[1, 2, 3, 4], flush: true);
    final File empty = await File(
      path.join(directory.path, 'empty.png'),
    ).writeAsBytes(const <int>[], flush: true);

    for (final File file in <File>[corrupt, empty]) {
      final EvidenceQualityAssessment result = await analyzer.analyze(
        evidence: await _evidence(file),
        absolutePath: file.path,
      );
      expect(result.fileState, EvidenceFileState.available);
      expect(result.decodeState, EvidenceDecodeState.failed);
      expect(result.integrityState, EvidenceIntegrityState.verified);
      expect(result.readiness, EvidenceReadiness.notUsable);
      expect(
        result.findings.map((EvidenceQualityFinding item) => item.code),
        contains(EvidenceQualityFindingCode.decodeFailed),
      );
    }
  });

  test('changed bytes report mismatch without changing import hash', () async {
    final File file = await writeTestPng(
      directory: directory,
      name: 'changed.png',
      width: 64,
      height: 64,
      pattern: TestImagePattern.solid,
      first: const TestRgb(120, 120, 120),
    );
    final String importHash = 'a' * 64;
    final EvidenceImage evidence = _evidenceWithHash(file, importHash);

    final EvidenceQualityAssessment result = await analyzer.analyze(
      evidence: evidence,
      absolutePath: file.path,
    );

    expect(result.integrityState, EvidenceIntegrityState.mismatch);
    expect(result.readiness, EvidenceReadiness.notUsable);
    expect(result.expectedSha256, importHash);
    expect(evidence.sha256, importHash);
    expect(result.assessedSha256, isNot(importHash));
    expect(
      result.findings.map((EvidenceQualityFinding item) => item.code),
      contains(EvidenceQualityFindingCode.integrityMismatch),
    );
  });

  test('resolution thresholds include the exact configured boundary', () {
    expect(
      EvidenceQualityThresholds.isLowResolution(width: 1279, height: 720),
      isTrue,
    );
    expect(
      EvidenceQualityThresholds.isLowResolution(width: 1280, height: 720),
      isFalse,
    );
    expect(
      EvidenceQualityThresholds.isLowResolution(width: 1920, height: 1080),
      isFalse,
    );
  });

  test(
    'blurred equivalent has meaningfully lower Laplacian variance',
    () async {
      final File sharp = await writeTestPng(
        directory: directory,
        name: 'sharp.png',
        width: 320,
        height: 240,
        pattern: TestImagePattern.checker,
        first: const TestRgb(40, 40, 40),
        second: const TestRgb(220, 220, 220),
        checkerSize: 24,
      );
      final File blurred = await writeTestPng(
        directory: directory,
        name: 'blurred.png',
        width: 320,
        height: 240,
        pattern: TestImagePattern.checker,
        first: const TestRgb(40, 40, 40),
        second: const TestRgb(220, 220, 220),
        checkerSize: 24,
        blurRadius: 8,
      );

      final EvidenceQualityAssessment sharpResult = await analyzer.analyze(
        evidence: await _evidence(sharp, id: 'sharp'),
        absolutePath: sharp.path,
      );
      final EvidenceQualityAssessment blurredResult = await analyzer.analyze(
        evidence: await _evidence(blurred, id: 'blurred'),
        absolutePath: blurred.path,
      );

      expect(sharpResult.sharpnessValue, isNotNull);
      expect(blurredResult.sharpnessValue, isNotNull);
      expect(
        blurredResult.sharpnessValue!,
        lessThan(sharpResult.sharpnessValue! * 0.35),
      );
    },
  );

  test('known RGB input follows documented BT.709 luminance', () async {
    final File file = await writeTestPng(
      directory: directory,
      name: 'luma.png',
      width: 16,
      height: 16,
      pattern: TestImagePattern.solid,
      first: const TestRgb(100, 150, 200),
    );
    final EvidenceQualityAssessment result = await analyzer.analyze(
      evidence: await _evidence(file),
      absolutePath: file.path,
    );

    const double expected = (0.2126 * 100) + (0.7152 * 150) + (0.0722 * 200);
    expect(result.meanLuminance, closeTo(expected, 0.6));
  });

  test(
    'black, white, and mixed fixtures produce real clipping fractions',
    () async {
      final File black = await writeTestPng(
        directory: directory,
        name: 'black.png',
        width: 20,
        height: 20,
        pattern: TestImagePattern.solid,
        first: const TestRgb(0, 0, 0),
      );
      final File white = await writeTestPng(
        directory: directory,
        name: 'white.png',
        width: 20,
        height: 20,
        pattern: TestImagePattern.solid,
        first: const TestRgb(255, 255, 255),
      );
      final File mixed = await writeTestPng(
        directory: directory,
        name: 'mixed.png',
        width: 20,
        height: 20,
        pattern: TestImagePattern.verticalSplit,
        first: const TestRgb(0, 0, 0),
        second: const TestRgb(255, 255, 255),
      );

      final EvidenceQualityAssessment blackResult = await analyzer.analyze(
        evidence: await _evidence(black, id: 'black'),
        absolutePath: black.path,
      );
      final EvidenceQualityAssessment whiteResult = await analyzer.analyze(
        evidence: await _evidence(white, id: 'white'),
        absolutePath: white.path,
      );
      final EvidenceQualityAssessment mixedResult = await analyzer.analyze(
        evidence: await _evidence(mixed, id: 'mixed'),
        absolutePath: mixed.path,
      );

      expect(blackResult.darkClippedFraction, 1);
      expect(blackResult.brightClippedFraction, 0);
      expect(whiteResult.darkClippedFraction, 0);
      expect(whiteResult.brightClippedFraction, 1);
      expect(mixedResult.darkClippedFraction, 0.5);
      expect(mixedResult.brightClippedFraction, 0.5);
    },
  );

  test('decoded dimensions classify portrait landscape and square', () async {
    final List<
      ({String id, int width, int height, EvidenceOrientation expected})
    >
    specifications =
        <({String id, int width, int height, EvidenceOrientation expected})>[
          (
            id: 'portrait',
            width: 20,
            height: 40,
            expected: EvidenceOrientation.portrait,
          ),
          (
            id: 'landscape',
            width: 40,
            height: 20,
            expected: EvidenceOrientation.landscape,
          ),
          (
            id: 'square',
            width: 30,
            height: 30,
            expected: EvidenceOrientation.square,
          ),
        ];
    for (final specification in specifications) {
      final File file = await writeTestPng(
        directory: directory,
        name: '${specification.id}.png',
        width: specification.width,
        height: specification.height,
        pattern: TestImagePattern.checker,
        first: const TestRgb(80, 80, 80),
        second: const TestRgb(180, 180, 180),
      );
      final EvidenceQualityAssessment result = await analyzer.analyze(
        evidence: await _evidence(file, id: specification.id),
        absolutePath: file.path,
      );
      expect(result.orientation, specification.expected);
    }
  });

  test('readiness distinguishes clean image, warning, and mismatch', () async {
    final File clean = await writeTestPng(
      directory: directory,
      name: 'clean.png',
      width: 1280,
      height: 720,
      pattern: TestImagePattern.checker,
      first: const TestRgb(80, 80, 80),
      second: const TestRgb(180, 180, 180),
      checkerSize: 48,
    );
    final EvidenceQualityAssessment cleanResult = await analyzer.analyze(
      evidence: await _evidence(clean, id: 'clean'),
      absolutePath: clean.path,
    );
    final File dark = await writeTestPng(
      directory: directory,
      name: 'dark.png',
      width: 1280,
      height: 720,
      pattern: TestImagePattern.solid,
      first: const TestRgb(5, 5, 5),
    );
    final EvidenceQualityAssessment warningResult = await analyzer.analyze(
      evidence: await _evidence(dark, id: 'dark'),
      absolutePath: dark.path,
    );
    final EvidenceQualityAssessment mismatchResult = await analyzer.analyze(
      evidence: _evidenceWithHash(clean, 'f' * 64, id: 'mismatch'),
      absolutePath: clean.path,
    );

    expect(cleanResult.readiness, EvidenceReadiness.ready);
    expect(cleanResult.findings, isEmpty);
    expect(warningResult.readiness, EvidenceReadiness.usableWithLimitations);
    expect(mismatchResult.readiness, EvidenceReadiness.notUsable);
  });

  test('sharpness and clipping threshold boundaries are deterministic', () {
    expect(
      EvidenceQualityThresholds.isPossiblyBlurred(
        EvidenceQualityThresholds.minimumSharpnessVariance,
      ),
      isFalse,
    );
    expect(
      EvidenceQualityThresholds.isPossiblyBlurred(
        EvidenceQualityThresholds.minimumSharpnessVariance - 0.01,
      ),
      isTrue,
    );
    expect(
      EvidenceQualityThresholds.hasSignificantClipping(
        EvidenceQualityThresholds.maximumClippedFraction,
      ),
      isTrue,
    );
    expect(
      EvidenceQualityThresholds.isVeryDark(
        EvidenceQualityThresholds.darkMeanLuminanceBelow,
      ),
      isFalse,
    );
    expect(
      EvidenceQualityThresholds.isVeryDark(
        EvidenceQualityThresholds.darkMeanLuminanceBelow - 0.01,
      ),
      isTrue,
    );
    expect(
      EvidenceQualityThresholds.isVeryBright(
        EvidenceQualityThresholds.brightMeanLuminanceAbove,
      ),
      isFalse,
    );
    expect(
      EvidenceQualityThresholds.isVeryBright(
        EvidenceQualityThresholds.brightMeanLuminanceAbove + 0.01,
      ),
      isTrue,
    );
  });
}

Future<EvidenceImage> _evidence(
  File file, {
  String id = 'evidence-id',
  String mimeType = 'image/png',
}) async {
  final String digest = sha256.convert(await file.readAsBytes()).toString();
  return _evidenceWithHash(file, digest, id: id, mimeType: mimeType);
}

EvidenceImage _evidenceWithHash(
  File file,
  String digest, {
  String id = 'evidence-id',
  String mimeType = 'image/png',
}) => EvidenceImage(
  id: id,
  caseId: 'case-id',
  storedRelativePath: path.basename(file.path),
  source: EvidenceSource.gallery,
  importedAt: DateTime.utc(2026, 9, 27),
  fileSizeBytes: file.existsSync() ? file.lengthSync() : 0,
  sha256: digest,
  mimeType: mimeType,
);
