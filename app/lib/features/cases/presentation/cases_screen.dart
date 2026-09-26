import 'package:flutter/material.dart';

import '../../../core/widgets/iris_app_bar.dart';
import '../../../core/widgets/iris_async_states.dart';
import '../../../core/widgets/iris_empty_state.dart';
import '../../../core/widgets/iris_page_body.dart';
import '../../../core/widgets/iris_section_header.dart';
import '../../../app/theme/iris_spacing.dart';
import '../application/case_controller.dart';
import '../domain/incident_case.dart';
import 'widgets/case_card.dart';

class CasesScreen extends StatelessWidget {
  const CasesScreen({
    required this.caseController,
    required this.onStartAnalysis,
    required this.onOpenCase,
    super.key,
  });

  final CaseController caseController;
  final VoidCallback onStartAnalysis;
  final ValueChanged<String> onOpenCase;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const IrisAppBar(title: 'Cases'),
      body: AnimatedBuilder(
        animation: caseController,
        builder: (BuildContext context, Widget? child) {
          return IrisPageBody(children: <Widget>[_buildCases(context)]);
        },
      ),
    );
  }

  Widget _buildCases(BuildContext context) {
    switch (caseController.state) {
      case CaseCollectionState.loading:
        return const IrisLoadingState(label: 'Loading cases');
      case CaseCollectionState.error:
        return IrisErrorState(
          title: 'Cases unavailable',
          message: 'IRIS could not read cases from local storage.',
          onRetry: caseController.retry,
        );
      case CaseCollectionState.data:
        final List<IncidentCase> cases = caseController.cases;
        if (cases.isEmpty) {
          return IrisEmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'No incident cases',
            message: 'Cases you create will appear here.',
            actionLabel: 'Start Incident Analysis',
            onAction: onStartAnalysis,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const IrisSectionHeader(
              title: 'Incident cases',
              supportingText: 'Most recently updated cases appear first.',
            ),
            const SizedBox(height: IrisSpacing.sm),
            for (int index = 0; index < cases.length; index++) ...<Widget>[
              CaseCard(
                key: ValueKey<String>('cases-case-${cases[index].id}'),
                incidentCase: cases[index],
                onTap: () => onOpenCase(cases[index].id),
              ),
              if (index != cases.length - 1)
                const SizedBox(height: IrisSpacing.sm),
            ],
          ],
        );
    }
  }
}
