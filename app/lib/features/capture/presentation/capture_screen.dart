import 'package:flutter/material.dart';

import '../../../app/theme/iris_colors.dart';
import '../../../app/theme/iris_spacing.dart';
import '../../../core/widgets/iris_app_bar.dart';
import '../../../core/widgets/iris_button.dart';
import '../../../core/widgets/iris_card.dart';
import '../../../core/widgets/iris_page_body.dart';
import '../../../core/widgets/iris_section_header.dart';
import '../../../core/widgets/iris_status_chip.dart';

class CaptureScreen extends StatelessWidget {
  const CaptureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const IrisAppBar(title: 'Evidence Capture'),
      body: const IrisPageBody(
        children: <Widget>[
          IrisSectionHeader(
            title: 'Add scene evidence',
            supportingText: 'Add scene evidence to begin an incident analysis.',
          ),
          SizedBox(height: IrisSpacing.sm),
          _EvidenceActionCard(
            icon: Icons.photo_camera_outlined,
            title: 'Capture Scene',
            description: 'Use the device camera to record scene evidence.',
            buttonKey: ValueKey<String>('capture-scene-button'),
            primary: true,
          ),
          SizedBox(height: IrisSpacing.sm),
          _EvidenceActionCard(
            icon: Icons.file_upload_outlined,
            title: 'Import Evidence',
            description: 'Select existing evidence files from this device.',
            buttonKey: ValueKey<String>('import-evidence-button'),
            primary: false,
          ),
          SizedBox(height: IrisSpacing.lg),
          IrisSectionHeader(
            title: 'Evidence guidance',
            supportingText:
                'When capture becomes available, include views that document:',
          ),
          SizedBox(height: IrisSpacing.sm),
          IrisCard(
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

class _EvidenceActionCard extends StatelessWidget {
  const _EvidenceActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonKey,
    required this.primary,
  });

  final IconData icon;
  final String title;
  final String description;
  final Key buttonKey;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return IrisCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: IrisColors.primaryBlueLight, size: 26),
              const SizedBox(width: IrisSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: IrisSpacing.xxs),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: IrisSpacing.sm),
          const IrisStatusChip(
            label: 'Not available yet',
            icon: Icons.info_outline,
          ),
          const SizedBox(height: IrisSpacing.xs),
          Text(
            'Evidence acquisition controls will be enabled after camera and '
            'import setup.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: IrisSpacing.sm),
          if (primary)
            IrisPrimaryButton(
              key: buttonKey,
              label: title,
              icon: icon,
              onPressed: null,
            )
          else
            IrisSecondaryButton(
              key: buttonKey,
              label: title,
              icon: icon,
              onPressed: null,
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
