import 'package:flutter/material.dart';

import '../../app/theme/iris_colors.dart';
import '../../app/theme/iris_spacing.dart';
import 'iris_button.dart';
import 'iris_card.dart';

class IrisEmptyState extends StatelessWidget {
  const IrisEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return IrisCard(
      semanticLabel: '$title. $message',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: IrisColors.elevatedCard,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: IrisColors.primaryBlueLight, size: 28),
          ),
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
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(height: IrisSpacing.md),
            IrisPrimaryButton(label: actionLabel!, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}
