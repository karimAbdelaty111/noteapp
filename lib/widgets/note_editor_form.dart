import 'package:flutter/material.dart';

import '../services/location_service.dart';
import '../services/notes_service.dart';

/// The note editor shared by the "Add note" and "Update note" screens so the
/// validation, the input rules and the location option only exist once.
///
/// The parent owns the [TextEditingController], the checkbox value, the busy
/// flag and the last [LocationResult]; this widget only renders and reports the
/// user's intent.
class NoteEditorForm extends StatelessWidget {
  const NoteEditorForm({
    required this.formKey,
    required this.controller,
    required this.focusNode,
    required this.attachLocation,
    required this.onAttachLocationChanged,
    required this.isBusy,
    super.key,
    this.locationResult,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool attachLocation;
  final ValueChanged<bool> onAttachLocationChanged;

  /// True while a save/update request is running — the inputs are locked.
  final bool isBusy;

  /// Outcome of the last location request, so the user gets immediate feedback
  /// instead of wondering whether the checkbox did anything.
  final LocationResult? locationResult;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Note',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            focusNode: focusNode,
            enabled: !isBusy,
            minLines: 6,
            maxLines: 14,
            maxLength: NotesService.maxLength,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            textCapitalization: TextCapitalization.sentences,
            autofocus: true,
            style: const TextStyle(fontSize: 16, height: 1.45),
            decoration: const InputDecoration(
              hintText: 'Write something...',
              alignLabelWithHint: true,
            ),
            buildCounter: (
              BuildContext context, {
              required int currentLength,
              required int? maxLength,
              required bool isFocused,
            }) {
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '$currentLength / ${maxLength ?? NotesService.maxLength}',
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            },
            validator: NotesService.validateText,
            onFieldSubmitted: (_) => focusNode.unfocus(),
          ),
          const SizedBox(height: 16),
          _LocationOption(
            attachLocation: attachLocation,
            isBusy: isBusy,
            locationResult: locationResult,
            onChanged: onAttachLocationChanged,
          ),
        ],
      ),
    );
  }
}

class _LocationOption extends StatelessWidget {
  const _LocationOption({
    required this.attachLocation,
    required this.isBusy,
    required this.locationResult,
    required this.onChanged,
  });

  final bool attachLocation;
  final bool isBusy;
  final LocationResult? locationResult;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = locationResult;

    // Only report something once the user actually asked for a location.
    final status = !attachLocation || result == null
        ? null
        : result.isSuccess
        ? 'Will be attached: ${result.location!.displayText}'
        : (result.message ?? 'The location could not be read.');

    return Material(
      // `Material` (not a coloured `Container`) keeps the checkbox ink visible.
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              value: attachLocation,
              onChanged: isBusy
                  ? null
                  : (bool? value) => onChanged(value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Add current location'),
              subtitle: Text(
                'Optional. Only the coordinates and the place name are stored.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (status != null)
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 8, bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      result!.isSuccess
                          ? Icons.check_circle_outline_rounded
                          : Icons.info_outline_rounded,
                      size: 16,
                      color: result.isSuccess
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        status,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: result.isSuccess
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}