import 'package:flutter/material.dart';

import '../../../app/theme/iris_spacing.dart';
import '../../../core/widgets/iris_button.dart';
import '../../../core/widgets/iris_card.dart';
import '../../../core/widgets/iris_section_header.dart';
import '../../../core/widgets/iris_status_chip.dart';
import '../application/evidence_classification_controller.dart';
import '../domain/evidence_classification.dart';

class EvidenceClassificationSection extends StatefulWidget {
  const EvidenceClassificationSection({required this.controller, super.key});
  final EvidenceClassificationController controller;
  @override
  State<EvidenceClassificationSection> createState() =>
      _EvidenceClassificationSectionState();
}

class _EvidenceClassificationSectionState
    extends State<EvidenceClassificationSection> {
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
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final EvidenceClassificationController controller = widget.controller;
    final EvidenceClassificationSnapshot snapshot = controller.snapshot;
    final EvidenceClassification? value = snapshot.classification;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const IrisSectionHeader(
          title: 'Image classification',
          supportingText:
              'Experimental local model analysis for this individual evidence image.',
        ),
        const SizedBox(height: IrisSpacing.sm),
        IrisCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (controller.analyzing)
                const Row(
                  children: <Widget>[
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: IrisSpacing.sm),
                    Text('Analyzing stored evidence…'),
                  ],
                )
              else ...<Widget>[
                IrisStatusChip(label: _label(snapshot.state)),
                const SizedBox(height: IrisSpacing.sm),
                Text(_message(snapshot.state)),
                if (snapshot.qualityHasLimitations)
                  const Padding(
                    padding: EdgeInsets.only(top: IrisSpacing.sm),
                    child: Text(
                      'Quality: Usable with limitations. Classification is permitted, but the quality findings remain relevant.',
                    ),
                  ),
                if (value != null) ...<Widget>[
                  const SizedBox(height: IrisSpacing.sm),
                  Text(
                    'Result: ${value.label.displayLabel}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text('Model score: ${value.modelScore.toStringAsFixed(6)}'),
                  Text('Analyzed: ${value.analyzedAt.toLocal()}'),
                  Text('Model: ${value.modelId}'),
                ],
                if (controller.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: IrisSpacing.sm),
                    child: Text(controller.errorMessage!),
                  ),
              ],
              const SizedBox(height: IrisSpacing.sm),
              IrisPrimaryButton(
                key: const ValueKey<String>('analyze-evidence-button'),
                label: value == null ? 'Analyze Image' : 'Reanalyze Image',
                icon: Icons.analytics_outlined,
                onPressed:
                    controller.analyzing ||
                        snapshot.state == EvidenceClassificationState.blocked ||
                        snapshot.state ==
                            EvidenceClassificationState.qualityRequired ||
                        snapshot.state ==
                            EvidenceClassificationState.unavailable
                    ? null
                    : controller.analyze,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _label(EvidenceClassificationState state) => switch (state) {
    EvidenceClassificationState.notAnalyzed => 'Ready for classification',
    EvidenceClassificationState.qualityRequired =>
      'Quality assessment required',
    EvidenceClassificationState.blocked => 'Not usable for classification',
    EvidenceClassificationState.current => 'Analysis current',
    EvidenceClassificationState.stale => 'Result stale',
    EvidenceClassificationState.unavailable => 'Classification unavailable',
  };
  String _message(EvidenceClassificationState state) => switch (state) {
    EvidenceClassificationState.notAnalyzed =>
      'No classification has been saved for these evidence bytes.',
    EvidenceClassificationState.qualityRequired =>
      'Assess evidence quality before running the classifier.',
    EvidenceClassificationState.blocked =>
      'The current quality assessment blocks classification.',
    EvidenceClassificationState.current =>
      'The displayed result is an experimental image classification, not a reconstruction conclusion.',
    EvidenceClassificationState.stale =>
      'The saved result no longer matches current evidence or model provenance.',
    EvidenceClassificationState.unavailable =>
      'Local classification status could not be determined.',
  };
}
