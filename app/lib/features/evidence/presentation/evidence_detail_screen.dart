import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/theme/iris_spacing.dart';
import '../../../app/theme/iris_colors.dart';
import '../../../core/widgets/iris_app_bar.dart';
import '../../../core/widgets/iris_button.dart';
import '../../../core/widgets/iris_card.dart';
import '../../../core/widgets/iris_page_body.dart';
import '../application/evidence_controller.dart';
import '../domain/evidence_image.dart';

class EvidenceDetailScreen extends StatefulWidget {
  const EvidenceDetailScreen({
    required this.evidence,
    required this.controller,
    super.key,
  });

  final EvidenceImage evidence;
  final EvidenceController controller;

  @override
  State<EvidenceDetailScreen> createState() => _EvidenceDetailScreenState();
}

class _EvidenceDetailScreenState extends State<EvidenceDetailScreen> {
  String? _path;
  bool _missing = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    widget.controller.absolutePath(widget.evidence).then((String value) async {
      final bool exists = await File(value).exists();
      if (mounted) {
        setState(() {
          _path = value;
          _missing = !exists;
        });
      }
    });
  }

  Future<void> _remove() async {
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
                key: const ValueKey<String>('confirm-detail-evidence-delete'),
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
    setState(() => _deleting = true);
    try {
      final bool deleted = await widget.controller.delete(widget.evidence);
      if (!mounted) {
        return;
      }
      if (!deleted) {
        throw StateError('Evidence record is unavailable.');
      }
      Navigator.of(context).pop();
    } on Object {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The evidence could not be deleted. Try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final EvidenceImage evidence = widget.evidence;
    return Scaffold(
      appBar: const IrisAppBar(title: 'Evidence Detail'),
      body: IrisPageBody(
        children: <Widget>[
          AspectRatio(
            aspectRatio: evidence.widthPx != null && evidence.heightPx != null
                ? evidence.widthPx! / evidence.heightPx!
                : 4 / 3,
            child: IrisCard(
              padding: EdgeInsets.zero,
              child: _path == null
                  ? const Center(child: CircularProgressIndicator())
                  : _missing
                  ? const Center(
                      child: Text('Stored evidence file is unavailable.'),
                    )
                  : InteractiveViewer(
                      child: Image.file(
                        File(_path!),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Center(
                          child: Text(
                            'This image cannot be displayed on this device.',
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: IrisSpacing.md),
          IrisCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Metadata(label: 'Source', value: evidence.source.displayLabel),
                if (evidence.originalDisplayName != null)
                  _Metadata(
                    label: 'Original name',
                    value: evidence.originalDisplayName!,
                  ),
                if (evidence.capturedAt != null)
                  _Metadata(
                    label: 'Captured',
                    value: evidence.capturedAt!.toLocal().toString(),
                  ),
                _Metadata(
                  label: 'Imported',
                  value: evidence.importedAt.toLocal().toString(),
                ),
                _Metadata(
                  label: 'File size',
                  value: '${evidence.fileSizeBytes} bytes',
                ),
                if (evidence.widthPx != null && evidence.heightPx != null)
                  _Metadata(
                    label: 'Dimensions',
                    value: '${evidence.widthPx} × ${evidence.heightPx} px',
                  ),
                if (evidence.mimeType != null)
                  _Metadata(label: 'Media type', value: evidence.mimeType!),
                _Metadata(label: 'SHA-256', value: evidence.sha256),
              ],
            ),
          ),
          const SizedBox(height: IrisSpacing.md),
          IrisSecondaryButton(
            key: const ValueKey<String>('detail-remove-evidence-button'),
            label: _deleting ? 'Deleting evidence…' : 'Remove Evidence',
            icon: Icons.delete_outline,
            onPressed: _deleting ? null : _remove,
          ),
        ],
      ),
    );
  }
}

class _Metadata extends StatelessWidget {
  const _Metadata({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: IrisSpacing.xs),
    child: SelectableText('$label: $value'),
  );
}
