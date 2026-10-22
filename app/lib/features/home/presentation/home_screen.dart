import 'package:flutter/material.dart';

import '../../../app/theme/iris_colors.dart';
import '../../../app/theme/iris_radius.dart';
import '../../../app/theme/iris_spacing.dart';
import '../../../core/widgets/iris_button.dart';
import '../../../core/widgets/iris_async_states.dart';
import '../../../core/widgets/iris_card.dart';
import '../../../core/widgets/iris_empty_state.dart';
import '../../../core/widgets/iris_page_body.dart';
import '../../../core/widgets/iris_section_header.dart';
import '../../cases/application/case_controller.dart';
import '../../cases/domain/incident_case.dart';
import '../../cases/presentation/widgets/case_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.caseController,
    required this.onAnalyzeIncident,
    required this.onOpenCase,
    required this.onViewCases,
    this.onOpenSegmentationQualification,
    super.key,
  });

  final CaseController caseController;
  final VoidCallback onAnalyzeIncident;
  final ValueChanged<String> onOpenCase;
  final VoidCallback onViewCases;
  final VoidCallback? onOpenSegmentationQualification;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IrisPageBody(
        safeTop: true,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: IrisColors.elevatedCard,
                  border: Border.all(color: IrisColors.primaryBorder),
                  borderRadius: BorderRadius.circular(IrisRadius.button),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.shield_outlined,
                  color: IrisColors.primaryBlueLight,
                  size: 26,
                ),
              ),
              const SizedBox(width: IrisSpacing.sm),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'AEGIS AI',
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: IrisSpacing.xxs),
                      Text(
                        'Intelligent Road Accident Evidence Analysis System',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: IrisSpacing.lg),
          IrisCard(
            elevated: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.document_scanner_outlined,
                  color: IrisColors.primaryBlueLight,
                  size: 28,
                ),
                const SizedBox(height: IrisSpacing.sm),
                Text(
                  'Begin an incident analysis',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: IrisSpacing.xs),
                Text(
                  'Create a case to organize real incident evidence and '
                  'evidence observations on this device.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: IrisSpacing.md),
                IrisPrimaryButton(
                  key: const ValueKey<String>('analyze-incident-button'),
                  label: 'Analyze Incident',
                  icon: Icons.arrow_forward,
                  onPressed: onAnalyzeIncident,
                ),
              ],
            ),
          ),
          const SizedBox(height: IrisSpacing.lg),
          const IrisSectionHeader(
            title: 'Recent cases',
            supportingText: 'Your incident work will be organized here.',
          ),
          const SizedBox(height: IrisSpacing.sm),
          AnimatedBuilder(
            animation: caseController,
            builder: (BuildContext context, Widget? child) {
              return _buildRecentCases(context);
            },
          ),
          if (onOpenSegmentationQualification != null) ...<Widget>[
            const SizedBox(height: IrisSpacing.lg),
            IrisCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Development qualification',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: IrisSpacing.xs),
                  const Text(
                    'Run governed public images through the real detector and segmentation candidate. Debug builds only.',
                  ),
                  const SizedBox(height: IrisSpacing.sm),
                  IrisSecondaryButton(
                    key: const ValueKey<String>(
                      'open-public-segmentation-qualification',
                    ),
                    label: 'Open segmentation qualification',
                    icon: Icons.science_outlined,
                    onPressed: onOpenSegmentationQualification,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentCases(BuildContext context) {
    switch (caseController.state) {
      case CaseCollectionState.loading:
        return const IrisLoadingState(label: 'Loading recent cases');
      case CaseCollectionState.error:
        return IrisErrorState(
          title: 'Recent cases unavailable',
          message: 'AEGIS AI could not read cases from local storage.',
          onRetry: caseController.retry,
        );
      case CaseCollectionState.data:
        final List<IncidentCase> recentCases = caseController.cases
            .take(3)
            .toList(growable: false);
        if (recentCases.isEmpty) {
          return const IrisEmptyState(
            icon: Icons.folder_open_outlined,
            title: 'No cases yet',
            message: 'Incident cases will appear here after they are created.',
          );
        }

        return Column(
          children: <Widget>[
            for (
              int index = 0;
              index < recentCases.length;
              index++
            ) ...<Widget>[
              CaseCard(
                key: ValueKey<String>('home-case-${recentCases[index].id}'),
                incidentCase: recentCases[index],
                compact: true,
                onTap: () => onOpenCase(recentCases[index].id),
              ),
              if (index != recentCases.length - 1)
                const SizedBox(height: IrisSpacing.sm),
            ],
            const SizedBox(height: IrisSpacing.sm),
            IrisSecondaryButton(
              label: 'View all cases',
              icon: Icons.folder_open_outlined,
              onPressed: onViewCases,
            ),
          ],
        );
    }
  }
}
