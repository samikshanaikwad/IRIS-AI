import 'package:flutter/material.dart';

class IrisPrimaryButton extends StatelessWidget {
  const IrisPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.semanticLabel,
    this.expand = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final String? semanticLabel;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final Widget button = icon == null
        ? FilledButton(onPressed: onPressed, child: Text(label))
        : FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          );

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel ?? label,
      child: SizedBox(width: expand ? double.infinity : null, child: button),
    );
  }
}

class IrisSecondaryButton extends StatelessWidget {
  const IrisSecondaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.semanticLabel,
    this.expand = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final String? semanticLabel;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final Widget button = icon == null
        ? OutlinedButton(onPressed: onPressed, child: Text(label))
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          );

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel ?? label,
      child: SizedBox(width: expand ? double.infinity : null, child: button),
    );
  }
}
