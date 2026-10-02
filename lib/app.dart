import 'package:flutter/material.dart';

import 'database/app_database.dart';
import 'screens/notes_list_screen.dart';
import 'services/location_service.dart';
import 'services/notes_service.dart';
import 'theme/app_theme.dart';

/// Root widget of the app.
///
/// It opens the **single** [AppDatabase] instance, closes it when the widget is
/// disposed and shows a retry screen when the database cannot be opened.
class NotesApp extends StatefulWidget {
  const NotesApp({super.key, this.openDatabase = openNotesDatabase});

  /// Overridden by the widget tests with `openInMemoryNotesDatabase`.
  final Future<AppDatabase> Function() openDatabase;

  @override
  State<NotesApp> createState() => _NotesAppState();
}

class _NotesAppState extends State<NotesApp> {
  NotesService? _notesService;
  AppDatabase? _database;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _openDatabase();
  }

  Future<void> _openDatabase() async {
    setState(() {
      _errorMessage = null;
      _notesService = null;
    });

    try {
      final database = await widget.openDatabase();
      // Makes sure the schema exists before the first query runs.
      await database.noteDao.countNotes();

      if (!mounted) {
        await database.close();
        return;
      }
      setState(() {
        _database = database;
        _notesService = NotesService(
          noteDao: database.noteDao,
          locationService: GeolocatorLocationService(),
        );
      });
    } on Object catch (error) {
      debugPrint('Could not open the notes database: $error');
      if (!mounted) return;
      setState(() => _errorMessage = 'The notes database could not be opened.');
    }
  }

  @override
  void dispose() {
    _database?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notes',
      debugShowCheckedModeBanner: false,
      // Both themes are designed in AppTheme, so the app follows the phone's
      // light/dark setting without any extra state or storage.
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    final notesService = _notesService;
    if (notesService != null) {
      return NotesListScreen(notesService: notesService);
    }

    final error = _errorMessage;
    if (error == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.storage_rounded,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _openDatabase,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
