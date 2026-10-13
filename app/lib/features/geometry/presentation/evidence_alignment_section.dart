import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../../../core/domain/case_local_world.dart';
import '../../evidence/application/evidence_controller.dart';
import '../../evidence/domain/evidence_image.dart';
import '../../location/application/case_location_service.dart';
import '../../location/domain/case_location.dart';
import '../../location/domain/road_context.dart';
import '../application/evidence_world_alignment_service.dart';
import '../data/sqlite_geometry_repository.dart';
import '../application/relative_geometry_service.dart';
import '../domain/evidence_world_alignment.dart';
import '../domain/relative_geometry.dart';

class EvidenceAlignmentSection extends StatefulWidget {
  const EvidenceAlignmentSection({
    required this.caseId,
    required this.evidenceController,
    required this.geometry,
    required this.location,
    required this.alignment,
    super.key,
  });
  final String caseId;
  final EvidenceController evidenceController;
  final RelativeGeometryOperations geometry;
  final CaseLocationService location;
  final EvidenceWorldAlignmentService alignment;

  @override
  State<EvidenceAlignmentSection> createState() =>
      _EvidenceAlignmentSectionState();
}

class _EvidenceAlignmentSectionState extends State<EvidenceAlignmentSection> {
  EvidenceImage? selected;
  List<EvidenceImage> eligible = const [];
  bool checking = false;

  @override
  void initState() {
    super.initState();
    widget.evidenceController.addListener(_onEvidenceChanged);
    unawaited(_hydrateEligible());
  }

  @override
  void dispose() {
    widget.evidenceController.removeListener(_onEvidenceChanged);
    super.dispose();
  }

  void _onEvidenceChanged() {
    if (widget.evidenceController.items.isNotEmpty)
      unawaited(_hydrateEligible());
  }

  Future<void> _hydrateEligible() async {
    final items = widget.evidenceController.items;
    if (items.isEmpty) return;
    setState(() => checking = true);
    final valid = <EvidenceImage>[];
    for (final item in items) {
      try {
        final record = await widget.geometry.load(item);
        if (record == null) continue;
        await widget.geometry.read(record);
        valid.add(item);
      } on Object {
        // Invalid or stale geometry is deliberately unavailable, never a fallback.
      }
    }
    if (!mounted) return;
    setState(() {
      eligible = List.unmodifiable(valid);
      if (selected == null || !eligible.contains(selected)) {
        selected = eligible.isEmpty ? null : eligible.first;
      }
      checking = false;
    });
  }

