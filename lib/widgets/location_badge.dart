import 'package:flutter/material.dart';

import '../database/entities/note.dart';

/// Compact location chip used inside a note card and on the details screen.
///
/// When a reverse geocoded name is available it is the visible label
/// (`📍 Cairo, Egypt`); otherwise the chip falls back to the coordinates so the
/// user still sees that a location exists.
class LocationBadge extends StatelessWidget {
  const LocationBadge({
    required this.hasLocation,
    super.key,
    this.location,
    this.coordinates,
    this.showWhenEmpty = false,
  });

  /// `true` when the note carries coordinates.
  final bool hasLocation;

  /// The full location, used for the readable name when available.
  final NoteLocation? location;

  /// Raw coordinates, kept for backwards compatible callers and tests.
  final String? coordinates;

  /// When `false` the widget renders nothing for a note without a location,
  /// so cards do not show a pointless "No location" chip.
  final bool showWhenEmpty;

  @override
  Widget build(BuildContext context) {
    if (!hasLocation && !showWhenEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final label = hasLocation
        ? (location?.hasPlaceName == true
              ? location!.placeName!.trim()
              : (coordinates ?? 'Location available'))
        : 'No location';

    final background = hasLocation
        ? theme.colorScheme.secondaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final foreground = hasLocation
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return Tooltip(
      message: hasLocation && location != null
          ? location!.coordinatesLabel
          : label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasLocation ? Icons.place_rounded : Icons.place_outlined,
              size: 14,
              color: foreground,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}