import 'package:flutter/material.dart';

import '../../app/theme/iris_colors.dart';
import '../../app/theme/iris_spacing.dart';
import 'iris_button.dart';
import 'iris_card.dart';

class IrisLoadingState extends StatelessWidget {
  const IrisLoadingState({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      liveRegion: true,
      child: const IrisCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(IrisSpacing.sm),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );
  }
}

class IrisErrorState extends StatelessWidget {
  const IrisErrorState({
    required this.title,
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return IrisCard(
      semanticLabel: '$title. $message',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.error_outline, color: IrisColors.danger, size: 32),
          const SizedBox(height: IrisSpacing.sm),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: IrisSpacing.xs),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: IrisSpacing.md),
          IrisSecondaryButton(
            label: 'Retry',
            icon: Icons.refresh,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
