import 'package:flutter/material.dart';

class FoundationScreen extends StatelessWidget {
  const FoundationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('IRIS'),
              SizedBox(height: 12),
              Text('Incident Reconstruction & Intelligence System'),
              SizedBox(height: 12),
              Text('Foundation initialized'),
            ],
          ),
        ),
      ),
    );
  }
}
