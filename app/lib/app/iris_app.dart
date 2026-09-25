import 'package:flutter/material.dart';

import '../features/foundation/presentation/foundation_screen.dart';

class IrisApp extends StatelessWidget {
  const IrisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IRIS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const FoundationScreen(),
    );
  }
}
