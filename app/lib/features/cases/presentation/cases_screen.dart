import 'package:flutter/material.dart';

import '../../../core/widgets/iris_app_bar.dart';
import '../../../core/widgets/iris_empty_state.dart';
import '../../../core/widgets/iris_page_body.dart';

class CasesScreen extends StatelessWidget {
  const CasesScreen({required this.onStartAnalysis, super.key});

  final VoidCallback onStartAnalysis;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const IrisAppBar(title: 'Cases'),
      body: IrisPageBody(
        children: <Widget>[
          IrisEmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'No incident cases',
            message: 'Cases you create will appear here.',
            actionLabel: 'Start Incident Analysis',
            onAction: onStartAnalysis,
          ),
        ],
      ),
    );
  }
}
