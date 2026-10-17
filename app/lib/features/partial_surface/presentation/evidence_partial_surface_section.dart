import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/iris_spacing.dart';
import '../../../core/widgets/iris_button.dart';
import '../../../core/widgets/iris_card.dart';
import '../application/evidence_partial_surface_controller.dart';
import '../domain/evidence_partial_surface.dart';
import 'evidence_partial_surface_preview.dart';

class EvidencePartialSurfaceSection extends StatefulWidget {
  const EvidencePartialSurfaceSection({required this.controller, super.key});
  final EvidencePartialSurfaceController controller;

  @override
  State<EvidencePartialSurfaceSection> createState() =>
      _EvidencePartialSurfaceSectionState();
}

class _EvidencePartialSurfaceSectionState
    extends State<EvidencePartialSurfaceSection> {
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

  Future<void> _inspect(EvidencePartialSurfaceAnalysis analysis) async {
    try {
      final meshes = await Future.wait(
        analysis.parts.map(widget.controller.operations.read),
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => EvidencePartialSurfacePreview(meshes: meshes),
        ),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved partial-surface artifact is unavailable.'),
          ),
        );
      }
    }
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
              'Evidence-coloured partial 3D surface',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: IrisSpacing.xs),
            const Text(
              'Uses only visible current vehicle-mask pixels, original image colour and relative depth. It is partial and nonmetric: no hidden geometry, dimensions, damage finding or world placement is created.',
            ),
            const SizedBox(height: IrisSpacing.sm),
            Text(_status(snapshot)),
            if (!widget.controller.executionEnabled) ...<Widget>[
              const SizedBox(height: IrisSpacing.xs),
              const Text(
                'Generation is disabled outside development builds while MobileSAM release eligibility remains unresolved.',
              ),
            ],
            if (analysis != null &&
                snapshot.state ==
                    EvidencePartialSurfaceState.current) ...<Widget>[
              const SizedBox(height: IrisSpacing.sm),
              Text(
                '${analysis.parts.length} visible surface part${analysis.parts.length == 1 ? '' : 's'} · ${analysis.parts.map((part) => '${part.className}: ${part.vertexCount} vertices / ${part.triangleCount} triangles').join(' · ')}',
              ),
              Text(
                'Total ${_ms(analysis.totalMs)} ms · sampled peak PSS ${analysis.sampledPeakPssKb ?? 'unavailable'} kB',
              ),
              const SizedBox(height: IrisSpacing.sm),
              IrisSecondaryButton(
                label: 'Inspect visible partial 3D surface',
                icon: Icons.threed_rotation,
                onPressed: () => _inspect(analysis),
              ),
            ],
            const SizedBox(height: IrisSpacing.sm),
            if (widget.controller.busy)
              IrisSecondaryButton(
                label: 'Cancel after safe surface release',
                icon: Icons.cancel_outlined,
                onPressed: widget.controller.cancel,
              )
            else
              IrisPrimaryButton(
                label: analysis == null
                    ? 'Generate partial 3D surface'
                    : 'Regenerate partial 3D surface',
                icon: Icons.view_in_ar,
                onPressed: widget.controller.executionEnabled
                    ? widget.controller.generate
                    : null,
              ),
          ],
        ),
      );
    },
  );

  String _status(EvidencePartialSurfaceSnapshot snapshot) {
    if (snapshot.message != null) return snapshot.message!;
    return switch (snapshot.state) {
      EvidencePartialSurfaceState.notGenerated =>
        'No visible partial surface has been generated.',
      EvidencePartialSurfaceState.generating =>
        'Generating a bounded visible-only surface on device…',
      EvidencePartialSurfaceState.current =>
        'Current partial-surface provenance and artifacts verified.',
      EvidencePartialSurfaceState.stale =>
        'Saved partial surface is stale and will not be used.',
      EvidencePartialSurfaceState.missingSegmentation =>
        'A current qualified car or motorcycle mask is required.',
      EvidencePartialSurfaceState.missingDepth =>
        'Current relative depth is required.',
      EvidencePartialSurfaceState.unavailable =>
        'Partial-surface data is unavailable.',
      EvidencePartialSurfaceState.insufficientEvidence =>
        'Insufficient connected visible evidence for a partial surface.',
      EvidencePartialSurfaceState.cancelled =>
        'Generation cancelled; no new partial surface was saved.',
      EvidencePartialSurfaceState.error =>
        'Partial-surface generation failed; no fallback surface was saved.',
    };
  }

  String _ms(double? value) =>
      value == null ? 'unavailable' : value.toStringAsFixed(1);
}
