import 'package:flutter/material.dart';
import '../../../core/widgets/iris_card.dart';
import '../../../app/theme/iris_spacing.dart';
import '../../evidence/application/evidence_controller.dart';
import '../application/case_location_service.dart';
import '../domain/case_location.dart';

class LocationSection extends StatefulWidget {
  const LocationSection({required this.caseId, required this.controller, required this.service, super.key});
  final String caseId; final EvidenceController controller; final CaseLocationService service;
  @override State<LocationSection> createState() => _LocationSectionState();
}
class _LocationSectionState extends State<LocationSection> {
  CaseLocation? location; bool busy = false; String? message;
  Future<void> _fromEvidence() async { if (busy) return; setState(() { busy = true; message = null; }); try { CaseLocation? found; for (final evidence in widget.controller.items) { final candidate = await widget.service.evidenceGps(widget.caseId, evidence); if (candidate != null) { if (found != null && (found.latitude - candidate.latitude).abs() > .001) { message = 'Conflicting evidence GPS values found. No location was selected.'; return; } found = candidate; } } if (!mounted) return; setState(() { location = found; message ??= found == null ? 'No GPS location metadata found in this evidence.' : 'GPS candidate found. Confirm it explicitly before using it as the incident location.'; }); } finally { if (mounted) setState(() => busy = false); } }
  Future<void> _current() async { if (busy) return; setState(() { busy = true; message = null; }); try { final found = await widget.service.current(widget.caseId); if (!mounted) return; setState(() { location = found; message = found == null ? 'Current location unavailable or permission is required. No location was assigned.' : 'Current device location candidate. It may differ from the incident location.'; }); } finally { if (mounted) setState(() => busy = false); } }
  Future<void> _confirm() async { final value = location; if (value == null) return; await widget.service.confirm(value); if (mounted) setState(() => message = 'Location confirmed from ${value.source.label}.'); }
  @override Widget build(BuildContext context) => IrisCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('LOCATION & ROAD CONTEXT', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: IrisSpacing.sm), Text(location == null ? 'Incident location: Not established' : 'Candidate: ${location!.latitude.toStringAsFixed(6)}, ${location!.longitude.toStringAsFixed(6)}'), if(location != null) Text('Source: ${location!.source.label}'), const SizedBox(height: IrisSpacing.sm), Wrap(spacing: IrisSpacing.sm, runSpacing: IrisSpacing.xs, children: [OutlinedButton(onPressed: busy ? null : _fromEvidence, child: const Text('Detect from Evidence')), OutlinedButton(onPressed: busy ? null : _current, child: const Text('Use Current Location')), const OutlinedButton(onPressed: null, child: Text('Select on Map')), const OutlinedButton(onPressed: null, child: Text('Search Location')), TextButton(onPressed: () => setState(() { location = null; message = 'Incident location: Not established'; }), child: const Text('Skip for Now'))]), if(location != null) FilledButton(onPressed: _confirm, child: const Text('Confirm location')), if(message != null) Padding(padding: const EdgeInsets.only(top: IrisSpacing.sm), child: Text(message!)), const SizedBox(height: IrisSpacing.sm), const Text('Road context: Unavailable — no map provider is configured in this V0 build.'), const Text('Map-derived context — verify against case evidence.') ]));
}
