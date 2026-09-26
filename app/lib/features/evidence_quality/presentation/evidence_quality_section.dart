import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/iris_colors.dart';
import '../../../app/theme/iris_spacing.dart';
import '../../../app/theme/iris_typography.dart';
import '../../../core/widgets/iris_button.dart';
import '../../../core/widgets/iris_card.dart';
import '../../../core/widgets/iris_section_header.dart';
import '../../../core/widgets/iris_status_chip.dart';
import '../application/evidence_quality_controller.dart';
import '../domain/evidence_quality_assessment.dart';

class EvidenceQualitySection extends StatefulWidget {
  const EvidenceQualitySection({required this.controller, super.key});

  final EvidenceQualityController controller;

  @override
  State<EvidenceQualitySection> createState() => _EvidenceQualitySectionState();
}

class _EvidenceQualitySectionState extends State<EvidenceQualitySection> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    unawaited(widget.controller.load());
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final EvidenceQualityController controller = widget.controller;
    final EvidenceQualitySnapshot snapshot = controller.snapshot;
    final EvidenceQualityAssessment? assessment = snapshot.assessment;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const IrisSectionHeader(
          title: 'Evidence Quality',
          supportingText:
              'Deterministic checks of the stored original and decoded pixels.',
        ),
        const SizedBox(height: IrisSpacing.sm),
        if (controller.loading && assessment == null)
          const IrisCard(
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: IrisSpacing.sm),
                Expanded(child: Text('Loading saved quality assessment…')),
              ],
            ),
          )
        else if (snapshot.state == EvidenceQualitySnapshotState.notAssessed)
          const IrisCard(
            child: Text(
              'Not assessed. Run quality checks to calculate real integrity and image measurements.',
            ),
          )
        else if (snapshot.state == EvidenceQualitySnapshotState.stale)
          const IrisCard(
            child: Text(
              'Reassessment needed. The saved result does not match the current algorithm or stored evidence bytes.',
            ),
          )
        else if (snapshot.state == EvidenceQualitySnapshotState.unavailable)
          IrisCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('The saved quality assessment is unavailable.'),
                const SizedBox(height: IrisSpacing.xs),
                TextButton(
                  onPressed: controller.loading ? null : controller.load,
                  child: const Text('Retry'),
                ),
              ],
            ),
          )
        else if (assessment != null)
          _AssessmentDetails(assessment: assessment),
        if (controller.errorMessage != null) ...<Widget>[
          const SizedBox(height: IrisSpacing.sm),
          IrisCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.error_outline, color: IrisColors.danger),
                const SizedBox(width: IrisSpacing.xs),
                Expanded(child: Text(controller.errorMessage!)),
              ],
            ),
          ),
        ],
        const SizedBox(height: IrisSpacing.sm),
        if (controller.assessing)
          const Padding(
            padding: EdgeInsets.only(bottom: IrisSpacing.xs),
            child: LinearProgressIndicator(
              semanticsLabel: 'Assessing evidence quality',
            ),
          ),
        IrisSecondaryButton(
          key: const ValueKey<String>('assess-evidence-quality-button'),
          label: controller.assessing
              ? 'Assessing quality…'
              : assessment == null &&
                    snapshot.state != EvidenceQualitySnapshotState.stale
              ? 'Assess Quality'
              : 'Reassess Quality',
          semanticLabel: controller.assessing
              ? 'Evidence quality assessment in progress'
              : 'Run deterministic evidence quality assessment',
          icon: Icons.fact_check_outlined,
          onPressed: controller.assessing ? null : controller.assess,
        ),
        const SizedBox(height: IrisSpacing.sm),
        Text(
          'Quality checks evaluate technical image characteristics only. '
          'They do not determine whether an accident occurred or what caused it.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _AssessmentDetails extends StatelessWidget {
  const _AssessmentDetails({required this.assessment});

  final EvidenceQualityAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final List<Widget> measurementRows = <Widget>[
      if (assessment.originalWidth != null && assessment.originalHeight != null)
        _MetricRow(
          label: 'Resolution',
          value:
              '${assessment.originalWidth} × ${assessment.originalHeight} px '
              '(${assessment.megapixels!.toStringAsFixed(2)} MP)',
        ),
      if (assessment.orientation != null)
        _MetricRow(
          label: 'Orientation',
          value: assessment.orientation!.displayLabel,
        ),
      if (assessment.analysisWidth != null && assessment.analysisHeight != null)
        _MetricRow(
          label: 'Analysis image',
          value:
              '${assessment.analysisWidth} × ${assessment.analysisHeight} px',
        ),
      if (assessment.sharpnessValue != null)
        _MetricRow(
          label: 'Sharpness',
          value:
              '${assessment.sharpnessValue!.toStringAsFixed(2)} Laplacian variance',
        ),
      if (assessment.meanLuminance != null)
        _MetricRow(
          label: 'Mean luminance',
          value: '${assessment.meanLuminance!.toStringAsFixed(2)} / 255',
        ),
      if (assessment.darkClippedFraction != null)
        _MetricRow(
          label: 'Near-black pixels',
          value: _percentage(assessment.darkClippedFraction!),
        ),
      if (assessment.brightClippedFraction != null)
        _MetricRow(
          label: 'Near-white pixels',
          value: _percentage(assessment.brightClippedFraction!),
        ),
      if (assessment.fileSizeBytes != null)
        _MetricRow(
          label: 'Measured file size',
          value: '${assessment.fileSizeBytes} bytes',
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        IrisCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: IrisSpacing.xs,
                runSpacing: IrisSpacing.xs,
                children: <Widget>[
                  IrisStatusChip(
                    key: const ValueKey<String>('quality-readiness-chip'),
                    label: assessment.readiness.displayLabel,
                    tone: _readinessTone(assessment.readiness),
                  ),
                  IrisStatusChip(
                    key: const ValueKey<String>('quality-integrity-chip'),
                    label:
                        'Integrity: ${assessment.integrityState.displayLabel}',
                    tone: _integrityTone(assessment.integrityState),
                  ),
                ],
              ),
              const SizedBox(height: IrisSpacing.sm),
              _MetricRow(
                label: 'File',
                value: assessment.fileState.displayLabel,
              ),
              _MetricRow(
                label: 'Decode',
                value: assessment.decodeState.displayLabel,
              ),
              _MetricRow(
                label: 'Assessed',
                value: assessment.assessedAt.toLocal().toString(),
              ),
              _MetricRow(
                label: 'Algorithm',
                value: assessment.algorithmVersion,
              ),
            ],
          ),
        ),
        if (measurementRows.isNotEmpty) ...<Widget>[
          const SizedBox(height: IrisSpacing.sm),
          IrisCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Measured characteristics',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: IrisSpacing.sm),
                ...measurementRows,
              ],
            ),
          ),
        ],
        const SizedBox(height: IrisSpacing.sm),
        IrisCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Findings', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: IrisSpacing.xs),
              if (assessment.findings.isEmpty)
                const Text(
                  'No configured technical quality limitations were found.',
                )
              else
                ...assessment.findings.map(
                  (EvidenceQualityFinding finding) => Padding(
                    padding: const EdgeInsets.only(bottom: IrisSpacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          finding.severity == EvidenceQualitySeverity.critical
                              ? Icons.error_outline
                              : Icons.warning_amber_outlined,
                          color:
                              finding.severity ==
                                  EvidenceQualitySeverity.critical
                              ? IrisColors.danger
                              : IrisColors.warning,
                          size: 20,
                        ),
                        const SizedBox(width: IrisSpacing.xs),
                        Expanded(child: Text(finding.explanation)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _percentage(double value) =>
      '${(value * 100).toStringAsFixed(1)}%';

  static IrisStatusTone _readinessTone(EvidenceReadiness state) =>
      switch (state) {
        EvidenceReadiness.ready => IrisStatusTone.success,
        EvidenceReadiness.usableWithLimitations => IrisStatusTone.warning,
        EvidenceReadiness.notUsable => IrisStatusTone.danger,
      };

  static IrisStatusTone _integrityTone(EvidenceIntegrityState state) =>
      switch (state) {
        EvidenceIntegrityState.verified => IrisStatusTone.success,
        EvidenceIntegrityState.mismatch => IrisStatusTone.danger,
        EvidenceIntegrityState.unavailable => IrisStatusTone.warning,
      };
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: IrisSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: Text(label)),
        const SizedBox(width: IrisSpacing.sm),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: IrisTypography.technicalValue,
          ),
        ),
      ],
    ),
  );
}
