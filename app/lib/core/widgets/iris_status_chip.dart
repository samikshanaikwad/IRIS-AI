import 'package:flutter/material.dart';

import '../../app/theme/iris_colors.dart';
import '../../app/theme/iris_radius.dart';
import '../../app/theme/iris_spacing.dart';

enum IrisStatusTone { neutral, success, warning, danger }

class IrisStatusChip extends StatelessWidget {
  const IrisStatusChip({
    required this.label,
    this.tone = IrisStatusTone.neutral,
    this.icon,
    super.key,
  });

  final String label;
  final IrisStatusTone tone;
  final IconData? icon;

  Color get _color => switch (tone) {
    IrisStatusTone.neutral => IrisColors.secondaryText,
    IrisStatusTone.success => IrisColors.success,
    IrisStatusTone.warning => IrisColors.warning,
    IrisStatusTone.danger => IrisColors.danger,
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _color.withValues(alpha: 0.1),
          border: Border.all(color: _color.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(IrisRadius.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: IrisSpacing.xs,
            vertical: IrisSpacing.xxs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, color: _color, size: 14),
                const SizedBox(width: IrisSpacing.xxs),
              ],
              Flexible(
                child: Text(
                  label,
                  softWrap: true,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: _color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
