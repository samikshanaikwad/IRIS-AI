import 'package:flutter/material.dart';

import '../../../app/theme/iris_colors.dart';
import '../../../app/theme/iris_spacing.dart';
import '../../../core/widgets/iris_app_bar.dart';
import '../../../core/widgets/iris_button.dart';
import '../../../core/widgets/iris_card.dart';
import '../../../core/widgets/iris_page_body.dart';
import '../../../core/widgets/iris_section_header.dart';

class CaptureScreen extends StatelessWidget {
  const CaptureScreen({
    required this.onSelectCase,
    required this.onCreateCase,
    super.key,
  });

  final VoidCallback onSelectCase;
  final VoidCallback onCreateCase;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const IrisAppBar(title: 'Evidence Capture'),
      body: IrisPageBody(
        children: <Widget>[
          const IrisSectionHeader(
            title: 'Select a case first',
            supportingText:
                'Evidence is stored inside an incident case so files cannot become orphaned.',
          ),
          SizedBox(height: IrisSpacing.sm),
          IrisCard(
            child: Column(
              children: <Widget>[
                const Icon(Icons.folder_open_outlined, size: 36),
                const SizedBox(height: IrisSpacing.sm),
                const Text(
                  'Open an existing case to capture or import evidence, or create a new incident case.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: IrisSpacing.md),
                IrisPrimaryButton(
                  key: const ValueKey<String>('capture-select-case-button'),
                  label: 'Select Existing Case',
                  icon: Icons.folder_open_outlined,
                  onPressed: onSelectCase,
                ),
                const SizedBox(height: IrisSpacing.xs),
                IrisSecondaryButton(
                  key: const ValueKey<String>('capture-create-case-button'),
                  label: 'Create Incident Case',
                  icon: Icons.add,
                  onPressed: onCreateCase,
                ),
              ],
            ),
          ),
          SizedBox(height: IrisSpacing.lg),
          const IrisSectionHeader(
            title: 'Evidence guidance',
            supportingText:
                'When capture becomes available, include views that document:',
          ),
          SizedBox(height: IrisSpacing.sm),
          const IrisCard(
            child: Column(
              children: <Widget>[
                _GuidanceItem(
                  icon: Icons.landscape_outlined,
                  text: 'The wider scene and road layout',
                ),
                Divider(height: IrisSpacing.md),
                _GuidanceItem(
                  icon: Icons.car_crash_outlined,
                  text: 'Vehicle positions and visible damage',
                ),
                Divider(height: IrisSpacing.md),
                _GuidanceItem(
                  icon: Icons.search,
                  text: 'Road marks, debris, and relevant scene details',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuidanceItem extends StatelessWidget {
  const _GuidanceItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, color: IrisColors.secondaryText, size: 20),
        const SizedBox(width: IrisSpacing.sm),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}
