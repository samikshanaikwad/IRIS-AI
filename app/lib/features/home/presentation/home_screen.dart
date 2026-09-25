import 'package:flutter/material.dart';

import '../../../app/theme/iris_colors.dart';
import '../../../app/theme/iris_radius.dart';
import '../../../app/theme/iris_spacing.dart';
import '../../../core/widgets/iris_button.dart';
import '../../../core/widgets/iris_card.dart';
import '../../../core/widgets/iris_empty_state.dart';
import '../../../core/widgets/iris_page_body.dart';
import '../../../core/widgets/iris_section_header.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.onAnalyzeIncident, super.key});

  final VoidCallback onAnalyzeIncident;

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
                  Icons.view_in_ar_outlined,
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
                        'IRIS',
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: IrisSpacing.xxs),
                      Text(
                        'Incident Reconstruction & Intelligence System',
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
                  'Start by adding real scene evidence. Evidence acquisition '
                  'will become available in a later implementation phase.',
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
          const IrisEmptyState(
            icon: Icons.folder_open_outlined,
            title: 'No cases yet',
            message: 'Incident cases will appear here after they are created.',
          ),
        ],
      ),
    );
  }
}
