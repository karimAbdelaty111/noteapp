import 'package:flutter/material.dart';

import '../services/location_service.dart';
import '../services/notes_exceptions.dart';
import '../services/notes_service.dart';
import '../widgets/note_editor_form.dart';

/// SCREEN 2 — create a new note.
///
/// Pops with `true` when a note was stored, so the list screen knows it has to
/// reload.
class AddNoteScreen extends StatefulWidget {
  const AddNoteScreen({required this.notesService, super.key});

  final NotesService notesService;

  @override
  State<AddNoteScreen> createState() => _AddNoteScreenState();
}

class _AddNoteScreenState extends State<AddNoteScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _attachLocation = false;
  bool _isSaving = false;
  bool _isReadingLocation = false;
  LocationResult? _locationResult;

  @override
  void initState() {
    super.initState();
    // Opens the keyboard as soon as the screen appears, but only after the
    // first frame so the field is on screen first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // Business rule: a second tap while saving must do nothing.
    if (_isSaving) return;

    final validationError = NotesService.validateText(_controller.text);
    if (validationError != null) {
      _formKey.currentState?.validate();
      _showSnackBar(validationError, isError: true);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);

    try {
      final result = await widget.notesService.addNote(
        text: _controller.text,
        attachLocation: _attachLocation,
      );
      if (!mounted) return;

      _showSnackBar(result.warning ?? 'Note saved');
      Navigator.of(context).pop(true);
    } on NoteValidationException catch (error) {
      if (!mounted) return;
      _formKey.currentState?.validate();
      _showSnackBar(error.message, isError: true);
      _stopSaving();
    } on NoteDatabaseException catch (error) {
      if (!mounted) return;
      _showSnackBar(error.message, isError: true);
      _stopSaving();
    } on Object catch (error, stackTrace) {
      debugPrint('Saving the note failed: $error\n$stackTrace');
      if (!mounted) return;
      _showSnackBar('Could not save the note.', isError: true);
      _stopSaving();
    }
  }

  /// Reads the location straight away when the box is ticked, so the user sees
  /// the resolved place name (or the reason it failed) before saving.
  Future<void> _onLocationOptionChanged(bool value) async {
    setState(() {
      _attachLocation = value;
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

  void _stopSaving() {
    if (mounted) {
      setState(() => _isSaving = false);
    }
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
    final isBusy = _isSaving || _isReadingLocation;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New note'),
        actions: [
          TextButton(
            onPressed: isBusy ? null : _save,
            child: const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      // `resizeToAvoidBottomInset` keeps the save button above the keyboard.
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: NoteEditorForm(
            formKey: _formKey,
            controller: _controller,
            focusNode: _focusNode,
            attachLocation: _attachLocation,
            isBusy: isBusy,
            locationResult: _locationResult,
            onAttachLocationChanged: _onLocationOptionChanged,
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton.icon(
            onPressed: isBusy ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_isSaving ? 'Saving...' : 'Save note'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ),
      ),
    );
  }
}