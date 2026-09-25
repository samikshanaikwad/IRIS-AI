import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'navigation/iris_app_shell.dart';
import 'theme/iris_colors.dart';
import 'theme/iris_theme.dart';

class IrisApp extends StatelessWidget {
  const IrisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IRIS',
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
      home: const IrisAppShell(),
    );
  }
}