  Future<void> _open() async {
    final evidence = selected;
    if (evidence == null) return;
    final origin = await widget.location.load(widget.caseId);
    final road = await widget.location.loadRoadContext(widget.caseId);
    final record = await widget.geometry.load(evidence);
    if (!mounted) return;
    if (origin == null ||
        road == null ||
        road.status != 'AVAILABLE' ||
        record == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Alignment requires map-derived road context and generated relative geometry.',
          ),
        ),
      );
      return;
    }
    try {
      final points = await widget.geometry.read(record);
      final previous = await widget.alignment.load(evidence.id);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => EvidenceAlignmentEditor(
            caseId: widget.caseId,
            evidence: evidence,
            origin: origin,
            road: road,
            geometry: points,
            record: record,
            previous: previous,
            service: widget.alignment,
          ),
        ),
      );
    } on Object {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Relative geometry is unavailable or corrupt.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = eligible;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EVIDENCE-TO-WORLD ALIGNMENT',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'User-supplied placement only. Relative evidence geometry is not automatically metric.',
            ),
            if (checking)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Checking persisted relative geometry…'),
              )
            else if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'No current TASK009C relative geometry is available for alignment.',
                ),
              )
            else ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<EvidenceImage>(
                initialValue: selected,
                decoration: const InputDecoration(
                  labelText: 'Evidence geometry',
                ),
                items: items
                    .map(
                      (e) => DropdownMenuItem(
                        value: e,
                        child: Text(
                          e.originalDisplayName ?? e.id,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => selected = value),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _open,
                icon: const Icon(Icons.open_with),
                label: const Text('Align Evidence'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EvidenceAlignmentEditor extends StatefulWidget {
  const EvidenceAlignmentEditor({
    required this.caseId,
    required this.evidence,
    required this.origin,
    required this.road,
    required this.geometry,
    required this.record,
    required this.previous,
    required this.service,
    super.key,
  });
  final String caseId;
  final EvidenceImage evidence;
  final CaseLocation origin;
  final RoadContext road;
  final RelativeGeometry geometry;
  final GeometryRecord record;
  final EvidenceWorldAlignment? previous;
  final EvidenceWorldAlignmentService service;
  @override
  State<EvidenceAlignmentEditor> createState() =>
      _EvidenceAlignmentEditorState();
}

class _EvidenceAlignmentEditorState extends State<EvidenceAlignmentEditor> {
  late double x, y, z, yaw, scale;
  @override
  void initState() {
    super.initState();
    final p = widget.previous;
    x = p?.translationX ?? 0;
    y = p?.translationY ?? 0;
    z = p?.translationZ ?? 0;
    yaw = p?.yaw ?? 0;
    scale = p?.uniformScale ?? 1;
  }

  String _fingerprint() => sha256
      .convert(
        utf8.encode(
          '${widget.road.caseId}|${widget.road.latitude}|${widget.road.longitude}|${widget.road.status}|${widget.road.json}',
        ),
      )
      .toString();
  Future<void> _save() async {
    final now = DateTime.now().toUtc();
    await widget.service.save(
      EvidenceWorldAlignment(
        caseId: widget.caseId,
        evidenceId: widget.evidence.id,
        translationX: x,
        translationY: y,
        translationZ: z,
        yaw: yaw,
        uniformScale: scale,
        source: AlignmentSource.userSupplied,
        geometrySha256: widget.record.sha256,
        roadContextFingerprint: _fingerprint(),
        worldFrameFingerprint: CaseLocalWorldFrame.fingerprint(
          caseId: widget.caseId,
          originLatitude: widget.origin.latitude,
          originLongitude: widget.origin.longitude,
        ),
        provenanceVersion: EvidenceWorldAlignment.currentProvenanceVersion,
        createdAt: widget.previous?.createdAt ?? now,
        updatedAt: now,
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Align Evidence')),
    body: Column(
      children: [
        Expanded(
          child: CustomPaint(
            painter: _AlignmentPainter(
              widget.road,
              widget.geometry,
              EvidenceWorldAlignment(
                caseId: widget.caseId,
                evidenceId: widget.evidence.id,
                translationX: x,
                translationY: y,
                translationZ: z,
                yaw: yaw,
                uniformScale: scale,
                source: AlignmentSource.userSupplied,
                geometrySha256: widget.record.sha256,
                roadContextFingerprint: _fingerprint(),
                worldFrameFingerprint: CaseLocalWorldFrame.fingerprint(
                  caseId: widget.caseId,
                  originLatitude: widget.origin.latitude,
                  originLongitude: widget.origin.longitude,
                ),
                provenanceVersion:
                    EvidenceWorldAlignment.currentProvenanceVersion,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'Initial editing position — not inferred. All controls are USER-SUPPLIED ALIGNMENT. Scale is relative-to-world and uncalibrated. The preview auto-fits all loaded geometry; apparent screen spacing is not a measured distance.',
          ),
        ),
        _slider('Move X', x, -50, 50, (v) => setState(() => x = v)),
        _slider('Move Z', z, -50, 50, (v) => setState(() => z = v)),
        _slider(
          'Heading',
          yaw,
          -math.pi,
          math.pi,
          (v) => setState(() => yaw = v),
        ),
        _slider('Scale', scale, .1, 10, (v) => setState(() => scale = v)),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _save, child: const Text('Save Alignment')),
            const SizedBox(width: 16),
          ],
        ),
      ],
    ),
  );
  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) => Row(
    children: [
      SizedBox(width: 78, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ),
    ],
  );
}

class _AlignmentPainter extends CustomPainter {
  _AlignmentPainter(this.road, this.geometry, this.alignment);
  final RoadContext road;
  final RelativeGeometry geometry;
  final EvidenceWorldAlignment alignment;
  @override
  void paint(Canvas canvas, Size size) {
    final all = road.roads.expand((r) => r.localCoordinates).toList();
    if (all.isEmpty) return;
    var minX = all.map((p) => p[0]).reduce(math.min),
        maxX = all.map((p) => p[0]).reduce(math.max),
        minZ = all.map((p) => p[1]).reduce(math.min),
        maxZ = all.map((p) => p[1]).reduce(math.max);
    // Both preview and ReconstructionScene use the same canonical TASK012B
    // transform. Only the viewport below is independently auto-fitted.
    final ep = geometry.points.map(alignment.transform).toList();
    for (final p in ep) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minZ = math.min(minZ, p.z);
      maxZ = math.max(maxZ, p.z);
    }
    final span = math.max(math.max(maxX - minX, maxZ - minZ), 1);
    Offset project(double x, double z) => Offset(
      size.width / 2 + (x - (minX + maxX) / 2) * size.shortestSide * .7 / span,
      size.height / 2 + (z - (minZ + maxZ) / 2) * size.shortestSide * .7 / span,
    );
    final roadPaint = Paint()
      ..color = Colors.amberAccent
      ..strokeWidth = 3;
    for (final r in road.roads)
      for (var i = 1; i < r.localCoordinates.length; i++)
        canvas.drawLine(
          project(r.localCoordinates[i - 1][0], r.localCoordinates[i - 1][1]),
          project(r.localCoordinates[i][0], r.localCoordinates[i][1]),
          roadPaint,
        );
    final ePaint = Paint()..color = Colors.cyanAccent;
    for (final p in ep) canvas.drawCircle(project(p.x, p.z), 2, ePaint);
    final origin = project(
      const CaseLocalWorldPoint.origin().xEast,
      const CaseLocalWorldPoint.origin().zNorth,
    );
    canvas.drawCircle(
      origin,
      5,
      Paint()
        ..color = Colors.cyanAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _AlignmentPainter old) => true;
}

/// Safe relationship diagnostic shared with Scene View. It contains no
/// coordinates and does not alter either road or evidence placement.
String alignmentPreviewRoadBucket(
  RoadContext road,
  RelativeGeometry geometry,
  EvidenceWorldAlignment alignment,
) {
  if (geometry.points.isEmpty) return 'noEvidenceGeometry';
  var nearest = double.infinity;
  for (final point in geometry.points.map(alignment.transform)) {
    nearest = math.min(
      nearest,
      nearestMapPolylineDistance(
        CaseLocalWorldPoint(xEast: point.x, yUp: point.y, zNorth: point.z),
        road.roads.map((r) => r.localCoordinates),
      ),
    );
  }
  return mapDistanceBucket(nearest);
}
