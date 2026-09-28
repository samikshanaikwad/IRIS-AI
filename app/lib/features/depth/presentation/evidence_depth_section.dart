import 'package:flutter/material.dart';
import '../../../app/theme/iris_spacing.dart';
import '../../../core/widgets/iris_card.dart';
import '../../../core/widgets/iris_button.dart';
import '../application/evidence_depth_controller.dart';
import '../domain/evidence_depth.dart';

class EvidenceDepthSection extends StatelessWidget {
  const EvidenceDepthSection({required this.controller, super.key});
  final EvidenceDepthController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: controller, builder: (context, _) {
    final s = controller.snapshot; final a = s.analysis;
    return IrisCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('DEPTH ANALYSIS', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: IrisSpacing.xs), Text(_status(s)),
      if (s.state == DepthState.analyzed && a != null) ...[
        const Text('Model: Depth Anything V2 Small'),
        const Text('Output: Relative depth'),
        const Text('Larger values indicate nearer scene structure.'),
        const Text('Relative depth is model-estimated scene structure, not measured distance.'),
        Text('Range: ${a.min.toStringAsFixed(3)} – ${a.max.toStringAsFixed(3)}'),
      ],
      if (s.message != null) Text(s.message!),
      const SizedBox(height: IrisSpacing.sm),
      IrisPrimaryButton(label: controller.busy ? 'Analyzing depth…' : a == null ? 'Analyze Depth' : 'Reanalyze Depth', icon: Icons.layers_outlined, onPressed: controller.busy ? null : controller.analyze),
    ]));
  });
  String _status(EvidenceDepthSnapshot s) => switch (s.state) {
    DepthState.notAnalyzed => 'Not analyzed',
    DepthState.analyzing => 'Analyzing',
    DepthState.analyzed => 'Analyzed',
    DepthState.stale => 'Stale / reanalysis required',
    DepthState.failed => 'Failed',
    DepthState.unavailable => 'Unavailable',
  };
}
