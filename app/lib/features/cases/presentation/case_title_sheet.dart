import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/iris_colors.dart';
import '../../../app/theme/iris_spacing.dart';
import '../../../core/widgets/iris_button.dart';
import '../domain/case_title_validator.dart';
import '../domain/incident_case.dart';

typedef CaseTitleSubmitter = Future<IncidentCase> Function(String title);

Future<IncidentCase?> showCaseTitleSheet({
  required BuildContext context,
  required String heading,
  required String submitLabel,
  required CaseTitleSubmitter onSubmit,
  String initialTitle = '',
}) {
  return showModalBottomSheet<IncidentCase>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext context) {
      return _CaseTitleSheet(
        heading: heading,
        submitLabel: submitLabel,
        initialTitle: initialTitle,
        onSubmit: onSubmit,
      );
    },
  );
}

class _CaseTitleSheet extends StatefulWidget {
  const _CaseTitleSheet({
    required this.heading,
    required this.submitLabel,
    required this.initialTitle,
    required this.onSubmit,
  });

  final String heading;
  final String submitLabel;
  final String initialTitle;
  final CaseTitleSubmitter onSubmit;

  @override
  State<_CaseTitleSheet> createState() => _CaseTitleSheetState();
}

class _CaseTitleSheetState extends State<_CaseTitleSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  bool _submitting = false;
  String? _submissionError;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _titleController.selection = TextSelection.collapsed(
      offset: _titleController.text.length,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _submitting = true;
      _submissionError = null;
    });

    try {
      final IncidentCase incidentCase = await widget.onSubmit(
        _titleController.text,
      );
      if (mounted) {
        Navigator.of(context).pop(incidentCase);
      }
    } on Object {
      if (mounted) {
        setState(() {
          _submitting = false;
          _submissionError =
              'The case could not be saved. Check local storage and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !_submitting,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(
          left: IrisSpacing.md,
          top: IrisSpacing.md,
          right: IrisSpacing.md,
          bottom: MediaQuery.viewInsetsOf(context).bottom + IrisSpacing.md,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  widget.heading,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: IrisSpacing.xs),
                Text(
                  'Use a clear title that helps you identify this incident.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: IrisSpacing.md),
                TextFormField(
                  key: const ValueKey<String>('case-title-field'),
                  controller: _titleController,
                  autofocus: true,
                  enabled: !_submitting,
                  minLines: 1,
                  maxLines: 2,
                  maxLength: CaseTitleValidator.maxLength,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  inputFormatters: <TextInputFormatter>[
                    LengthLimitingTextInputFormatter(
                      CaseTitleValidator.maxLength,
                    ),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Case title',
                    hintText: 'Enter a descriptive title',
                  ),
                  validator: (String? value) {
                    return CaseTitleValidator.validationMessage(value ?? '');
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (_submissionError != null) ...<Widget>[
                  const SizedBox(height: IrisSpacing.sm),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _submissionError!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: IrisColors.danger,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: IrisSpacing.sm),
                IrisPrimaryButton(
                  key: const ValueKey<String>('confirm-case-title-button'),
                  label: _submitting ? 'Saving…' : widget.submitLabel,
                  icon: _submitting ? null : Icons.check,
                  onPressed: _submitting ? null : _submit,
                ),
                const SizedBox(height: IrisSpacing.xs),
                IrisSecondaryButton(
                  label: 'Cancel',
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
