import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../evidence/domain/evidence_image.dart';
import '../domain/evidence_quality_assessment.dart';
import '../domain/evidence_quality_thresholds.dart';

typedef EvidenceQualityClock = DateTime Function();

abstract interface class EvidenceQualityAnalyzer {
  Future<EvidenceQualityAssessment> analyze({
    required EvidenceImage evidence,
    required String absolutePath,
  });
}

class FlutterImageQualityAnalyzer implements EvidenceQualityAnalyzer {
  FlutterImageQualityAnalyzer({EvidenceQualityClock? clock})
    : _clock = clock ?? DateTime.now;

  static const String algorithmVersion = 'iris-image-quality-v1';

  final EvidenceQualityClock _clock;

  @override
  Future<EvidenceQualityAssessment> analyze({
    required EvidenceImage evidence,
    required String absolutePath,
  }) async {
    final DateTime assessedAt = _clock().toUtc();
    final File file = File(absolutePath);

    bool exists;
    try {
      exists = await file.exists();
    } on Object {
      return _unreadable(evidence: evidence, assessedAt: assessedAt);
    }
    if (!exists) {
      return _missing(evidence: evidence, assessedAt: assessedAt);
    }

    int? fileSizeBytes;
    String? assessedSha256;
    try {
      fileSizeBytes = await file.length();
      assessedSha256 = (await sha256.bind(file.openRead()).first).toString();
    } on Object catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'IRIS quality assessment could not read evidence '
          '${evidence.id} (${error.runtimeType}).',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      return _unreadable(
        evidence: evidence,
        assessedAt: assessedAt,
        fileSizeBytes: fileSizeBytes,
      );
    }

