import 'package:flutter/material.dart';

import '../database/entities/note.dart';
import '../services/location_service.dart';
import '../services/notes_exceptions.dart';
import '../services/notes_service.dart';
import '../widgets/location_badge.dart';
import '../widgets/message_state.dart';
import '../widgets/note_card.dart' show formatDateTime;
import '../widgets/note_editor_form.dart';

/// SCREEN 3 — read, update and delete one note.
///
/// Pops with `true` when the note changed or was deleted so the list reloads.
class NoteDetailsScreen extends StatefulWidget {
  const NoteDetailsScreen({
    required this.notesService,
    required this.noteId,
    super.key,
    this.fallbackNote,
  });

  final NotesService notesService;
  final int noteId;

  /// Used while the fresh copy is loading, so the screen can render instantly.
  final Note? fallbackNote;

  @override
  State<NoteDetailsScreen> createState() => _NoteDetailsScreenState();
}

class _NoteDetailsScreenState extends State<NoteDetailsScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Note? _note;
  bool _isLoading = true;
  bool _attachLocation = false;
  bool _removeLocation = false;
  bool _isSaving = false;
  bool _isReadingLocation = false;
  bool _isDeleting = false;
  LocationResult? _locationResult;

  bool get _isBusy => _isSaving || _isDeleting || _isReadingLocation;

  @override
  void initState() {
    super.initState();
    final fallback = widget.fallbackNote;
    if (fallback != null) {
      _note = fallback;
      _controller.text = fallback.text;
    }
    _loadNote();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Reads the note again so the screen never shows stale data.
  Future<void> _loadNote() async {
    try {
      final note = await widget.notesService.findNote(widget.noteId);
      if (!mounted) return;

      if (note == null) {
        // The note vanished while this screen was opening (for example it was
        // deleted from the list). Stay here and explain instead of popping, so
        // the user is not left on a screen with no explanation.
        setState(() => _isLoading = false);
        _showSnackBar('This note was deleted.', isError: true);
        return;
      }

      setState(() {
        _note = note;
        _controller.text = note.text;
        _isLoading = false;
      });
    } on NoteDatabaseException catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar(error.message, isError: true);
    } on Object catch (error, stackTrace) {
      debugPrint('Loading the note failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar('Could not load this note.', isError: true);
    }
  }

  Future<void> _update() async {
    final note = _note;
    if (note == null || _isBusy) return;

    final validationError = NotesService.validateText(_controller.text);
    if (validationError != null) {
      _formKey.currentState?.validate();
      _showSnackBar(validationError, isError: true);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);
    try {
      final result = await widget.notesService.updateNote(
        note: note,
        text: _controller.text,
        // Editing the text must never silently drop an existing location, so
        // these flags are only set by an explicit user choice.
        attachLocation: _attachLocation,
        removeLocation: _removeLocation,
      );
      if (!mounted) return;

      setState(() {
        _note = result.note;
        _attachLocation = false;
        _removeLocation = false;
        _locationResult = null;
        _isSaving = false;
      });
      _showSnackBar(result.warning ?? 'Note updated');
    } on NoteValidationException catch (error) {
      if (!mounted) return;
      _formKey.currentState?.validate();
      _showSnackBar(error.message, isError: true);
      _stopSaving();
    } on NoteNotFoundException catch (error) {
      if (!mounted) return;
      _showSnackBar(error.message, isError: true);
      Navigator.of(context).pop(true);
    } on NoteDatabaseException catch (error) {
      if (!mounted) return;
      _showSnackBar(error.message, isError: true);
      _stopSaving();
    } on Object catch (error, stackTrace) {
      debugPrint('Updating the note failed: $error\n$stackTrace');
      if (!mounted) return;
      _showSnackBar('Could not update the note.', isError: true);
      _stopSaving();
    }
  }

  Future<void> _delete() async {
    final note = _note;
    if (note == null || _isBusy) return;

    final confirmed = await _confirmDelete();
    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      final result = await widget.notesService.deleteNote(note.id!);
      if (!mounted) return;

      _showSnackBar(
        result.deleted ? 'Note deleted' : 'This note was already deleted.',
      );
      Navigator.of(context).pop(true);
    } on NoteDatabaseException catch (error) {
      if (!mounted) return;
      _showSnackBar(error.message, isError: true);
      _stopDeleting();
    } on Object catch (error, stackTrace) {
      debugPrint('Deleting the note failed: $error\n$stackTrace');
      if (!mounted) return;
      _showSnackBar('Could not delete the note.', isError: true);
      _stopDeleting();
    }
  }

  /// Reads the location for the preview without saving anything yet.
  Future<void> _onLocationOptionChanged(bool value) async {
    setState(() {
      _attachLocation = value;
      _removeLocation = false;
      _locationResult = null;
    });
    if (!value) return;

    setState(() => _isReadingLocation = true);
    try {
      final result = await widget.notesService.previewLocation();
      if (!mounted) return;
      setState(() => _locationResult = result);
    } finally {
      if (mounted) setState(() => _isReadingLocation = false);
    }
  }

  Future<bool?> _confirmDelete() {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          icon: const Icon(Icons.delete_outline_rounded),
          title: const Text('Delete note?'),
          content: const Text('This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('DELETE'),
            ),
          ],
        );
      },
    );
  }

  void _stopSaving() {
    if (mounted) setState(() => _isSaving = false);
  }

  void _stopDeleting() {
    if (mounted) setState(() => _isDeleting = false);
  }

  void _showSnackBar(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final note = _note;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit note'),
        actions: [
          IconButton(
            tooltip: 'Delete note',
            onPressed: (note == null || _isBusy) ? null : _delete,
            icon: _isDeleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(note),
      bottomNavigationBar: _buildBottomBar(note),
    );
  }

  Widget _buildBody(Note? note) {
    if (_isLoading && note == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (note == null) {
      return const MessageState(
        icon: Icons.search_off_rounded,
        title: 'Note not found',
        message: 'This note is no longer in the database.',
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NoteEditorForm(
              formKey: _formKey,
              controller: _controller,
              focusNode: _focusNode,
              attachLocation: _attachLocation,
              isBusy: _isBusy,
              locationResult: _locationResult,
              onAttachLocationChanged: _onLocationOptionChanged,
            ),
            const SizedBox(height: 20),
            _LocationCard(
              note: note,
              isBusy: _isBusy,
              removeLocation: _removeLocation,
              onRemoveLocationChanged: (bool value) {
                setState(() {
                  _removeLocation = value;
                  if (value) {
                    _attachLocation = false;
                    _locationResult = null;
                  }
                });
              },
            ),
            const SizedBox(height: 16),
            _MetadataCard(note: note),
          ],
        ),
      ),
    );
  }

  Widget? _buildBottomBar(Note? note) {
    if (note == null) return null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: FilledButton.icon(
          onPressed: (_isBusy) ? null : _update,
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: Text(_isSaving ? 'Updating...' : 'Update note'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      ),
    );
  }
}

