import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/iris_spacing.dart';
import '../../../app/theme/iris_colors.dart';
import '../../../core/widgets/iris_app_bar.dart';
import '../../../core/widgets/iris_button.dart';
import '../../../core/widgets/iris_card.dart';
import '../../../core/widgets/iris_page_body.dart';
import '../application/evidence_controller.dart';
import '../domain/evidence_image.dart';
import '../../evidence_quality/application/evidence_quality_controller.dart';
import '../../evidence_quality/presentation/evidence_quality_section.dart';
import '../../classification/application/evidence_classification_controller.dart';
import '../../classification/presentation/evidence_classification_section.dart';
import '../../detection/application/evidence_detection_controller.dart';
import '../../detection/domain/evidence_detection.dart';
import '../../detection/presentation/evidence_detection_section.dart';
import '../../depth/application/evidence_depth_controller.dart';
import '../../depth/presentation/evidence_depth_section.dart';
import '../../geometry/application/relative_geometry_controller.dart';
import '../../geometry/presentation/relative_geometry_section.dart';
import '../../segmentation_qualification/segmentation_prompt_box.dart';

class EvidenceDetailScreen extends StatefulWidget {
  const EvidenceDetailScreen({
    required this.evidence,
    required this.controller,
    required this.qualityController,
    required this.classificationController,
    required this.detectionController,
    required this.depthController,
    required this.geometryController,
    super.key,
  });

  final EvidenceImage evidence;
  final EvidenceController controller;
  final EvidenceQualityController qualityController;
  final EvidenceClassificationController classificationController;
  final EvidenceDetectionController detectionController;
  final EvidenceDepthController depthController;
  final RelativeGeometryController geometryController;

  @override
  State<EvidenceDetailScreen> createState() => _EvidenceDetailScreenState();
}

class _EvidenceDetailScreenState extends State<EvidenceDetailScreen> {
  String? _path;
  bool _missing = false;
  bool _deleting = false;
  bool _segmentationBusy = false;
  Map<String, Object?>? _segmentationResult;
  String? _segmentationFailure;

  static const MethodChannel _segmentationChannel = MethodChannel(
    'com.iris.debug/segmentation-qualification',
  );

  @override
  void initState() {
    super.initState();
    unawaited(widget.depthController.load());
    unawaited(widget.geometryController.load());
    widget.controller.absolutePath(widget.evidence).then((String value) async {
      final bool exists = await File(value).exists();
      if (mounted) {
        setState(() {
          _path = value;
          _missing = !exists;
        });
      }
    });
  }

