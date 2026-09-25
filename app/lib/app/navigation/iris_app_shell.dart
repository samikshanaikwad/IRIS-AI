import 'package:flutter/material.dart';

import '../../features/capture/presentation/capture_screen.dart';
import '../../features/cases/presentation/cases_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/more/presentation/more_screen.dart';
import 'iris_navigation.dart';

class IrisAppShell extends StatefulWidget {
  const IrisAppShell({super.key});

  @override
  State<IrisAppShell> createState() => _IrisAppShellState();
}

class _IrisAppShellState extends State<IrisAppShell> {
  int _selectedIndex = IrisDestination.home.index;

  void _selectDestination(IrisDestination destination) {
    if (_selectedIndex == destination.index) {
      return;
    }

    setState(() {
      _selectedIndex = destination.index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = <Widget>[
      HomeScreen(
        onAnalyzeIncident: () => _selectDestination(IrisDestination.capture),
      ),
      CasesScreen(
        onStartAnalysis: () => _selectDestination(IrisDestination.capture),
      ),
      const CaptureScreen(),
      const MoreScreen(),
    ];

    return PopScope<void>(
      canPop: _selectedIndex == IrisDestination.home.index,
      onPopInvokedWithResult: (bool didPop, void result) {
        if (!didPop) {
          _selectDestination(IrisDestination.home);
        }
      },
      child: Scaffold(
        body: IndexedStack(index: _selectedIndex, children: screens),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (int index) {
            _selectDestination(IrisDestination.values[index]);
          },
          destinations: IrisDestination.values
              .map((destination) {
                return NavigationDestination(
                  key: ValueKey<String>('nav-${destination.name}'),
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(destination.selectedIcon),
                  label: destination.label,
                  tooltip: destination.label,
                );
              })
              .toList(growable: false),
        ),
      ),
    );
  }
}
