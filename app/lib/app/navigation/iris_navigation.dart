import 'package:flutter/material.dart';

enum IrisDestination {
  home(label: 'Home', icon: Icons.home_outlined, selectedIcon: Icons.home),
  cases(
    label: 'Cases',
    icon: Icons.folder_open_outlined,
    selectedIcon: Icons.folder,
  ),
  capture(
    label: 'Capture',
    icon: Icons.add_a_photo_outlined,
    selectedIcon: Icons.add_a_photo,
  ),
  more(label: 'More', icon: Icons.more_horiz, selectedIcon: Icons.more_horiz);

  const IrisDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
