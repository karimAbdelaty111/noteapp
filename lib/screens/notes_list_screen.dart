import 'package:flutter/material.dart';

import '../database/entities/note.dart';
import '../services/notes_exceptions.dart';
import '../services/notes_service.dart';
import '../services/shake_service.dart';
import '../widgets/message_state.dart';
import '../widgets/note_card.dart';
import 'add_note_screen.dart';
import 'note_details_screen.dart';

/// Builds the [ShakeService] used by the list screen.
///
/// It is injectable so the widget tests can trigger a shake without a real
/// accelerometer.
typedef ShakeServiceFactory = ShakeService Function(VoidCallback onShake);

/// SCREEN 1 — the list of every note stored in SQLite.
class NotesListScreen extends StatefulWidget {
  const NotesListScreen({
    required this.notesService,
    super.key,
    this.shakeServiceFactory = _defaultShakeServiceFactory,
  });

  final NotesService notesService;
  final ShakeServiceFactory shakeServiceFactory;

  static ShakeService _defaultShakeServiceFactory(VoidCallback onShake) {
    return ShakeService(onShake: onShake);
  }

  @override
  State<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends State<NotesListScreen> {
  List<Note> _notes = <Note>[];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isDeleteAllInProgress = false;
  bool _hasLoadedOnce = false;

  late final ShakeService _shakeService;

  @override
  void initState() {
    super.initState();
    _shakeService = widget.shakeServiceFactory(_onShakeDetected);
    _shakeService.start();
    _loadNotes();
  }

  @override
  void dispose() {
    // Releases the accelerometer subscription -> no listener leak.
    _shakeService.dispose();
    super.dispose();
  }

  /// Reads every note from the database.
  ///
  /// The list is always rebuilt from SQLite, never patched in memory, so the
  /// UI can never drift away from the database.
  Future<void> _loadNotes() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final notes = await widget.notesService.loadNotes();
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _isLoading = false;
        _hasLoadedOnce = true;
      });
    } on NoteDatabaseException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
      });
    } on Object catch (error, stackTrace) {
      // Defensive: an unexpected failure shows the error state instead of
      // crashing the app.
      debugPrint('Unexpected error while loading notes: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong while loading the notes.';
        _isLoading = false;
      });
    }
  }

  Future<void> _openAddNote() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AddNoteScreen(notesService: widget.notesService),
      ),
    );
    if (!mounted || changed != true) return;
    await _loadNotes();
  }

  Future<void> _openNote(Note note) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => NoteDetailsScreen(
          notesService: widget.notesService,
          noteId: note.id!,
          fallbackNote: note,
        ),
      ),
    );
    if (!mounted || changed != true) return;
    await _loadNotes();
  }

  /// Deletes one note straight from the list (swipe or the bin icon) and offers
  /// an Undo instead of a confirmation dialog: the snackbar is enough of a
  /// safety net, so the flow stays fast.