  Future<void> _remove() async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('Delete evidence?'),
            content: const Text(
              'This permanently removes the stored evidence copy and its metadata from this case.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                key: const ValueKey<String>('confirm-detail-evidence-delete'),
                style: TextButton.styleFrom(foregroundColor: IrisColors.danger),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _deleting = true);
    try {
      final bool deleted = await widget.controller.delete(widget.evidence);
      if (!mounted) {
        return;
      }
      if (!deleted) {
        throw StateError('Evidence record is unavailable.');
      }
      Navigator.of(context).pop();
    } on Object {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The evidence could not be deleted. Try again.'),
          ),
        );
      }
    }
  }

  Future<void> _qualifySegmentation() async {
    final snapshot = widget.detectionController.snapshot;
    final analysis = snapshot.analysis;
    final metadata = analysis?.coordinateMetadata;
    if (!kDebugMode ||
        snapshot.state != DetectionState.complete ||
        analysis == null ||
        analysis.evidenceSha256 != widget.evidence.sha256 ||
        metadata == null ||
        _segmentationBusy) {
      return;
    }
    final prompts = <Map<String, Object>>[];
    var rejectedPrompts = 0;
    for (final detection in analysis.detections) {
      if (!SegmentationPromptBox.supportedClasses.containsKey(
        detection.classId,
      )) {
        continue;
      }
      try {
        prompts.add(
          SegmentationPromptBox.fromDetection(
            detection: detection,
            metadata: metadata,
          ).toChannelValue(),
        );
      } on FormatException {
        rejectedPrompts++;
      }
    }
    if (prompts.isEmpty) {
      setState(() {
        _segmentationFailure =
            'No eligible current vehicle box maps to valid image pixels.';
        _segmentationResult = null;
      });
      return;
    }
    setState(() {
      _segmentationBusy = true;
      _segmentationFailure = null;
      _segmentationResult = null;
    });
    try {
      final result = await _segmentationChannel
          .invokeMapMethod<String, Object?>(
            'runQualification',
            <String, Object?>{
              'absolutePath': _path,
              'coordinateContractVersion': metadata.contractVersion,
              'boxes': prompts,
            },
          );
      if (result == null || result['status'] != 'MASKS_GENERATED_ON_DEVICE') {
        throw StateError('No real mask was returned.');
      }
      if (mounted) {
        setState(() {
          _segmentationResult = <String, Object?>{
            ...result,
            'rejectedPrompts': rejectedPrompts,
          };
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _segmentationFailure =
              error.message ??
              'The on-device qualification runner is unavailable.';
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _segmentationFailure =
              'On-device segmentation failed; no mask or fallback was saved.';
        });
      }
    } finally {
      if (mounted) setState(() => _segmentationBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final EvidenceImage evidence = widget.evidence;
    return Scaffold(
      appBar: const IrisAppBar(title: 'Evidence Detail'),
      body: IrisPageBody(
        children: <Widget>[
          AspectRatio(
            aspectRatio: evidence.widthPx != null && evidence.heightPx != null
                ? evidence.widthPx! / evidence.heightPx!
                : 4 / 3,
            child: IrisCard(
              padding: EdgeInsets.zero,
              child: _path == null
                  ? const Center(child: CircularProgressIndicator())
                  : _missing
                  ? const Center(
                      child: Text('Stored evidence file is unavailable.'),
                    )
                  : InteractiveViewer(
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          Image.file(
                            File(_path!),
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Center(
                              child: Text(
                                'This image cannot be displayed on this device.',
                              ),
                            ),
                          ),
                          AnimatedBuilder(
                            animation: widget.detectionController,
                            builder: (BuildContext context, Widget? child) =>
                                IgnorePointer(
                                  child: CustomPaint(
                                    painter: _DetectionOverlayPainter(
                                      detections:
                                          widget
                                              .detectionController
                                              .snapshot
                                              .analysis
                                              ?.detections ??
                                          const <EvidenceDetection>[],
                                      sourceSize: Size(
                                        (evidence.widthPx ?? 1).toDouble(),
                                        (evidence.heightPx ?? 1).toDouble(),
                                      ),
                                    ),
                                  ),
                                ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: IrisSpacing.md),
          IrisCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Metadata(label: 'Source', value: evidence.source.displayLabel),
                if (evidence.originalDisplayName != null)
                  _Metadata(
                    label: 'Original name',
                    value: evidence.originalDisplayName!,
                  ),
                if (evidence.capturedAt != null)
                  _Metadata(
                    label: 'Captured',
                    value: evidence.capturedAt!.toLocal().toString(),
                  ),
                _Metadata(
                  label: 'Imported',
                  value: evidence.importedAt.toLocal().toString(),
                ),
                _Metadata(
                  label: 'File size',
                  value: '${evidence.fileSizeBytes} bytes',
                ),
                if (evidence.widthPx != null && evidence.heightPx != null)
                  _Metadata(
                    label: 'Dimensions',
                    value: '${evidence.widthPx} × ${evidence.heightPx} px',
                  ),
                if (evidence.mimeType != null)
                  _Metadata(label: 'Media type', value: evidence.mimeType!),
                _Metadata(label: 'SHA-256', value: evidence.sha256),
              ],
            ),
          ),
          const SizedBox(height: IrisSpacing.md),
          EvidenceQualitySection(controller: widget.qualityController),
          const SizedBox(height: IrisSpacing.md),
          EvidenceClassificationSection(
            controller: widget.classificationController,
          ),
          const SizedBox(height: IrisSpacing.md),
          EvidenceDetectionSection(controller: widget.detectionController),
          if (kDebugMode) ...<Widget>[
            const SizedBox(height: IrisSpacing.sm),
            _segmentationQualificationPanel(),
          ],
          const SizedBox(height: IrisSpacing.md),
          EvidenceDepthSection(controller: widget.depthController),
          const SizedBox(height: IrisSpacing.md),
          RelativeGeometrySection(controller: widget.geometryController),
          const SizedBox(height: IrisSpacing.md),
          IrisSecondaryButton(
            key: const ValueKey<String>('detail-remove-evidence-button'),
            label: _deleting ? 'Deleting evidence…' : 'Remove Evidence',
            icon: Icons.delete_outline,
            onPressed: _deleting ? null : _remove,
          ),
        ],
      ),
    );
  }

  Widget _segmentationQualificationPanel() {
    final snapshot = widget.detectionController.snapshot;
    final analysis = snapshot.analysis;
    final canRun =
        snapshot.state == DetectionState.complete &&
        analysis != null &&
        analysis.evidenceSha256 == widget.evidence.sha256 &&
        analysis.coordinateMetadata != null &&
        analysis.detections.any(
          (detection) => SegmentationPromptBox.supportedClasses.containsKey(
            detection.classId,
          ),
        );
    final result = _segmentationResult;
    final overlayPath = result?['overlayPath'];
    final detectionResults = result?['promptMaskResults'];
    return IrisCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text('Segmentation qualification — debug only'),
          const SizedBox(height: IrisSpacing.xs),
          const Text(
            'Uses current saved TASK007 boxes as prompts. It does not save a mask as evidence or alter the production reconstruction.',
          ),
          const SizedBox(height: IrisSpacing.sm),
          IrisPrimaryButton(
            key: const ValueKey<String>('debug-segmentation-qualification'),
            label: _segmentationBusy
                ? 'Running on this device…'
                : 'Run real on-device mask qualification',
            icon: Icons.layers_outlined,
            onPressed: !canRun || _segmentationBusy || _path == null
                ? null
                : _qualifySegmentation,
          ),
          if (analysis?.coordinateMetadata == null)
            const Text('Requires current v2 image-coordinate metadata.'),
          if (_segmentationFailure != null) ...<Widget>[
            const SizedBox(height: IrisSpacing.sm),
            Text(_segmentationFailure!),
          ],
          if (result != null && overlayPath is String) ...<Widget>[
            const SizedBox(height: IrisSpacing.md),
            AspectRatio(
              aspectRatio:
                  (result['orientedWidth'] as num).toDouble() /
                  (result['orientedHeight'] as num).toDouble(),
              child: Image.file(
                File(overlayPath),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Center(
                  child: Text('Private-cache mask overlay is unavailable.'),
                ),
              ),
            ),
            const SizedBox(height: IrisSpacing.sm),
            Text('Model: ${result['model']} (class-agnostic prompts)'),
            Text('Coordinate mapping: ${result['coordinateContractVersion']}'),
            Text(
              'Preprocess ${_ms(result['preprocessMs'])} ms • encoder ${_ms(result['imageEncoderMs'])} ms • total ${_ms(result['totalMs'])} ms',
            ),
            Text(
              'Sampled peak process PSS: ${result['sampledPeakPssKb']} kB (baseline ${result['baselinePssKb']} kB; sampling may miss brief peaks)',
            ),
            if (result['rejectedPrompts'] != 0)
              Text(
                'Boxes rejected by coordinate checks: ${result['rejectedPrompts']}',
              ),
            if (detectionResults is List<Object?>)
              ...detectionResults.whereType<Map<Object?, Object?>>().map(
                (item) => Text(
                  '${item['className']}: ${item['status']}, mask pixels ${item['maskPixels']}, model score ${_score(item['predictedQuality'])}, mask/box ratio ${_score(item['maskToBoxAreaRatio'])}, mask-box IoU ${_score(item['maskBoundingBoxIou'])}',
                ),
              ),
            const SizedBox(height: IrisSpacing.xs),
            const Text(
              'Mask/box overlap and model score are diagnostics, not ground-truth accuracy. Overlay colors are visualization-only.',
            ),
            SelectableText('Overlay SHA-256: ${result['overlaySha256']}'),
          ],
        ],
      ),
    );
  }

  String _ms(Object? value) =>
      value is num ? value.toStringAsFixed(1) : 'unavailable';
  String _score(Object? value) =>
      value is num ? value.toStringAsFixed(3) : 'unavailable';
}

class _Metadata extends StatelessWidget {
  const _Metadata({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: IrisSpacing.xs),
    child: SelectableText('$label: $value'),
  );
}

class _DetectionOverlayPainter extends CustomPainter {
  const _DetectionOverlayPainter({
    required this.detections,
    required this.sourceSize,
  });
  final List<EvidenceDetection> detections;
  final Size sourceSize;
  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty || sourceSize.isEmpty) return;
    final scale =
        (size.width / sourceSize.width < size.height / sourceSize.height
                ? size.width / sourceSize.width
                : size.height / sourceSize.height)
            .toDouble();
    final imageSize = Size(sourceSize.width * scale, sourceSize.height * scale);
    final offset = Offset(
      (size.width - imageSize.width) / 2,
      (size.height - imageSize.height) / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.amber;
    for (final d in detections) {
      final rect = Rect.fromLTRB(
        offset.dx + d.xmin * imageSize.width,
        offset.dy + d.ymin * imageSize.height,
        offset.dx + d.xmax * imageSize.width,
        offset.dy + d.ymax * imageSize.height,
      );
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_DetectionOverlayPainter oldDelegate) =>
      oldDelegate.detections != detections ||
      oldDelegate.sourceSize != sourceSize;
}
