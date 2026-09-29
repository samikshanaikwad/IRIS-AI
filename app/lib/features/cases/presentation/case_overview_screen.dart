import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/iris_colors.dart';
import '../../../app/theme/iris_spacing.dart';
import '../../../app/theme/iris_typography.dart';
import '../../../core/widgets/iris_app_bar.dart';
import '../../../core/widgets/iris_async_states.dart';
import '../../../core/widgets/iris_card.dart';
import '../../../core/widgets/iris_page_body.dart';
import '../../../core/widgets/iris_section_header.dart';
import '../../../core/widgets/iris_status_chip.dart';
import '../application/case_controller.dart';
import '../domain/incident_case.dart';
import '../../evidence/application/evidence_controller.dart';
import '../../evidence/presentation/case_evidence_section.dart';
import '../../evidence_quality/application/evidence_quality_service.dart';
import '../../classification/application/evidence_classification_service.dart';
import '../../detection/application/evidence_detection_service.dart';
import '../../depth/application/evidence_depth_service.dart';
import '../../geometry/application/relative_geometry_service.dart';
import 'case_date_formatter.dart';
import 'case_title_sheet.dart';
import '../../multiview/application/multiview_service.dart';
import '../../multiview/presentation/multiview_section.dart';
import '../../location/application/case_location_service.dart';
import '../../location/presentation/location_section.dart';

class CaseOverviewScreen extends StatefulWidget {
  const CaseOverviewScreen({
    required this.caseId,
    required this.caseController,
    required this.evidenceController,
    required this.evidenceQuality,
    required this.evidenceClassification,
    required this.evidenceDetection,
    required this.evidenceDepth,
    required this.relativeGeometry,
    required this.multiView,
    required this.location,
    super.key,
  });

  final String caseId;
  final CaseController caseController;
  final EvidenceController evidenceController;
  final EvidenceQualityOperations evidenceQuality;
  final EvidenceClassificationOperations evidenceClassification;
  final EvidenceDetectionOperations evidenceDetection;
  final EvidenceDepthOperations evidenceDepth;
  final RelativeGeometryOperations relativeGeometry;
  final MultiViewService multiView;
  final CaseLocationService location;

  @override
  State<CaseOverviewScreen> createState() => _CaseOverviewScreenState();
}

