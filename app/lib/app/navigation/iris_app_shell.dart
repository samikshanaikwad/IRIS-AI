import 'package:flutter/material.dart';

import '../iris_application_services.dart';
import '../../features/capture/presentation/capture_screen.dart';
import '../../features/cases/presentation/cases_screen.dart';
import '../../features/cases/application/case_controller.dart';
import '../../features/cases/domain/incident_case.dart';
import '../../features/cases/presentation/case_overview_screen.dart';
import '../../features/cases/presentation/case_title_sheet.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/more/presentation/more_screen.dart';
import 'iris_navigation.dart';

class IrisAppShell extends StatefulWidget {
  const IrisAppShell({
    required this.caseController,
    required this.services,
    super.key,
  });

  final CaseController caseController;
  final IrisApplicationServices services;

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

  Future<void> _createCase() async {
    final IncidentCase? incidentCase = await showCaseTitleSheet(
      context: context,
      heading: 'Create incident case',
      submitLabel: 'Create Case',
      onSubmit: widget.caseController.createCase,
    );
    if (incidentCase != null && mounted) {
      _openCase(incidentCase.id);
    }
  }

  void _openCase(String caseId) {
    final evidenceQuality = widget.services.evidenceQuality;
    final evidenceClassification = widget.services.evidenceClassification;
    final evidenceDetection = widget.services.evidenceDetection;
    final evidenceDepth = widget.services.evidenceDepth;
    if (evidenceQuality == null ||
        evidenceClassification == null ||
        evidenceDetection == null || evidenceDepth == null) {
      throw StateError('Evidence quality services are not configured.');
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return CaseOverviewScreen(
            caseId: caseId,
            caseController: widget.caseController,
            evidenceController: widget.services.evidenceControllerFor(caseId),
            evidenceQuality: evidenceQuality,
            evidenceClassification: evidenceClassification,
            evidenceDetection: evidenceDetection,
            evidenceDepth: evidenceDepth,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = <Widget>[
      HomeScreen(
        caseController: widget.caseController,
        onAnalyzeIncident: _createCase,
        onOpenCase: _openCase,
        onViewCases: () => _selectDestination(IrisDestination.cases),
      ),
      CasesScreen(
        caseController: widget.caseController,
        onStartAnalysis: _createCase,
        onOpenCase: _openCase,
      ),
      CaptureScreen(
        onSelectCase: () => _selectDestination(IrisDestination.cases),
        onCreateCase: _createCase,
      ),
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
