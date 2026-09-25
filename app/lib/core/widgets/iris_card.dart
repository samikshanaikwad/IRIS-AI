import 'package:flutter/material.dart';

import '../../app/theme/iris_colors.dart';
import '../../app/theme/iris_radius.dart';
import '../../app/theme/iris_spacing.dart';

class IrisCard extends StatelessWidget {
  const IrisCard({
    required this.child,
    this.padding = const EdgeInsets.all(IrisSpacing.md),
    this.elevated = false,
    this.onTap,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool elevated;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Widget content = Padding(padding: padding, child: child);

    return Semantics(
      container: true,
      label: semanticLabel,
      button: onTap != null,
      child: Card(
        color: elevated ? IrisColors.elevatedCard : IrisColors.card,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: IrisColors.subtleBorder),
          borderRadius: BorderRadius.circular(IrisRadius.card),
        ),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}
