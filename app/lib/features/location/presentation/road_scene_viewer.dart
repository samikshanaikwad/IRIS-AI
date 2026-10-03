import 'package:flutter/material.dart';
import '../application/case_location_service.dart';
import '../../geometry/application/relative_geometry_service.dart';
import '../../geometry/application/evidence_world_alignment_service.dart';
import '../../detection/application/evidence_detection_service.dart';
import '../../evidence/application/evidence_controller.dart';
import '../../evidence_quality/application/evidence_quality_service.dart';
import '../../classification/application/evidence_classification_service.dart';
import '../../depth/application/evidence_depth_service.dart';
import '../../multiview/application/multiview_service.dart';
import '../../reconstruction/application/reconstruction_scene_service.dart';
import '../../reconstruction/domain/reconstruction_scene.dart';
import '../../reconstruction/presentation/scene_render_data.dart';
import '../../reconstruction/presentation/reconstruction_painter.dart';

class RoadSceneSection extends StatefulWidget {
  const RoadSceneSection({
    required this.caseId,
    required this.service,
    this.evidenceController,
    this.geometry,
    this.alignmentService,
    this.detection,
    this.quality,
    this.classification,
    this.depth,
    this.multiView,
    super.key,
  });
  final String caseId;
  final CaseLocationService service;
  final EvidenceController? evidenceController;
  final RelativeGeometryOperations? geometry;
  final EvidenceWorldAlignmentService? alignmentService;
  final EvidenceDetectionOperations? detection;
  final EvidenceQualityOperations? quality;
  final EvidenceClassificationOperations? classification;
  final EvidenceDepthOperations? depth;
  final MultiViewService? multiView;
  @override
  State<RoadSceneSection> createState() => _RoadSceneSectionState();
}

class _RoadSceneSectionState extends State<RoadSceneSection> {
  bool loading = false;
  Future<void> open() async {
    setState(() => loading = true);
    try {
      final loader = ReconstructionSceneService(
        location: widget.service,
        loadEvidence: () async {
          final controller = widget.evidenceController;
          await controller?.load();
          if (controller?.failed == true) {
            throw StateError('Evidence could not be loaded');
          }
          return controller?.items ?? [];
        },
        geometry: widget.geometry,
        alignment: widget.alignmentService,
        detection: widget.detection,
        quality: widget.quality,
        classification: widget.classification,
        depth: widget.depth,
        multiView: widget.multiView,
      );
      final scene = await loader.load(widget.caseId);
      if (!mounted) return;
      if (!scene.hasWorld) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              scene.location == null
                  ? '3D road environment unavailable — incident location not established.'
                  : 'Road environment unavailable — no current map-derived road geometry.',
            ),
          ),
        );
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RoadSceneViewer(
            scene: scene,
            loader: loader,
            service: widget.service,
          ),
        ),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Reconstruction source data unavailable. Please reopen the case.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '3D RECONSTRUCTION',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Real map context and applicable evidence. Placement and scale remain user supplied.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: loading ? null : open,
            icon: const Icon(Icons.view_in_ar),
            label: Text(loading ? 'Loading scene…' : 'Open 3D Reconstruction'),
          ),
        ],
      ),
    ),
  );
}

/// Camera gesture baseline is captured once per gesture, not multiplied into
/// every cumulative pinch update.
double sceneGestureZoom(double baseline, double cumulativeScale) =>
    (baseline * cumulativeScale).clamp(.2, 10);

class RoadSceneViewer extends StatefulWidget {
  const RoadSceneViewer({
    required this.scene,
    required this.loader,
    required this.service,
    super.key,
  });
  final ReconstructionScene scene;
  final ReconstructionSceneService loader;
  final CaseLocationService service;
  @override
  State<RoadSceneViewer> createState() => _RoadSceneViewerState();
}

class _RoadSceneViewerState extends State<RoadSceneViewer> {
  late ReconstructionScene scene;
  late SceneRenderData render;
  ReconstructionPainter? painter;
  double yaw = .5, pitch = -.62, zoom = 1, gestureZoom = 1;
  Offset pan = Offset.zero;
  bool analysis = false,
      evidence = false,
      centerlines = false,
      grid = false,
      environment = true;
  bool refreshing = false;
  @override
  void initState() {
    super.initState();
    scene = widget.scene;
    render = SceneRenderData(scene);
  }