class _CaseOverviewScreenState extends State<CaseOverviewScreen> {
  IncidentCase? _incidentCase;
  bool _loading = true;
  bool _loadFailed = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCase());
  }

  Future<void> _loadCase() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final IncidentCase? incidentCase = await widget.caseController
          .getCaseById(widget.caseId);
      if (!mounted) {
        return;
      }
      setState(() {
        _incidentCase = incidentCase;
        _loading = false;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _incidentCase = null;
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _renameCase() async {
    final IncidentCase? current = _incidentCase;
    if (current == null) {
      return;
    }
    final IncidentCase? renamed = await showCaseTitleSheet(
      context: context,
      heading: 'Rename case',
      submitLabel: 'Save title',
      initialTitle: current.title,
      onSubmit: (String title) {
        return widget.caseController.renameCase(id: current.id, title: title);
      },
    );
    if (renamed != null && mounted) {
      setState(() {
        _incidentCase = renamed;
      });
    }
  }

  Future<void> _requestDeletion() async {
    final IncidentCase? current = _incidentCase;
    if (current == null || _deleting) {
      return;
    }

    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Delete case?'),
              content: Text(
                'Delete “${current.title}”? This permanently removes the case, '
                'its stored evidence copies, and related metadata from this device.',
              ),
              actions: <Widget>[
                TextButton(
                  key: const ValueKey<String>('cancel-delete-button'),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  key: const ValueKey<String>('confirm-delete-button'),
                  style: TextButton.styleFrom(
                    foregroundColor: IrisColors.danger,
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _deleting = true;
    });
    try {
      final bool deleted = await widget.caseController.deleteCase(current.id);
      if (!mounted) {
        return;
      }
      if (!deleted) {
        throw StateError('Case record no longer exists.');
      }
      Navigator.of(context).pop();
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _deleting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The case could not be deleted. Try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final IncidentCase? incidentCase = _incidentCase;
    return Scaffold(
      appBar: IrisAppBar(
        title: 'Case Overview',
        actions: incidentCase == null
            ? null
            : <Widget>[
                IconButton(
                  key: const ValueKey<String>('rename-case-button'),
                  tooltip: 'Rename case',
                  onPressed: _deleting ? null : _renameCase,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  key: const ValueKey<String>('delete-case-button'),
                  tooltip: 'Delete case',
                  onPressed: _deleting ? null : _requestDeletion,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
      ),
      body: _buildBody(incidentCase),
    );
  }

  Widget _buildBody(IncidentCase? incidentCase) {
    if (_loading) {
      return const IrisPageBody(
        children: <Widget>[IrisLoadingState(label: 'Loading case')],
      );
    }
    if (_loadFailed) {
      return IrisPageBody(
        children: <Widget>[
          IrisErrorState(
            title: 'Case unavailable',
            message: 'IRIS could not read this case from local storage.',
            onRetry: _loadCase,
          ),
        ],
      );
    }
    if (incidentCase == null) {
      return IrisPageBody(
        children: <Widget>[
          IrisErrorState(
            title: 'Case not found',
            message: 'This case record is no longer available on this device.',
            onRetry: _loadCase,
          ),
        ],
      );
    }

    return IrisPageBody(
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            incidentCase.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: IrisSpacing.sm),
        Wrap(
          spacing: IrisSpacing.xs,
          runSpacing: IrisSpacing.xs,
          children: <Widget>[
            IrisStatusChip(label: incidentCase.status.displayLabel),
          ],
        ),
        const SizedBox(height: IrisSpacing.md),
        IrisCard(
          child: Column(
            children: <Widget>[
              _CaseMetadataRow(
                label: 'Created',
                value: formatCaseTimestamp(incidentCase.createdAt),
              ),
              const Divider(height: IrisSpacing.md),
              _CaseMetadataRow(
                label: 'Updated',
                value: formatCaseTimestamp(incidentCase.updatedAt),
              ),
            ],
          ),
        ),
        const SizedBox(height: IrisSpacing.lg),
        const IrisSectionHeader(
          title: 'Case workflow',
          supportingText: 'Only persisted or currently known states are shown.',
        ),
        const SizedBox(height: IrisSpacing.sm),
        CaseEvidenceSection(
          controller: widget.evidenceController,
          qualityOperations: widget.evidenceQuality,
          classificationOperations: widget.evidenceClassification,
          detectionOperations: widget.evidenceDetection,
          depthOperations: widget.evidenceDepth,
          geometryOperations: widget.relativeGeometry,
        ),
        const SizedBox(height: IrisSpacing.lg),
        MultiViewSection(controller: widget.evidenceController, service: widget.multiView),
        const SizedBox(height: IrisSpacing.lg),
        LocationSection(caseId: widget.caseId, controller: widget.evidenceController, service: widget.location),
        const SizedBox(height: IrisSpacing.md),
        const _WorkflowState(
          icon: Icons.location_off_outlined,
          title: 'Location',
          state: 'Not set',
        ),
        const SizedBox(height: IrisSpacing.sm),
        const _WorkflowState(
          icon: Icons.view_in_ar_outlined,
          title: 'Reconstruction',
          state: 'Not available until evidence is analyzed',
        ),
        const SizedBox(height: IrisSpacing.sm),
        const _WorkflowState(
          icon: Icons.alt_route_outlined,
          title: 'Scenarios',
          state: 'Not generated',
        ),
        const SizedBox(height: IrisSpacing.sm),
        const _WorkflowState(
          icon: Icons.calculate_outlined,
          title: 'Physics',
          state: 'Not evaluated',
        ),
        const SizedBox(height: IrisSpacing.sm),
        const _WorkflowState(
          icon: Icons.description_outlined,
          title: 'Report',
          state: 'Not generated',
        ),
      ],
    );
  }
}

class _CaseMetadataRow extends StatelessWidget {
  const _CaseMetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(width: IrisSpacing.sm),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: IrisTypography.technicalValue,
          ),
        ),
      ],
    );
  }
}

class _WorkflowState extends StatelessWidget {
  const _WorkflowState({
    required this.icon,
    required this.title,
    required this.state,
  });

  final IconData icon;
  final String title;
  final String state;

  @override
  Widget build(BuildContext context) {
    return IrisCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: IrisColors.secondaryText),
          const SizedBox(width: IrisSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: IrisSpacing.xxs),
                Text(state, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