    final EvidenceIntegrityState integrity = assessedSha256 == evidence.sha256
        ? EvidenceIntegrityState.verified
        : EvidenceIntegrityState.mismatch;
    if (integrity == EvidenceIntegrityState.mismatch && kDebugMode) {
      debugPrint('IRIS evidence integrity mismatch for ${evidence.id}.');
    }

    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? decodedImage;
    try {
      buffer = await ui.ImmutableBuffer.fromFilePath(absolutePath);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final int originalWidth = descriptor.width;
      final int originalHeight = descriptor.height;
      if (originalWidth <= 0 || originalHeight <= 0) {
        throw const FormatException('Decoded image dimensions are invalid.');
      }

      if (originalWidth >= originalHeight &&
          originalWidth > EvidenceQualityThresholds.maxAnalysisDimensionPx) {
        codec = await descriptor.instantiateCodec(
          targetWidth: EvidenceQualityThresholds.maxAnalysisDimensionPx,
        );
      } else if (originalHeight > originalWidth &&
          originalHeight > EvidenceQualityThresholds.maxAnalysisDimensionPx) {
        codec = await descriptor.instantiateCodec(
          targetHeight: EvidenceQualityThresholds.maxAnalysisDimensionPx,
        );
      } else {
        codec = await descriptor.instantiateCodec();
      }

      final ui.FrameInfo frame = await codec.getNextFrame();
      decodedImage = frame.image;
      final ByteData? rgba = await decodedImage.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (rgba == null) {
        throw StateError('Decoded image pixels are unavailable.');
      }

      final Uint8List pixels = rgba.buffer.asUint8List(
        rgba.offsetInBytes,
        rgba.lengthInBytes,
      );
      final _PixelMetrics metrics;
      try {
        metrics = await compute(
          _calculatePixelMetrics,
          _PixelAnalysisInput(
            rgba: pixels,
            width: decodedImage.width,
            height: decodedImage.height,
          ),
        );
      } on Object catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint(
            'IRIS quality metric computation failed for ${evidence.id} '
            '(${error.runtimeType}).',
          );
          debugPrintStack(stackTrace: stackTrace);
        }
        return EvidenceQualityAssessment(
          evidenceId: evidence.id,
          assessedAt: assessedAt,
          algorithmVersion: algorithmVersion,
          expectedSha256: evidence.sha256,
          assessedSha256: assessedSha256,
          fileState: EvidenceFileState.available,
          decodeState: EvidenceDecodeState.decoded,
          integrityState: integrity,
          readiness: EvidenceReadiness.notUsable,
          fileSizeBytes: fileSizeBytes,
          originalWidth: originalWidth,
          originalHeight: originalHeight,
          analysisWidth: decodedImage.width,
          analysisHeight: decodedImage.height,
          orientation: _orientation(originalWidth, originalHeight),
          findings: <EvidenceQualityFinding>[
            if (integrity == EvidenceIntegrityState.mismatch)
              _integrityMismatchFinding(),
            const EvidenceQualityFinding(
              code: EvidenceQualityFindingCode.assessmentFailed,
              severity: EvidenceQualitySeverity.critical,
              metric: EvidenceQualityMetric.processing,
              explanation:
                  'Technical image measurements could not be calculated.',
            ),
          ],
        );
      }
      final List<EvidenceQualityFinding> findings = _qualityFindings(
        width: originalWidth,
        height: originalHeight,
        integrity: integrity,
        metrics: metrics,
      );
      final bool hasWarning = findings.any(
        (EvidenceQualityFinding finding) =>
            finding.severity == EvidenceQualitySeverity.warning,
      );

      return EvidenceQualityAssessment(
        evidenceId: evidence.id,
        assessedAt: assessedAt,
        algorithmVersion: algorithmVersion,
        expectedSha256: evidence.sha256,
        assessedSha256: assessedSha256,
        fileState: EvidenceFileState.available,
        decodeState: EvidenceDecodeState.decoded,
        integrityState: integrity,
        readiness: integrity == EvidenceIntegrityState.mismatch
            ? EvidenceReadiness.notUsable
            : hasWarning
            ? EvidenceReadiness.usableWithLimitations
            : EvidenceReadiness.ready,
        fileSizeBytes: fileSizeBytes,
        originalWidth: originalWidth,
        originalHeight: originalHeight,
        analysisWidth: decodedImage.width,
        analysisHeight: decodedImage.height,
        orientation: _orientation(originalWidth, originalHeight),
        sharpnessValue: metrics.sharpnessVariance,
        meanLuminance: metrics.meanLuminance,
        darkClippedFraction: metrics.darkClippedFraction,
        brightClippedFraction: metrics.brightClippedFraction,
        findings: List<EvidenceQualityFinding>.unmodifiable(findings),
      );
    } on Object catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'IRIS quality assessment could not decode evidence '
          '${evidence.id} (${error.runtimeType}).',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      final List<EvidenceQualityFinding> findings = <EvidenceQualityFinding>[
        if (integrity == EvidenceIntegrityState.mismatch)
          _integrityMismatchFinding(),
        const EvidenceQualityFinding(
          code: EvidenceQualityFindingCode.decodeFailed,
          severity: EvidenceQualitySeverity.critical,
          metric: EvidenceQualityMetric.decoding,
          explanation:
              'The stored bytes could not be decoded as a supported image.',
        ),
      ];
      return EvidenceQualityAssessment(
        evidenceId: evidence.id,
        assessedAt: assessedAt,
        algorithmVersion: algorithmVersion,
        expectedSha256: evidence.sha256,
        assessedSha256: assessedSha256,
        fileState: EvidenceFileState.available,
        decodeState: EvidenceDecodeState.failed,
        integrityState: integrity,
        readiness: EvidenceReadiness.notUsable,
        fileSizeBytes: fileSizeBytes,
        findings: findings,
      );
    } finally {
      decodedImage?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  EvidenceQualityAssessment _missing({
    required EvidenceImage evidence,
    required DateTime assessedAt,
  }) => EvidenceQualityAssessment(
    evidenceId: evidence.id,
    assessedAt: assessedAt,
    algorithmVersion: algorithmVersion,
    expectedSha256: evidence.sha256,
    fileState: EvidenceFileState.missing,
    decodeState: EvidenceDecodeState.notAttempted,
    integrityState: EvidenceIntegrityState.unavailable,
    readiness: EvidenceReadiness.notUsable,
    findings: const <EvidenceQualityFinding>[
      EvidenceQualityFinding(
        code: EvidenceQualityFindingCode.fileMissing,
        severity: EvidenceQualitySeverity.critical,
        metric: EvidenceQualityMetric.fileAvailability,
        explanation: 'The managed evidence file is missing from local storage.',
      ),
    ],
  );

  EvidenceQualityAssessment _unreadable({
    required EvidenceImage evidence,
    required DateTime assessedAt,
    int? fileSizeBytes,
  }) => EvidenceQualityAssessment(
    evidenceId: evidence.id,
    assessedAt: assessedAt,
    algorithmVersion: algorithmVersion,
    expectedSha256: evidence.sha256,
    fileState: EvidenceFileState.unreadable,
    decodeState: EvidenceDecodeState.notAttempted,
    integrityState: EvidenceIntegrityState.unavailable,
    readiness: EvidenceReadiness.notUsable,
    fileSizeBytes: fileSizeBytes,
    findings: const <EvidenceQualityFinding>[
      EvidenceQualityFinding(
        code: EvidenceQualityFindingCode.unreadable,
        severity: EvidenceQualitySeverity.critical,
        metric: EvidenceQualityMetric.readability,
        explanation: 'The managed evidence bytes could not be read.',
      ),
    ],
  );

  List<EvidenceQualityFinding> _qualityFindings({
    required int width,
    required int height,
    required EvidenceIntegrityState integrity,
    required _PixelMetrics metrics,
  }) {
    final List<EvidenceQualityFinding> findings = <EvidenceQualityFinding>[];
    if (integrity == EvidenceIntegrityState.mismatch) {
      findings.add(_integrityMismatchFinding());
    }
    final int pixelCount = width * height;
    if (EvidenceQualityThresholds.isLowResolution(
      width: width,
      height: height,
    )) {
      findings.add(
        EvidenceQualityFinding(
          code: EvidenceQualityFindingCode.lowResolution,
          severity: EvidenceQualitySeverity.warning,
          metric: EvidenceQualityMetric.resolution,
          measuredValue: pixelCount.toDouble(),
          threshold: EvidenceQualityThresholds.minimumPixelCount.toDouble(),
          unit: 'pixels',
          explanation:
              'Resolution is below the current IRIS analysis threshold.',
        ),
      );
    }
    if (EvidenceQualityThresholds.isPossiblyBlurred(
      metrics.sharpnessVariance,
    )) {
      findings.add(
        EvidenceQualityFinding(
          code: EvidenceQualityFindingCode.possibleBlur,
          severity: EvidenceQualitySeverity.warning,
          metric: EvidenceQualityMetric.sharpness,
          measuredValue: metrics.sharpnessVariance,
          threshold: EvidenceQualityThresholds.minimumSharpnessVariance,
          unit: 'Laplacian variance',
          explanation:
              'Sharpness is below the current IRIS analysis threshold.',
        ),
      );
    }
    if (EvidenceQualityThresholds.isVeryDark(metrics.meanLuminance)) {
      findings.add(
        EvidenceQualityFinding(
          code: EvidenceQualityFindingCode.veryDark,
          severity: EvidenceQualitySeverity.warning,
          metric: EvidenceQualityMetric.brightness,
          measuredValue: metrics.meanLuminance,
          threshold: EvidenceQualityThresholds.darkMeanLuminanceBelow,
          unit: '0–255 luma',
          explanation:
              'Mean brightness is below the current IRIS analysis threshold.',
        ),
      );
    }
    if (EvidenceQualityThresholds.isVeryBright(metrics.meanLuminance)) {
      findings.add(
        EvidenceQualityFinding(
          code: EvidenceQualityFindingCode.veryBright,
          severity: EvidenceQualitySeverity.warning,
          metric: EvidenceQualityMetric.brightness,
          measuredValue: metrics.meanLuminance,
          threshold: EvidenceQualityThresholds.brightMeanLuminanceAbove,
          unit: '0–255 luma',
          explanation:
              'Mean brightness is above the current IRIS analysis threshold.',
        ),
      );
    }
    if (EvidenceQualityThresholds.hasSignificantClipping(
      metrics.darkClippedFraction,
    )) {
      findings.add(
        EvidenceQualityFinding(
          code: EvidenceQualityFindingCode.darkClipping,
          severity: EvidenceQualitySeverity.warning,
          metric: EvidenceQualityMetric.darkClipping,
          measuredValue: metrics.darkClippedFraction,
          threshold: EvidenceQualityThresholds.maximumClippedFraction,
          unit: 'fraction',
          explanation:
              '${(metrics.darkClippedFraction * 100).toStringAsFixed(1)}% of analyzed pixels are near black.',
        ),
      );
    }
    if (EvidenceQualityThresholds.hasSignificantClipping(
      metrics.brightClippedFraction,
    )) {
      findings.add(
        EvidenceQualityFinding(
          code: EvidenceQualityFindingCode.brightClipping,
          severity: EvidenceQualitySeverity.warning,
          metric: EvidenceQualityMetric.brightClipping,
          measuredValue: metrics.brightClippedFraction,
          threshold: EvidenceQualityThresholds.maximumClippedFraction,
          unit: 'fraction',
          explanation:
              '${(metrics.brightClippedFraction * 100).toStringAsFixed(1)}% of analyzed pixels are near white.',
        ),
      );
    }
    return findings;
  }

  EvidenceQualityFinding
  _integrityMismatchFinding() => const EvidenceQualityFinding(
    code: EvidenceQualityFindingCode.integrityMismatch,
    severity: EvidenceQualitySeverity.critical,
    metric: EvidenceQualityMetric.integrity,
    explanation:
        'The stored evidence bytes no longer match the SHA-256 recorded at import.',
  );

  EvidenceOrientation _orientation(int width, int height) {
    if (width == height) {
      return EvidenceOrientation.square;
    }
    return width > height
        ? EvidenceOrientation.landscape
        : EvidenceOrientation.portrait;
  }
}