/// Location section: the readable place name is the headline, the raw
/// coordinates are secondary. The whole block is hidden when there is no
/// location and nothing to attach.
class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.note,
    required this.isBusy,
    required this.removeLocation,
    required this.onRemoveLocationChanged,
  });

  final Note note;
  final bool isBusy;
  final bool removeLocation;
  final ValueChanged<bool> onRemoveLocationChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = note.location;
    if (location == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.place_rounded, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Location', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            LocationBadge(hasLocation: true, location: location),
            const SizedBox(height: 8),
            // Secondary detail: the numbers, clearly less prominent.
            Text(
              location.coordinatesLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (location.capturedAt != null) ...[
              const SizedBox(height: 2),
              Text(
                'Captured ${formatDateTime(location.capturedAt!)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            CheckboxListTile(
              value: removeLocation,
              onChanged: isBusy
                  ? null
                  : (bool? value) => onRemoveLocationChanged(value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Remove the stored location'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataCard extends StatelessWidget {
  const _MetadataCard({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Row(
      children: [
        Icon(Icons.tag_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text('id ${note.id}', style: style),
        const SizedBox(width: 14),
        const Icon(Icons.schedule_rounded, size: 14),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'updated ${formatDateTime(note.updatedAt)}',
            style: style,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}