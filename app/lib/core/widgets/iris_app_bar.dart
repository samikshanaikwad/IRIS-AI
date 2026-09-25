import 'package:flutter/material.dart';

class IrisAppBar extends StatelessWidget implements PreferredSizeWidget {
  const IrisAppBar({required this.title, this.actions, super.key});

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title, style: Theme.of(context).textTheme.headlineSmall),
      actions: actions,
    );
  }
}
