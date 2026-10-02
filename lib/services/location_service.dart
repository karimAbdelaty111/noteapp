import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';

import '../database/entities/note.dart';

/// Why a location request could not be satisfied.
enum LocationFailureReason {
  /// Location services (GPS) are switched off on the device.
  serviceDisabled,

  /// The user refused the permission prompt.
  permissionDenied,

  /// The user refused permanently — only the OS settings can fix it.
  permissionDeniedForever,

  /// The device did not return a fix before the time limit.
  timeout,

  /// Location is not supported on this platform at all.
  unavailable,

  /// Anything else went wrong.
  unknown,
}

/// Result of a location request: either a [NoteLocation] or a friendly message.
class LocationResult {
  const LocationResult.success(this.location)
    : failureReason = null,
      message = null;

  const LocationResult.failure(this.failureReason, this.message)
    : location = null;

  final NoteLocation? location;
  final LocationFailureReason? failureReason;

  /// User facing explanation, ready to be shown in a SnackBar.
  final String? message;

  bool get isSuccess => location != null;

  /// `true` when the user has to change something in the OS settings.
  bool get requiresSettings =>
      failureReason == LocationFailureReason.permissionDeniedForever ||
      failureReason == LocationFailureReason.serviceDisabled;
}

/// Abstraction over the device location so the app can be tested without the
/// `geolocator` platform channels.
abstract class LocationService {
  /// Tries to return the current position. Never throws.
  Future<LocationResult> getCurrentLocation();

  /// Opens the OS location settings (returns `false` when not possible).
  Future<bool> openLocationSettings();

  /// Opens this app's page in the OS settings.
  Future<bool> openAppSettings();
}

/// Real implementation on top of the `geolocator` plugin.
class GeolocatorLocationService implements LocationService {
  GeolocatorLocationService({
    this.timeLimit = const Duration(seconds: 12),
    this.accuracy = LocationAccuracy.high,
    ReverseGeocoder? geocoder,
  }) : _geocoder = geocoder ?? const PlatformGeocoder();

  /// Maximum time we wait for a GPS fix before giving up.
  final Duration timeLimit;

  final LocationAccuracy accuracy;

  final ReverseGeocoder _geocoder;

  @override
  Future<LocationResult> getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult.failure(
          LocationFailureReason.serviceDisabled,
          'Location services are turned off. The note was saved without a location.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        return const LocationResult.failure(
          LocationFailureReason.permissionDeniedForever,
          'Location permission is permanently denied. '
          'Enable it in the app settings. The note was saved without a location.',
        );
      }

      if (permission == LocationPermission.denied) {
        return const LocationResult.failure(
          LocationFailureReason.permissionDenied,
          'Location permission denied. The note was saved without a location.',
        );
      }

      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return const LocationResult.failure(
          LocationFailureReason.unavailable,
          'Location permission state could not be determined. '
          'The note was saved without a location.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: accuracy, timeLimit: timeLimit),
      );

      // Reverse geocoding is a *best effort* extra: the note is kept even when
      // it fails (no internet, no permission for the geocoder, ...).
      final placeName = await _geocoder.nameFor(
        position.latitude,
        position.longitude,
      );

      return LocationResult.success(
        NoteLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          placeName: placeName,
          capturedAt: position.timestamp,
        ),
      );
    } on TimeoutException {
      return const LocationResult.failure(
        LocationFailureReason.timeout,
        'Could not get a location fix in time. '
        'The note was saved without a location.',
      );
    } on PermissionDeniedException catch (error) {
      return LocationResult.failure(
        LocationFailureReason.permissionDenied,
        error.message ??
            'Location permission denied. '
                'The note was saved without a location.',
      );
    } on LocationServiceDisabledException {
      return const LocationResult.failure(
        LocationFailureReason.serviceDisabled,
        'Location services are turned off. The note was saved without a location.',
      );
    } on UnsupportedError {
      return const LocationResult.failure(
        LocationFailureReason.unavailable,
        'Location is not available on this device. '
        'The note was saved without a location.',
      );
    } on Exception catch (error) {
      return LocationResult.failure(
        LocationFailureReason.unknown,
        'Could not read the location ($error). '
        'The note was saved without a location.',
      );
    }
  }

  @override
  Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } on Exception {
      return false;
    }
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } on Exception {
      return false;
    }
  }
}

/// Turns coordinates into a human readable place name ("Dokki, Giza, Egypt").
///
/// It is an interface so the location logic can be tested without the platform
/// channels, and so a failing lookup can be simulated.
abstract class ReverseGeocoder {
  /// Returns a readable name, or `null` when it cannot be resolved.
  Future<String?> nameFor(double latitude, double longitude);
}

/// Implementation on top of the `geocoding` plugin (Android / iOS / macOS).
///
/// Every failure — no internet, service limits, invalid coordinates — resolves
/// to `null` so the caller can fall back to the coordinates.
class PlatformGeocoder implements ReverseGeocoder {
  const PlatformGeocoder();

  /// Comma separated address parts, ordered from the most to the least specific
  /// but never longer than [maxParts] so the UI stays readable.
  static const int maxParts = 3;

  @override
  Future<String?> nameFor(double latitude, double longitude) async {
    try {
      final placemarks = await geocoding.Geocoding().placemarkFromCoordinates(
        latitude,
        longitude,
      );
      if (placemarks.isEmpty) return null;
      return _format(placemarks.first);
    } on Object catch (error) {
      // Reverse geocoding is optional: log and let the UI show the coordinates.
      debugPrint('Reverse geocoding failed: $error');
      return null;
    }
  }

  static String? _format(geocoding.Placemark placemark) {
    final parts = <String>[
      placemark.subLocality ?? placemark.name ?? '',
      placemark.locality ?? '',
      placemark.administrativeArea ?? '',
      placemark.country ?? '',
    ]
        .map((String part) => part.trim())
        .where((String part) => part.isNotEmpty)
        .toSet()
        .toList();

    if (parts.isEmpty) return null;
    return parts.take(maxParts).join(', ');
  }
}
