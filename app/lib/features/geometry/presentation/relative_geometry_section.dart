import 'package:flutter/material.dart';
import '../../../core/widgets/iris_card.dart';
import '../../../core/widgets/iris_button.dart';
import '../../../app/theme/iris_spacing.dart';
import '../application/relative_geometry_controller.dart';
import 'relative_geometry_viewer.dart';

class RelativeGeometrySection extends StatelessWidget { const RelativeGeometrySection({required this.controller, super.key}); final RelativeGeometryController controller;
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: controller, builder: (context, _) { final g = controller.geometry; return IrisCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('RELATIVE SCENE GEOMETRY', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: IrisSpacing.xs), Text(controller.busy ? 'Generating…' : g == null ? 'Not generated' : 'Generated'), if (g != null) ...[const Text('Representation: Relative 3D geometry'), const Text('Projection: Normalized / uncalibrated'), const Text('Scale: Unresolved'), Text('Points: ${g.points.length}'), const Text('Source: Persisted relative depth'), const SizedBox(height: IrisSpacing.sm), SizedBox(height: 220, child: RelativeGeometryViewer(geometry: g)), const Text('Scale unresolved • Relative geometry'), const Text('Relative spatial representation — not measured physical distance.')], if (controller.error != null) Text(controller.error!), const SizedBox(height: IrisSpacing.sm), IrisPrimaryButton(label: controller.busy ? 'Generating…' : g == null ? 'Generate Geometry' : 'Regenerate Geometry', icon: Icons.scatter_plot, onPressed: controller.busy ? null : controller.generate)])); });
}