class _PixelAnalysisInput {
  const _PixelAnalysisInput({
    required this.rgba,
    required this.width,
    required this.height,
  });

  final Uint8List rgba;
  final int width;
  final int height;
}

class _PixelMetrics {
  const _PixelMetrics({
    required this.sharpnessVariance,
    required this.meanLuminance,
    required this.darkClippedFraction,
    required this.brightClippedFraction,
  });

  final double sharpnessVariance;
  final double meanLuminance;
  final double darkClippedFraction;
  final double brightClippedFraction;
}

_PixelMetrics _calculatePixelMetrics(_PixelAnalysisInput input) {
  final int pixelCount = input.width * input.height;
  if (pixelCount <= 0 || input.rgba.length < pixelCount * 4) {
    throw const FormatException('Decoded pixel buffer is incomplete.');
  }

  final Float32List luminance = Float32List(pixelCount);
  double luminanceSum = 0;
  int darkClipped = 0;
  int brightClipped = 0;
  for (int pixel = 0, offset = 0; pixel < pixelCount; pixel++, offset += 4) {
    final double value =
        (0.2126 * input.rgba[offset]) +
        (0.7152 * input.rgba[offset + 1]) +
        (0.0722 * input.rgba[offset + 2]);
    luminance[pixel] = value;
    luminanceSum += value;
    if (value <= EvidenceQualityThresholds.darkClippingBoundary) {
      darkClipped++;
    }
    if (value >= EvidenceQualityThresholds.brightClippingBoundary) {
      brightClipped++;
    }
  }

  double laplacianSum = 0;
  double laplacianSquaredSum = 0;
  int laplacianCount = 0;
  for (int y = 1; y < input.height - 1; y++) {
    final int row = y * input.width;
    for (int x = 1; x < input.width - 1; x++) {
      final int index = row + x;
      final double laplacian =
          (4 * luminance[index]) -
          luminance[index - 1] -
          luminance[index + 1] -
          luminance[index - input.width] -
          luminance[index + input.width];
      laplacianSum += laplacian;
      laplacianSquaredSum += laplacian * laplacian;
      laplacianCount++;
    }
  }
  final double sharpnessVariance;
  if (laplacianCount == 0) {
    sharpnessVariance = 0;
  } else {
    final double mean = laplacianSum / laplacianCount;
    sharpnessVariance = (laplacianSquaredSum / laplacianCount) - (mean * mean);
  }

  return _PixelMetrics(
    sharpnessVariance: sharpnessVariance < 0 ? 0 : sharpnessVariance,
    meanLuminance: luminanceSum / pixelCount,
    darkClippedFraction: darkClipped / pixelCount,
    brightClippedFraction: brightClipped / pixelCount,
  );
}
