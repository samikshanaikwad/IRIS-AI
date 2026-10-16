import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/theme/iris_spacing.dart';
import '../../../core/widgets/iris_button.dart';
import '../../../core/widgets/iris_card.dart';
import '../../../core/widgets/iris_section_header.dart';
import '../../evidence/application/evidence_controller.dart';
import '../../evidence/domain/evidence_image.dart';
import '../application/accident_scenario_service.dart';
import '../domain/accident_scenario.dart';

class AccidentScenarioSection extends StatefulWidget {
  const AccidentScenarioSection({
    required this.caseId,
    required this.service,
    required this.evidenceController,
    super.key,
  });
  final String caseId;
  final AccidentScenarioOperations service;
  final EvidenceController evidenceController;

  @override
  State<AccidentScenarioSection> createState() =>
      _AccidentScenarioSectionState();
}

class _AccidentScenarioSectionState extends State<AccidentScenarioSection> {
  ScenarioWorkspace? _workspace;
  bool _loading = false;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await widget.service.load(widget.caseId);
      if (mounted)
        setState(() {
          _workspace = value;
          _loading = false;
        });
    } on Object {
      if (mounted)
        setState(() {
          _loading = false;
          _error = 'Scenario data is unavailable.';
        });
    }
  }

  Future<void> _generate() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.service.generate(widget.caseId);
      await _load();
    } on Object {
      if (mounted)
        setState(() {
          _working = false;
          _error = 'Scenario analysis could not be completed.';
        });
      return;
    }
    if (mounted) setState(() => _working = false);
  }

  Future<void> _addObservation() async {
    final workspace = _workspace;
    if (workspace == null || workspace.evidence.isEmpty) return;
    var evidence = workspace.evidence.first;
    var kind = ScenarioObservationKind.values.first;
    final subject = TextEditingController();
    final note = TextEditingController();
    final accepted =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Record evidence observation'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'This is stored as a user-entered observation, not a measured or model-established fact.',
                    ),
                    const SizedBox(height: IrisSpacing.sm),
                    DropdownButtonFormField<EvidenceImage>(
                      initialValue: evidence,
                      decoration: const InputDecoration(
                        labelText: 'Supporting evidence',
                      ),
                      items: workspace.evidence
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item.originalDisplayName ?? item.id),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null)
                          setDialogState(() => evidence = value);
                      },
                    ),
                    DropdownButtonFormField<ScenarioObservationKind>(
                      initialValue: kind,
                      decoration: const InputDecoration(
                        labelText: 'Observed feature',
                      ),
                      items: ScenarioObservationKind.values
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setDialogState(() => kind = value);
                      },
                    ),
                    TextField(
                      controller: subject,
                      decoration: const InputDecoration(
                        labelText: 'Subject label',
                        hintText: 'e.g. vehicle A',
                      ),
                    ),
                    TextField(
                      controller: note,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'What is visibly supported?',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save observation'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!accepted) return;
    try {
      await widget.service.addObservation(
        caseId: widget.caseId,
        evidence: evidence,
        kind: kind,
        subjectLabel: subject.text,
        note: note.text,
      );
      await _load();
    } on Object {
      if (mounted)
        setState(
          () => _error = 'A subject and evidence-grounded note are required.',
        );
    } finally {
      subject.dispose();
      note.dispose();
    }
  }

  Future<void> _inspect(String evidenceId) async {
    final evidence = _workspace?.evidence
        .where((item) => item.id == evidenceId)
        .firstOrNull;
    if (evidence == null) return;
    final path = await widget.evidenceController.absolutePath(evidence);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(evidence.originalDisplayName ?? 'Supporting evidence'),
        content: Image.file(
          File(path),
          errorBuilder: (_, __, ___) =>
              const Text('Evidence image is not available.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workspace = _workspace;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const IrisSectionHeader(
          title: 'Possible Accident Scenarios',
          supportingText:
              'Evidence-supported hypotheses for investigation — not established cause, fault, speed, or probability.',
        ),
        const SizedBox(height: IrisSpacing.sm),
        if (_loading)
          const IrisCard(child: Text('Loading scenario evidence…'))
        else if (_error != null)
          IrisCard(child: Text(_error!))
        else if (workspace == null)
          IrisCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Not assessed. IRIS generates no generic accident possibilities.',
                ),
                const SizedBox(height: IrisSpacing.sm),
                IrisPrimaryButton(
                  label: 'Review scenario evidence',
                  onPressed: _load,
                ),
              ],
            ),
          )
        else ...[
          if (workspace.evidence.isEmpty)
            const IrisCard(
              child: Text(
                'Insufficient evidence: add genuine case evidence before recording observations.',
              ),
            ),
          for (final observation in workspace.observations)
            Padding(
              padding: const EdgeInsets.only(bottom: IrisSpacing.xs),
              child: IrisCard(
                child: Row(
                  children: [
                    const Icon(Icons.visibility_outlined),
                    const SizedBox(width: IrisSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            observation.kind.label,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            '${observation.subjectLabel}: ${observation.note}',
                          ),
                          const Text('Provenance: USER_ENTERED'),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove observation',
                      onPressed: () async {
                        await widget.service.deleteObservation(observation.id);
                        await _load();
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            ),
          if (workspace.analysis?.state == ScenarioAnalysisState.stale)
            const IrisCard(
              child: Text(
                'Previous hypotheses are stale because supporting evidence or observations changed. Generate again to reassess.',
              ),
            ),
          if (workspace.analysis?.state ==
              ScenarioAnalysisState.insufficientEvidence)
            const IrisCard(
              child: Text(
                'Insufficient evidence: no supported scenario pattern is established. IRIS will not display generic accident possibilities.',
              ),
            ),
          if (workspace.analysis?.state == ScenarioAnalysisState.available)
            for (final hypothesis in workspace.analysis!.hypotheses)
              _HypothesisCard(hypothesis: hypothesis, onInspect: _inspect),
          const SizedBox(height: IrisSpacing.sm),
          Wrap(
            spacing: IrisSpacing.sm,
            runSpacing: IrisSpacing.sm,
            children: [
              IrisSecondaryButton(
                label: 'Record observation',
                onPressed: workspace.evidence.isEmpty || _working
                    ? null
                    : _addObservation,
              ),
              IrisPrimaryButton(
                label: _working
                    ? 'Analyzing…'
                    : 'Generate evidence-grounded hypotheses',
                onPressed: _working ? null : _generate,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _HypothesisCard extends StatelessWidget {
  const _HypothesisCard({required this.hypothesis, required this.onInspect});
  final AccidentScenarioHypothesis hypothesis;
  final Future<void> Function(String) onInspect;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: IrisSpacing.sm),
    child: IrisCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hypothesis.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text('HYPOTHESIS — not established fact'),
          const SizedBox(height: IrisSpacing.xs),
          Text('Possible sequence: ${hypothesis.possibleSequence}'),
          _lines('Contradictory observations', hypothesis.contradictions),
          _lines('Missing information', hypothesis.missingInformation),
          _lines('Alternative explanations', hypothesis.alternatives),
          _lines(
            'Evidence needed for verification',
            hypothesis.verificationNeeded,
          ),
          const SizedBox(height: IrisSpacing.xs),
          const Text('Supporting evidence:'),
          Wrap(
            children: hypothesis.supportingEvidenceIds
                .map(
                  (id) => TextButton(
                    onPressed: () => onInspect(id),
                    child: const Text('Inspect evidence'),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    ),
  );

  Widget _lines(String title, List<String> values) => Padding(
    padding: const EdgeInsets.only(top: IrisSpacing.xs),
    child: Text(
      '$title: ${values.isEmpty ? 'None identified' : values.join('; ')}',
    ),
  );
}