  void reset() => setState(() {
    yaw = .5;
    pitch = -.62;
    zoom = 1;
    gestureZoom = 1;
    pan = Offset.zero;
  });
  Future<void> refresh() async {
    setState(() => refreshing = true);
    try {
      await widget.service.refreshEnvironment(scene.caseId);
      final next = await widget.loader.load(scene.caseId);
      if (!mounted) return;
      setState(() {
        scene = next;
        render = SceneRenderData(next);
      });
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Refresh unavailable. Last loaded scene retained; reopen if location has changed.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  void inspect(Offset point) {
    final mesh = painter?.objectAt(point);
    if (mesh == null) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(mesh.label, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(mesh.provenance),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final env = scene.environment;
    final countLabel = env?.hasVerifiedResult == true
        ? 'Buildings: ${env!.count('building')} • Trees: ${env.count('tree')} • Barriers: ${env.count('barrier')}'
        : 'Mapped environment unavailable — refresh to retrieve';
    return Scaffold(
      appBar: AppBar(
        title: const Text('3D Reconstruction'),
        actions: [
          IconButton(
            onPressed: refreshing ? null : refresh,
            tooltip: 'Refresh mapped environment',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: reset,
            tooltip: 'Reset camera',
            icon: const Icon(Icons.center_focus_strong),
          ),
        ],
      ),
      body: Column(
        children: [
          if (refreshing) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Scene View'),
                  selected: !analysis,
                  onSelected: (_) => setState(() {
                    analysis = false;
                    evidence = false;
                    centerlines = false;
                    grid = false;
                  }),
                ),
                ChoiceChip(
                  label: const Text('Analysis View'),
                  selected: analysis,
                  onSelected: (_) => setState(() {
                    analysis = true;
                    evidence = true;
                  }),
                ),
                FilterChip(
                  label: const Text('Environment'),
                  selected: environment,
                  onSelected: (v) => setState(() => environment = v),
                ),
              ],
            ),
          ),
          if (analysis)
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Evidence geometry'),
                  selected: evidence,
                  onSelected: (v) => setState(() => evidence = v),
                ),
                FilterChip(
                  label: const Text('Road centerlines'),
                  selected: centerlines,
                  onSelected: (v) => setState(() => centerlines = v),
                ),
                FilterChip(
                  label: const Text('World grid'),
                  selected: grid,
                  onSelected: (v) => setState(() => grid = v),
                ),
              ],
            ),
          Expanded(
            child: !scene.hasWorld
                ? const Center(
                    child: Text(
                      'Current road world unavailable. Reopen the case.',
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      painter = ReconstructionPainter(
                        data: render,
                        yaw: yaw,
                        pitch: pitch,
                        zoom: zoom,
                        pan: pan,
                        evidence: evidence,
                        centerlines: centerlines,
                        grid: grid,
                        environment: environment,
                      );
                      return GestureDetector(
                        onDoubleTap: reset,
                        onTapUp: (d) => inspect(d.localPosition),
                        onScaleStart: (_) => gestureZoom = zoom,
                        onScaleUpdate: (d) => setState(() {
                          if (d.pointerCount > 1) {
                            zoom = sceneGestureZoom(gestureZoom, d.scale);
                            pan +=
                                Offset(
                                  -d.focalPointDelta.dx,
                                  d.focalPointDelta.dy,
                                ) *
                                (render.frame.span /
                                    constraints.maxWidth /
                                    zoom);
                          } else {
                            yaw += d.focalPointDelta.dx * .008;
                            pitch = (pitch + d.focalPointDelta.dy * .008).clamp(
                              -1.4,
                              -.12,
                            );
                          }
                        }),
                        child: RepaintBoundary(
                          child: CustomPaint(
                            key: const Key('unified-scene'),
                            painter: painter,
                            size: Size.infinite,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              '${scene.hasRoadContext ? '' : 'Road context unavailable. '}$countLabel',
            ),
          ),
          ExpansionTile(
            title: const Text('Sources & evidence'),
            subtitle: Text(
              '${scene.vehicles.length} evidence-anchored proxies • user-supplied scale',
            ),
            children: [
              SizedBox(
                height: 200,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Map-derived context — verify against case evidence. Map coverage may be incomplete.\n'
                        '© OpenStreetMap contributors • Overture Maps Foundation (ODbL).\n'
                        'Evidence: image-derived relative geometry. Alignment and scale: user supplied / uncalibrated.\n'
                        'Vehicle dimensions: Not measured. Vehicle orientation: Not established.\n'
                        'Reference ground: Visualization only. Terrain elevation: Not established.\n'
                        'Incident location reference — not a collision point. Tap objects for source details.',
                      ),
                      for (final source in env?.sources ?? [])
                        Text(
                          '${source.provider}: ${source.state.storageValue}${source.cached ? ' • saved cache retained' : ''}'
                          '${source.release == null ? '' : ' • release ${source.release}'}\n'
                          'Last usable retrieval: ${source.retrievedAt?.toLocal() ?? 'unavailable'}\n'
                          '${source.detail ?? ''}',
                        ),
                      for (final item in scene.evidence)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${item.label}: ${item.placementStatus}\n'
                            '${item.capabilities.entries.map((e) => '${e.key}: ${e.value}').join(' • ')}',
                          ),
                        ),
                      Text(
                        '${scene.relatedViews.length} verified multi-view relationships. '
                        'No metric pose, automatic fusion or cross-image vehicle identity inferred.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
