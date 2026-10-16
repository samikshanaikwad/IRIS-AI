import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/theme/iris_spacing.dart';
import '../../../core/widgets/iris_button.dart';
import '../../../core/widgets/iris_card.dart';
import '../application/evidence_segmentation_controller.dart';
import '../domain/evidence_segmentation.dart';

class EvidenceSegmentationSection extends StatefulWidget {
  const EvidenceSegmentationSection({required this.controller, super.key});

  final EvidenceSegmentationController controller;

  @override
  State<EvidenceSegmentationSection> createState() =>
      _EvidenceSegmentationSectionState();
}

class _EvidenceSegmentationSectionState
    extends State<EvidenceSegmentationSection> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.load());
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final snapshot = widget.controller.snapshot;
      final analysis = snapshot.analysis;
      return IrisCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Observed vehicle mask',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: IrisSpacing.xs),
            const Text(
              'MobileSAM uses current TASK007 car or motorcycle boxes. A mask represents visible prompted pixels only; it does not establish damage, hidden geometry, dimensions, or depth.',
            ),
            const SizedBox(height: IrisSpacing.sm),
            Text(_status(snapshot)),
            if (!widget.controller.executionEnabled) ...<Widget>[
              const SizedBox(height: IrisSpacing.xs),
              const Text(
                'Execution is disabled outside development builds while model redistribution and memory safeguards remain under review.',
              ),
            ],
            if (analysis != null &&
                snapshot.state ==
                    EvidenceSegmentationState.current) ...<Widget>[
              const SizedBox(height: IrisSpacing.md),
              FutureBuilder<String>(
                future: widget.controller.operations.overlayAbsolutePath(
                  analysis,
                ),
                builder: (context, pathSnapshot) {
                  final overlayPath = pathSnapshot.data;
                  if (overlayPath == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return AspectRatio(
                    aspectRatio:
                        analysis.coordinateMetadata.oriented.width /
                        analysis.coordinateMetadata.oriented.height,
                    child: Image.file(
                      File(overlayPath),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Center(
                        child: Text('Saved mask overlay is unavailable.'),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: IrisSpacing.sm),
              Text(
                '${analysis.masks.length} persisted mask${analysis.masks.length == 1 ? '' : 's'} · ${analysis.masks.map((mask) => mask.className).join(', ')}',
              ),
              Text(
                'Total ${_ms(analysis.totalMs)} ms · sampled peak PSS ${analysis.sampledPeakPssKb ?? 'unavailable'} kB',
              ),
              SelectableText('Overlay SHA-256: ${analysis.overlaySha256}'),
            ],
            const SizedBox(height: IrisSpacing.sm),
            if (widget.controller.busy)
              IrisSecondaryButton(
                key: const ValueKey<String>('cancel-evidence-segmentation'),
                label: snapshot.state == EvidenceSegmentationState.queued
                    ? 'Cancel queued analysis'
                    : 'Cancel after safe model release',
                icon: Icons.cancel_outlined,
                onPressed: widget.controller.cancel,
              )
            else
              IrisPrimaryButton(
                key: const ValueKey<String>('run-evidence-segmentation'),
                label: analysis == null
                    ? 'Generate observed vehicle mask'
                    : 'Regenerate from current detection',
                icon: Icons.layers_outlined,
                onPressed: widget.controller.executionEnabled
                    ? widget.controller.analyze
                    : null,
              ),
          ],
        ),
      );
    },
  );

  String _status(EvidenceSegmentationSnapshot snapshot) {
    if (snapshot.message != null) return snapshot.message!;
    return switch (snapshot.state) {
      EvidenceSegmentationState.notAnalyzed =>
        'No persisted vehicle mask. Current TASK007 detections are required.',
      EvidenceSegmentationState.queued => 'Waiting for segmentation worker.',
      EvidenceSegmentationState.running => 'Running on-device segmentation…',
      EvidenceSegmentationState.current =>
        'Current mask provenance and artifact integrity verified.',
      EvidenceSegmentationState.stale =>
        'Saved mask is stale and will not be used.',
      EvidenceSegmentationState.unsupported =>
        'Only qualified car and motorcycle detections are supported.',
      EvidenceSegmentationState.unavailable => 'Segmentation unavailable.',
      EvidenceSegmentationState.cancelled =>
        'Segmentation cancelled; no new mask was saved.',
      EvidenceSegmentationState.error =>
        'Segmentation failed; no fallback mask was saved.',
    };
  }

  String _ms(double? value) =>
      value == null ? 'unavailable' : value.toStringAsFixed(1);
}
