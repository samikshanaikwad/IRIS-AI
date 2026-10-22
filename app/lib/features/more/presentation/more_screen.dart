import 'package:flutter/material.dart';

import '../../../app/theme/iris_colors.dart';
import '../../../app/theme/iris_spacing.dart';
import '../../../core/widgets/iris_app_bar.dart';
import '../../../core/widgets/iris_card.dart';
import '../../../core/widgets/iris_page_body.dart';
import '../../../core/widgets/iris_section_header.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const IrisAppBar(title: 'More'),
      body: IrisPageBody(
        children: <Widget>[
          const IrisSectionHeader(title: 'About AEGIS AI'),
          const SizedBox(height: IrisSpacing.sm),
          IrisCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.shield_outlined,
                  color: IrisColors.primaryBlueLight,
                  size: 28,
                ),
                const SizedBox(height: IrisSpacing.sm),
                Text('AEGIS AI', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: IrisSpacing.xxs),
                Text(
                  'Intelligent Road Accident Evidence Analysis System',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: IrisSpacing.sm),
                Text(
                  'Image-based road accident evidence management and analysis. AI findings require verification.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: IrisSpacing.lg),
          const IrisSectionHeader(title: 'Application options'),
          const SizedBox(height: IrisSpacing.sm),
          const IrisCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.settings_outlined, color: IrisColors.secondaryText),
                SizedBox(width: IrisSpacing.sm),
                Expanded(
                  child: Text(
                    'Settings, privacy controls, and model information will '
                    'appear here when their underlying capabilities are '
                    'implemented.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
