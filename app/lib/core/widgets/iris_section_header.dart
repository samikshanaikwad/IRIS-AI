import 'package:flutter/material.dart';

import '../../app/theme/iris_colors.dart';

class IrisSectionHeader extends StatelessWidget {
  const IrisSectionHeader({
    required this.title,
    this.supportingText,
    super.key,
  });

  final String title;
  final String? supportingText;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (supportingText != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              supportingText!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: IrisColors.mutedText),
            ),
          ],
        ],
      ),
    );
  }
}
