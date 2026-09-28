import 'package:flutter/material.dart';
import '../../../app/theme/iris_spacing.dart';
import '../../../core/widgets/iris_button.dart';
import '../../../core/widgets/iris_card.dart';
import '../../../core/widgets/iris_section_header.dart';
import '../../../core/widgets/iris_status_chip.dart';
import '../application/evidence_detection_controller.dart';
import '../domain/evidence_detection.dart';

class EvidenceDetectionSection extends StatefulWidget {
  const EvidenceDetectionSection({required this.controller, super.key});
  final EvidenceDetectionController controller;
  @override
  State<EvidenceDetectionSection> createState() =>
      _EvidenceDetectionSectionState();
}

class _EvidenceDetectionSectionState extends State<EvidenceDetectionSection> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.controller.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = c.snapshot;
    final a = s.analysis;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const IrisSectionHeader(
          title: 'Scene objects',
          supportingText:
              'Real offline road-user detections from the qualified COCO detector.',
        ),
        const SizedBox(height: IrisSpacing.sm),
        IrisCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (c.busy)
                const Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: IrisSpacing.sm),
                    Text('Detecting scene objects…'),
                  ],
                )
              else ...[
                IrisStatusChip(label: _label(s.state)),
                const SizedBox(height: IrisSpacing.sm),
                Text(s.message ?? _message(s.state)),
                if (a != null) ...[
                  const SizedBox(height: IrisSpacing.sm),
                  Text('Objects detected: ${a.detections.length}'),
                  ...a.detections.map(
                    (d) => Text(
                      '${d.className} — Detection score: ${d.score.toStringAsFixed(3)}',
                    ),
                  ),
                ],
              ],
              const SizedBox(height: IrisSpacing.sm),
              IrisPrimaryButton(
                key: const ValueKey('detect-scene-objects-button'),
                label: a == null
                    ? 'Detect Scene Objects'
                    : 'Redetect Scene Objects',
                icon: Icons.center_focus_strong,
                onPressed: c.busy || s.state == DetectionState.unavailable
                    ? null
                    : c.analyze,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _label(DetectionState s) => switch (s) {
    DetectionState.notAnalyzed => 'Not analyzed',
    DetectionState.detecting => 'Detecting',
    DetectionState.complete => 'Complete',
    DetectionState.stale => 'Stale',
    DetectionState.unavailable => 'Unavailable',
    DetectionState.error => 'Error',
  };
  String _message(DetectionState s) => switch (s) {
    DetectionState.notAnalyzed =>
      'No scene-object analysis has been saved for these evidence bytes.',
    DetectionState.detecting => 'Detection is running locally.',
    DetectionState.complete =>
      'Detections are derived from actual model inference.',
    DetectionState.stale =>
      'Saved detections no longer match current evidence or detector provenance.',
    DetectionState.unavailable =>
      'A current usable quality assessment is required.',
    DetectionState.error =>
      'Detection failed; no replacement detections were created.',
  };
}
