import 'package:flutter/material.dart';

import '../../../../app/theme/iris_colors.dart';
import '../../../../app/theme/iris_spacing.dart';
import '../../../../app/theme/iris_typography.dart';
import '../../../../core/widgets/iris_card.dart';
import '../../../../core/widgets/iris_status_chip.dart';
import '../../domain/incident_case.dart';
import '../case_date_formatter.dart';

class CaseCard extends StatelessWidget {
  const CaseCard({
    required this.incidentCase,
    required this.onTap,
    this.compact = false,
    super.key,
  });

  final IncidentCase incidentCase;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return IrisCard(
      onTap: onTap,
      semanticLabel:
          '${incidentCase.title}. ${incidentCase.status.displayLabel}. '
          'Updated ${formatCaseTimestamp(incidentCase.updatedAt)}.',
      padding: EdgeInsets.all(compact ? IrisSpacing.sm : IrisSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          const Icon(
            Icons.folder_outlined,
            color: IrisColors.primaryBlueLight,
            size: 26,
          ),
          const SizedBox(width: IrisSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  incidentCase.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: IrisSpacing.xs),
                Wrap(
                  spacing: IrisSpacing.xs,
                  runSpacing: IrisSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    IrisStatusChip(label: incidentCase.status.displayLabel),
                    Text(
                      'Updated ${formatCaseTimestamp(incidentCase.updatedAt)}',
                      style: IrisTypography.technicalValue.copyWith(
                        color: IrisColors.mutedText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: IrisSpacing.xs),
          const Icon(Icons.chevron_right, color: IrisColors.mutedText),
        ],
      ),
    );
  }
}
