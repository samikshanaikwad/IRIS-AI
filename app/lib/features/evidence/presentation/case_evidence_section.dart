import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/iris_colors.dart';
import '../../../app/theme/iris_spacing.dart';
import '../../../core/widgets/iris_button.dart';
import '../../../core/widgets/iris_card.dart';
import '../../../core/widgets/iris_section_header.dart';
import '../application/evidence_acquisition_service.dart';
import '../application/evidence_controller.dart';
import '../data/evidence_picker_gateway.dart';
import '../domain/evidence_image.dart';
import 'camera_capture_screen.dart';
import 'evidence_detail_screen.dart';

class CaseEvidenceSection extends StatefulWidget {
  const CaseEvidenceSection({required this.controller, this.picker, super.key});

  final EvidenceController controller;
  final EvidencePickerGateway? picker;

  @override
  State<CaseEvidenceSection> createState() => _CaseEvidenceSectionState();
}

class _CaseEvidenceSectionState extends State<CaseEvidenceSection> {
  late final EvidencePickerGateway _picker;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _picker = widget.picker ?? PlatformEvidencePickerGateway();
    widget.controller.addListener(_onChanged);
    unawaited(widget.controller.load());
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    widget.controller.dispose();
    super.dispose();
  }

  Future<void> _showAddSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(IrisSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Add Evidence',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: IrisSpacing.md),
              IrisPrimaryButton(
                key: const ValueKey<String>('evidence-take-photo'),
                label: 'Take Photo',
                icon: Icons.photo_camera_outlined,
                onPressed: () {
                  Navigator.pop(sheetContext);
                  unawaited(_capture());
                },
              ),
              const SizedBox(height: IrisSpacing.xs),
              IrisSecondaryButton(
                key: const ValueKey<String>('evidence-choose-one'),
                label: 'Choose One Image',
                icon: Icons.image_outlined,
                onPressed: () {
                  Navigator.pop(sheetContext);
                  unawaited(_pick(multiple: false));
                },
              ),
              const SizedBox(height: IrisSpacing.xs),
              IrisSecondaryButton(
                key: const ValueKey<String>('evidence-choose-multiple'),
                label: 'Choose Multiple Images',
                icon: Icons.collections_outlined,
                onPressed: () {
                  Navigator.pop(sheetContext);
                  unawaited(_pick(multiple: true));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _capture() async {
    final EvidenceImportCandidate? candidate = await Navigator.of(context)
        .push<EvidenceImportCandidate>(
          MaterialPageRoute<EvidenceImportCandidate>(
            builder: (_) => const CameraCaptureScreen(),
          ),
        );
    if (candidate != null && mounted) {
      await _import(<EvidenceImportCandidate>[candidate]);
    }
  }

  Future<void> _pick({required bool multiple}) async {
    try {
      final List<EvidenceImportCandidate> candidates = multiple
          ? await _picker.pickMultiple()
          : await _picker.pickOne();
      if (candidates.isNotEmpty && mounted) {
        await _import(candidates);
      }
    } on PlatformException {
      if (mounted) {
        _message('The Android photo picker could not be opened. Try again.');
      }
    }
  }

  Future<void> _import(List<EvidenceImportCandidate> candidates) async {
    setState(() => _importing = true);
    final EvidenceImportSummary summary = await widget.controller.importAll(
      candidates,
    );
    if (!mounted) {
      return;
    }
    setState(() => _importing = false);
    final List<String> parts = <String>[];
    if (summary.imported > 0) {
      parts.add('${summary.imported} added');
    }
    if (summary.duplicates > 0) {
      parts.add('${summary.duplicates} duplicate skipped');
    }
    if (summary.failed > 0) {
      parts.add('${summary.failed} failed');
    }
    _message(parts.isEmpty ? 'No evidence was selected.' : parts.join(' · '));
  }

  void _message(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _delete(EvidenceImage evidence) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('Delete evidence?'),
            content: const Text(
              'This permanently removes the stored evidence copy and its metadata from this case.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                key: const ValueKey<String>('confirm-evidence-delete'),
                style: TextButton.styleFrom(foregroundColor: IrisColors.danger),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) {
      return;
    }
    try {
      if (!await widget.controller.delete(evidence) && mounted) {
        _message('The evidence record is no longer available.');
      }
    } on Object {
      if (mounted) {
        _message('The evidence could not be deleted. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final EvidenceController controller = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        IrisSectionHeader(
          title: 'Evidence',
          supportingText: controller.items.isEmpty
              ? 'No evidence has been added to this case.'
              : '${controller.items.length} stored image${controller.items.length == 1 ? '' : 's'}',
        ),
        const SizedBox(height: IrisSpacing.sm),
        if (controller.loading)
          const Center(child: CircularProgressIndicator())
        else if (controller.failed)
          IrisCard(
            child: Column(
              children: <Widget>[
                const Text('Evidence could not be read from local storage.'),
                TextButton(
                  onPressed: controller.load,
                  child: const Text('Retry'),
                ),
              ],
            ),
          )
        else if (controller.items.isEmpty)
          const IrisCard(
            child: Text(
              'Add one image for a single-image workflow, or add multiple views of the same incident.',
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: IrisSpacing.sm,
              mainAxisSpacing: IrisSpacing.sm,
              childAspectRatio: 0.9,
            ),
            itemCount: controller.items.length,
            itemBuilder: (BuildContext context, int index) {
              final EvidenceImage evidence = controller.items[index];
              return _EvidenceTile(
                evidence: evidence,
                controller: controller,
                onOpen: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => EvidenceDetailScreen(
                      evidence: evidence,
                      controller: controller,
                    ),
                  ),
                ),
                onDelete: () => _delete(evidence),
              );
            },
          ),
        const SizedBox(height: IrisSpacing.sm),
        IrisPrimaryButton(
          key: const ValueKey<String>('add-evidence-button'),
          label: _importing ? 'Adding evidence…' : 'Add Evidence',
          icon: Icons.add_photo_alternate_outlined,
          onPressed: _importing ? null : _showAddSheet,
        ),
      ],
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  const _EvidenceTile({
    required this.evidence,
    required this.controller,
    required this.onOpen,
    required this.onDelete,
  });

  final EvidenceImage evidence;
  final EvidenceController controller;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => IrisCard(
    padding: EdgeInsets.zero,
    child: InkWell(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: FutureBuilder<String>(
              future: controller.absolutePath(evidence),
              builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Image.file(
                  File(snapshot.data!),
                  fit: BoxFit.cover,
                  cacheWidth: 480,
                  errorBuilder: (_, _, _) =>
                      const Center(child: Icon(Icons.broken_image_outlined)),
                );
              },
            ),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: IrisSpacing.sm),
                  child: Text(evidence.source.displayLabel),
                ),
              ),
              IconButton(
                tooltip: 'Delete evidence',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
