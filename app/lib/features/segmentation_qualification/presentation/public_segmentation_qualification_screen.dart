import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/iris_spacing.dart';
import '../../../core/widgets/iris_app_bar.dart';
import '../../../core/widgets/iris_button.dart';
import '../../../core/widgets/iris_card.dart';
import '../../../core/widgets/iris_page_body.dart';
import '../../detection/application/evidence_detection_service.dart';
import '../../detection/domain/evidence_detection.dart';
import '../../evidence/domain/image_coordinate_contract.dart';
import '../public_vehicle_evaluation.dart';

class PublicSegmentationQualificationScreen extends StatefulWidget {
  const PublicSegmentationQualificationScreen({super.key});

  @override
  State<PublicSegmentationQualificationScreen> createState() =>
      _PublicSegmentationQualificationScreenState();
}

class _PublicSegmentationQualificationScreenState
    extends State<PublicSegmentationQualificationScreen> {
  static const _detector = MethodChannel('com.iris.detector/v1');
  static const _segmentation = MethodChannel(
    'com.iris.debug/segmentation-qualification',
  );

  final _results = <String, Map<String, Object?>>{};
  bool _busy = false;
  String? _current;

  Future<void> _runAll() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _current = null;
      _results.clear();
    });
    try {
      for (final image in publicVehicleEvaluationImages) {
        if (!mounted) return;
        setState(() => _current = image.id);
        final result = await _runOne(image);
        if (!mounted) return;
        setState(() => _results[image.id] = result);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _current = null;
        });
      }
    }
  }

  Future<Map<String, Object?>> _runOne(
    PublicVehicleEvaluationImage image,
  ) async {
    final startedAt = DateTime.now().toUtc();
    try {
      final prepared = await _segmentation.invokeMapMethod<String, Object?>(
        'preparePublicEvaluationImage',
        <String, Object?>{'assetName': image.assetName, 'sha256': image.sha256},
      );
      if (prepared == null || prepared['sha256'] != image.sha256) {
        throw StateError('Public evaluation asset integrity check failed.');
      }
      final path = prepared['absolutePath'];
      if (path is! String) throw StateError('Prepared image path is missing.');
      final detector = await _detector.invokeMapMethod<Object?, Object?>(
        'run',
        <String, Object?>{'absolutePath': path},
      );
      if (detector == null ||
          detector['detectorSha256'] !=
              EvidenceDetectionService.detectorSha256 ||
          detector['thresholdPolicyVersion'] !=
              EvidenceDetectionService.contractVersion) {
        throw StateError('TASK007 detector contract mismatch.');
      }
      final metadataRaw = detector['coordinateMetadata'];
      final detectionsRaw = detector['detections'];
      if (metadataRaw is! Map || detectionsRaw is! List) {
        throw StateError('TASK007 coordinate output is incomplete.');
      }
      final metadata = ImageCoordinateMetadata.fromJson(
        Map<String, Object?>.from(metadataRaw),
      );
      final detections = detectionsRaw.map(_parseDetection).toList();
      final prompts = publicEvaluationPrompts(
        vehicleClass: image.vehicleClass,
        detections: detections,
        metadata: metadata,
      );
      if (prompts.isEmpty) {
        final result = <String, Object?>{
          'schema_version': 'iris-public-segmentation-device-result-v1',
          'evaluation_image': image.toQualificationJson(),
          'status': 'NO_ELIGIBLE_DETECTOR_BOX',
          'started_at_utc': startedAt.toIso8601String(),
          'completed_at_utc': DateTime.now().toUtc().toIso8601String(),
          'detector_sha256': detector['detectorSha256'],
          'detector_inference_ms': detector['inferenceMs'],
          'detector_detections': _safeDetectionRecords(detections),
          'target_detection_count': 0,
          'segmentation_invoked': false,
        };
        await _writeResult(path, image.id, result);
        return result;
      }
      final segmentation = await _segmentation.invokeMapMethod<String, Object?>(
        'runQualification',
        <String, Object?>{
          'absolutePath': path,
          'coordinateContractVersion': metadata.contractVersion,
          'boxes': prompts
              .map((prompt) => prompt.toChannelValue())
              .toList(growable: false),
          'outputId': image.id,
        },
      );
      if (segmentation == null ||
          segmentation['status'] != 'MASKS_GENERATED_ON_DEVICE') {
        throw StateError('MobileSAM produced no genuine mask result.');
      }
      final result = <String, Object?>{
        'schema_version': 'iris-public-segmentation-device-result-v1',
        'evaluation_image': image.toQualificationJson(),
        'status': 'MASKS_GENERATED_ON_DEVICE',
        'started_at_utc': startedAt.toIso8601String(),
        'completed_at_utc': DateTime.now().toUtc().toIso8601String(),
        'detector_sha256': detector['detectorSha256'],
        'detector_inference_ms': detector['inferenceMs'],
        'detector_detections': _safeDetectionRecords(detections),
        'target_detection_count': prompts.length,
        'segmentation_invoked': true,
        'segmentation': Map<String, Object?>.from(segmentation),
      };
      await _writeResult(path, image.id, result);
      return result;
    } on PlatformException catch (error) {
      return <String, Object?>{
        'schema_version': 'iris-public-segmentation-device-result-v1',
        'evaluation_image': image.toQualificationJson(),
        'status': 'ERROR',
        'error_code': error.code,
        'error_message': error.message ?? 'On-device inference failed.',
        'started_at_utc': startedAt.toIso8601String(),
        'completed_at_utc': DateTime.now().toUtc().toIso8601String(),
      };
    } on Object catch (error) {
      return <String, Object?>{
        'schema_version': 'iris-public-segmentation-device-result-v1',
        'evaluation_image': image.toQualificationJson(),
        'status': 'ERROR',
        'error_message': error.toString(),
        'started_at_utc': startedAt.toIso8601String(),
        'completed_at_utc': DateTime.now().toUtc().toIso8601String(),
      };
    }
  }

  EvidenceDetection _parseDetection(Object? raw) {
    if (raw is! Map) throw StateError('Malformed TASK007 detection.');
    final value = Map<Object?, Object?>.from(raw);
    final classId = (value['classId'] as num).toInt();
    final className = EvidenceDetectionService.allowed[classId];
    final score = (value['score'] as num).toDouble();
    final box = List<num>.from(value['box'] as List);
    if (className == null ||
        box.length != 4 ||
        !score.isFinite ||
        box.any((coordinate) => !coordinate.isFinite)) {
      throw StateError('Malformed TASK007 detection.');
    }
    return EvidenceDetection(
      classId: classId,
      className: className,
      score: score,
      ymin: box[0].toDouble(),
      xmin: box[1].toDouble(),
      ymax: box[2].toDouble(),
      xmax: box[3].toDouble(),
    );
  }

  List<Map<String, Object>> _safeDetectionRecords(
    List<EvidenceDetection> detections,
  ) => detections
      .map(
        (detection) => <String, Object>{
          'class_id': detection.classId,
          'class_name': detection.className,
          'score': detection.score,
          'normalized_box': <double>[
            detection.ymin,
            detection.xmin,
            detection.ymax,
            detection.xmax,
          ],
        },
      )
      .toList(growable: false);

  Future<void> _writeResult(
    String sourcePath,
    String id,
    Map<String, Object?> result,
  ) async {
    final directory = File(sourcePath).parent;
    final file = File(
      '${directory.path}${Platform.pathSeparator}$id-result.json',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(result),
      flush: true,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const IrisAppBar(title: 'Public segmentation qualification'),
    body: IrisPageBody(
      children: <Widget>[
        const IrisCard(
          child: Text(
            'Debug-only qualification. Rights-cleared public images are run through the real TASK007 detector and MobileSAM. Nothing is imported into a case or saved as production analysis.',
          ),
        ),
        const SizedBox(height: IrisSpacing.md),
        IrisPrimaryButton(
          key: const ValueKey<String>('run-public-segmentation-qualification'),
          label: _busy
              ? 'Running ${_current ?? 'evaluation'}…'
              : 'Run all public evaluations',
          icon: Icons.memory_outlined,
          onPressed: _busy ? null : _runAll,
        ),
        const SizedBox(height: IrisSpacing.md),
        for (final image in publicVehicleEvaluationImages) ...<Widget>[
          _resultCard(image),
          const SizedBox(height: IrisSpacing.sm),
        ],
      ],
    ),
  );

  Widget _resultCard(PublicVehicleEvaluationImage image) {
    final result = _results[image.id];
    final segmentation = result?['segmentation'];
    final segmentationMap = segmentation is Map
        ? Map<Object?, Object?>.from(segmentation)
        : null;
    final overlayPath = segmentationMap?['overlayPath'];
    return IrisCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('${image.id} — ${image.vehicleClass}'),
          Text('${image.license} • ${image.author}'),
          Text(image.scenario),
          const SizedBox(height: IrisSpacing.xs),
          Text('Status: ${result?['status'] ?? 'NOT_RUN'}'),
          if (result?['target_detection_count'] != null)
            Text('Real TASK007 prompts: ${result!['target_detection_count']}'),
          if (segmentationMap != null) ...<Widget>[
            Text(
              'Detector ${_number(result?['detector_inference_ms'])} ms • encoder ${_number(segmentationMap['imageEncoderMs'])} ms • total ${_number(segmentationMap['totalMs'])} ms',
            ),
            Text(
              'Sampled peak process PSS ${segmentationMap['sampledPeakPssKb']} kB',
            ),
          ],
          if (overlayPath is String && overlayPath.isNotEmpty) ...<Widget>[
            const SizedBox(height: IrisSpacing.sm),
            Image.file(
              File(overlayPath),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Text('Generated overlay is unavailable.'),
            ),
          ],
          if (result?['error_message'] case final String message) Text(message),
        ],
      ),
    );
  }

  String _number(Object? value) =>
      value is num ? value.toStringAsFixed(1) : 'unavailable';
}
