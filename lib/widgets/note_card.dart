import 'package:flutter/material.dart';

import '../database/entities/note.dart';
import 'location_badge.dart';

/// One row of the notes list.
///
/// It shows a short preview of the note, where it was written and when it was
/// last changed. Long text never breaks the layout: the preview is capped with
/// [maxLines] and an ellipsis.
class NoteCard extends StatelessWidget {
  const NoteCard({
    required this.note,
    required this.onTap,
    super.key,
    this.onDelete,
  });

  final Note note;
  final VoidCallback onTap;

  /// Optional swipe/menu delete. When `null` the row is not dismissible.
  final VoidCallback? onDelete;

  static const int previewLines = 3;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildContent(context)),
              if (onDelete != null)
                IconButton(
                  tooltip: 'Delete note',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )
              else
                const Padding(
                  padding: EdgeInsets.only(right: 4, top: 2),
                  child: Icon(Icons.chevron_right_rounded, size: 20),
                ),
            ],
          ),
        ),
      ),
    );

    if (onDelete == null) return card;

    // Swipe to delete: a left swipe (the gesture people expect in a notes app)
    // reveals a red "Delete" area. The row has to travel past 40% of its width,
    // so an accidental flick during a normal scroll never deletes anything.
    return Dismissible(
      key: ValueKey<String>('note-${note.id}'),
      direction: DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: 0.4},
      onDismissed: (_) => onDelete!(),
      background: const _SwipeBackground(),
      child: card,
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final lines = note.text.split('\n');
    final title = lines.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
        if (lines.length > 1) ...[
          const SizedBox(height: 2),
          Text(
            note.text,
            maxLines: previewLines,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            if (note.hasLocation) ...[
              Flexible(
                child: LocationBadge(hasLocation: true, location: note.location),
              ),
              const SizedBox(width: 8),
            ],
            const Spacer(),
            Icon(
              Icons.schedule_rounded,
              size: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              formatDateTime(note.updatedAt),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Red background revealed while a note is being swiped away to the left.
class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline_rounded, color: colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Text(
            'Delete',
            style: TextStyle(
              color: colorScheme.onErrorContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// `dd/MM/yyyy HH:mm` — short and locale independent so it is easy to read.
/// Notes from today show only the time.
String formatDateTime(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  String two(int number) => number.toString().padLeft(2, '0');

  final time = '${two(local.hour)}:${two(local.minute)}';
  final sameYear = local.year == now.year;
  final isToday =
      sameYear && local.month == now.month && local.day == now.day;

  if (isToday) return time;

  final date = sameYear
      ? '${two(local.day)}/${two(local.month)}'
      : '${two(local.day)}/${two(local.month)}/${local.year}';
  return '$date, $time';
}