import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/cases/application/case_controller.dart';
import 'iris_application_services.dart';
import 'navigation/iris_app_shell.dart';
import 'theme/iris_colors.dart';
import 'theme/iris_theme.dart';

class IrisApp extends StatefulWidget {
  const IrisApp({this.services, super.key});

  final IrisApplicationServices? services;

  @override
  State<IrisApp> createState() => _IrisAppState();
}

class _IrisAppState extends State<IrisApp> {
  late final bool _ownsServices;
  late final IrisApplicationServices _services;
  late final CaseController _caseController;

  @override
  void initState() {
    super.initState();
    _ownsServices = widget.services == null;
    _services = widget.services ?? IrisApplicationServices.production();
    _caseController = CaseController(_services.caseRepository);
    unawaited(_caseController.loadCases());
  }

  @override
  void dispose() {
    _caseController.dispose();
    if (_ownsServices) {
      unawaited(_services.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AEGIS AI',
      debugShowCheckedModeBanner: false,
      theme: IrisTheme.dark,
      darkTheme: IrisTheme.dark,
      themeMode: ThemeMode.dark,
      builder: (BuildContext context, Widget? child) {
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            systemNavigationBarColor: IrisColors.elevatedBackground,
            systemNavigationBarIconBrightness: Brightness.light,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: IrisAppShell(caseController: _caseController, services: _services),
    );
  }
}