Future<void> _deleteNote(Note note) async {
    final id = note.id;
    if (id == null || _isDeleteAllInProgress) return;

    try {
final result = await widget.notesService.deleteNote(id);
      if (!mounted) return;

      if (!result.deleted) {
        await _loadNotes();
        _showSnackBar('This note was already deleted.');
        return;
      }

      await _loadNotes();
      if (!mounted) return;

      _showSnackBar(
        'Note deleted',
        action: result.canBeRestored
            ? SnackBarAction(
                label: 'UNDO',
                onPressed: () => _undoDelete(result.note!),
              )
            : null,
      );
    } on NoteDatabaseException catch (error) {
      if (!mounted) return;
      _showSnackBar(error.message, isError: true);
    } on Object catch (error, stackTrace) {
      debugPrint('Deleting the note failed: $error\n$stackTrace');
      if (!mounted) return;
      _showSnackBar('Could not delete the note.', isError: true);
    }
  }

  /// UNDO — writes the note back through the repository, then reloads the list
  /// from SQLite so what the user sees is exactly what is stored.
  Future<void> _undoDelete(Note note) async {
    try {
      final result = await widget.notesService.restoreNote(note);
      if (!mounted) return;

      await _loadNotes();
      if (!mounted) return;

      _showSnackBar(result.warning ?? 'Note restored');
    } on NoteValidationException catch (error) {
      if (!mounted) return;
      _showSnackBar(error.message, isError: true);
    } on NoteDatabaseException catch (error) {
      if (!mounted) return;
      _showSnackBar('Could not restore the note: ${error.message}', isError: true);
    } on Object catch (error, stackTrace) {
      debugPrint('Undo failed: $error\n$stackTrace');
      if (!mounted) return;
      _showSnackBar('Could not restore the note.', isError: true);
    }
  }

  /// SHAKE REQUIREMENT — the gesture only calls this method once thanks to the
  /// trigger cooldown and the `_isDeleteAllInProgress` guard below.
  Future<void> _onShakeDetected() async {
    if (!mounted || _isDeleteAllInProgress) return;

    setState(() => _isDeleteAllInProgress = true);
    try {
      if (_notes.isEmpty) {
        _showSnackBar('There are no notes to delete.');
        return;
      }

      final confirmed = await _confirmDeleteAll();
      // The user may have left the screen while the dialog was open.
      if (confirmed != true || !mounted) return;

      final result = await widget.notesService.deleteAllNotes();
      if (!mounted) return;

      await _loadNotes();
      if (!mounted) return;

      _showSnackBar(
        result.isEmpty
            ? 'There were no notes to delete.'
            : 'All notes deleted',
        action: result.canBeRestored
            ? SnackBarAction(
                label: 'UNDO ALL',
                onPressed: () => _undoDeleteAll(result.notes),
              )
            : null,
      );
    } on NoteDatabaseException catch (error) {
      if (!mounted) return;
      _showSnackBar(error.message, isError: true);
    } on Object catch (error, stackTrace) {
      debugPrint('Delete all failed: $error\n$stackTrace');
      if (!mounted) return;
      _showSnackBar('Could not delete the notes.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isDeleteAllInProgress = false);
      }
    }
  }

  /// UNDO ALL — restores every note that the shake deleted, through Floor.
  Future<void> _undoDeleteAll(List<Note> notes) async {
    try {
      final result = await widget.notesService.restoreNotes(notes);
      if (!mounted) return;

      await _loadNotes();
      if (!mounted) return;

      _showSnackBar(
        result.warning ??
            'Restored ${result.restoredCount} '
                '${result.restoredCount == 1 ? "note" : "notes"}',
      );
    } on NoteDatabaseException catch (error) {
      if (!mounted) return;
      _showSnackBar('Could not restore the notes: ${error.message}', isError: true);
    } on Object catch (error, stackTrace) {
      debugPrint('Undo all failed: $error\n$stackTrace');
      if (!mounted) return;
      _showSnackBar('Could not restore the notes.', isError: true);
    }
  }

  /// Asks the user before wiping the whole table.
  Future<bool?> _confirmDeleteAll() {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: const Text('Delete all notes?'),
          content: const Text(
            'All saved notes will be removed. You can undo this for a few '
            'seconds afterwards.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('DELETE ALL'),
            ),
          ],
        );
      },
    );
  }

  void _showSnackBar(
    String message, {
    bool isError = false,
    SnackBarAction? action,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    // Hiding the current one first keeps a single active Undo at a time, so two
    // quick deletes can never restore the same note twice.
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: action == null
            ? const Duration(seconds: 3)
            : const Duration(seconds: 5),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        action: action,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My notes'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadNotes,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(30),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _subtitle(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isDeleteAllInProgress ? null : _openAddNote,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add note'),
      ),
    );
  }

  String _subtitle() {
    if (_isLoading && !_hasLoadedOnce) return 'Loading your notes...';
    final count = _notes.length;
    final notes = '$count ${count == 1 ? "note" : "notes"}';
    return '$notes  •  shake the phone to delete all';
  }

  Widget _buildBody() {
    if (_isLoading && !_hasLoadedOnce) {
      return const NoteListSkeleton();
    }

    final error = _errorMessage;
    if (error != null) {
      return MessageState(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load your notes.",
        message: error,
        actionLabel: 'Retry',
        isError: true,
        onAction: _loadNotes,
      );
    }

    if (_notes.isEmpty) {
      return MessageState(
        icon: Icons.sticky_note_2_outlined,
        title: 'No notes yet',
        message:
            'Create your first note and keep your thoughts organized.',
        actionLabel: 'Add note',
        onAction: _openAddNote,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadNotes,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: _notes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (BuildContext context, int index) {
          final note = _notes[index];
          return NoteCard(
            key: ValueKey<int?>(note.id),
            note: note,
            onTap: () => _openNote(note),
            onDelete: () => _deleteNote(note),
          );
        },
      ),
    );
  }
}