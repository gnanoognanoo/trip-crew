import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tripcrew/core/services/supabase_service.dart';
import 'package:tripcrew/features/maps/utils/location_calculator.dart';

enum LocationServiceState {
  off,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  sharing,
  error,
}

/// Service managing client-side GPS streaming, Android foreground notification,
/// and cost-controlled location updates in Supabase PostgreSQL.
class LiveCrewService {
  static final LiveCrewService instance = LiveCrewService._internal();
  LiveCrewService._internal();

  StreamSubscription<Position>? _positionSub;
  Timer? _expiryCheckTimer;

  Position? _lastWrittenPosition;
  DateTime? _lastWriteTime;

  String? _activeTripId;
  String? _activeUid;
  String? _activeDisplayName;
  String? _activePhotoUrl;
  String _activeSharingMode = 'off';
  DateTime? _activeSharingUntil;

  // Diagnostics / Cost metrics
  int _totalFirestoreWrites = 0;
  int get totalFirestoreWrites => _totalFirestoreWrites;

  bool get isSharing => _positionSub != null;
  String get activeSharingMode => _activeSharingMode;
  DateTime? get activeSharingUntil => _activeSharingUntil;
  String? get activePhotoUrl => _activePhotoUrl;
  Position? get lastPosition => _lastWrittenPosition;

  // Stream controller to notify UI of current user GPS and status changes
  final _statusController = StreamController<LocationServiceState>.broadcast();
  Stream<LocationServiceState> get statusStream => _statusController.stream;

  final _userPositionController = StreamController<Position?>.broadcast();
  Stream<Position?> get userPositionStream => _userPositionController.stream;

  /// Checks location permissions and services without prompting unless requested.
  Future<LocationServiceState> checkStatus() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationServiceState.serviceDisabled;
    }

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      return LocationServiceState.permissionDenied;
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationServiceState.permissionDeniedForever;
    }

    return isSharing ? LocationServiceState.sharing : LocationServiceState.off;
  }

  /// Prompts user for location permission if needed.
  Future<LocationServiceState> requestPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationServiceState.serviceDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return LocationServiceState.permissionDenied;
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationServiceState.permissionDeniedForever;
    }

    return LocationServiceState.off;
  }

  /// Checks the raw system permission status.
  Future<LocationPermission> checkRawPermission() =>
      Geolocator.checkPermission();

  /// Requests foreground location permission (ACCESS_FINE_LOCATION / ACCESS_COARSE_LOCATION).
  Future<LocationPermission> requestForegroundPermission() =>
      Geolocator.requestPermission();

  /// Requests background location permission (ACCESS_BACKGROUND_LOCATION) separately for Android 11+.
  Future<LocationPermission> requestBackgroundPermission() =>
      Geolocator.requestPermission();

  /// Opens system location settings if GPS is disabled.
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  /// Opens application settings if permission was denied forever.
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  /// Starts live location sharing with battery-safe throttling and Android foreground notification.
  Future<LocationServiceState> startSharing({
    required String tripId,
    required String tripName,
    required String uid,
    required String displayName,
    String? photoUrl,
    required String
    sharingMode, // '1_hour', 'until_end_of_day', 'until_trip_ends'
    required DateTime sharingUntil,
  }) async {
    // Hard expiry check: do not start sharing if sharingUntil is already past or equal to now
    if (DateTime.now().isAfter(sharingUntil) ||
        DateTime.now().isAtSameMomentAs(sharingUntil)) {
      developer.log(
        'Cannot start sharing: sharingUntil is already in the past.',
        name: 'LiveCrewService',
      );
      await stopSharing();
      return LocationServiceState.off;
    }

    final permStatus = await requestPermission();
    if (permStatus != LocationServiceState.off &&
        permStatus != LocationServiceState.sharing) {
      _statusController.add(permStatus);
      return permStatus;
    }

    await stopSharing();

    _activeTripId = tripId;
    _activeUid = uid;
    _activeDisplayName = displayName;
    _activePhotoUrl = photoUrl;
    _activeSharingMode = sharingMode;
    _activeSharingUntil = sharingUntil;

    // 1. Configure Android Foreground Service notification
    final String notifText =
        'Live location is being shared with your $tripName crew.';

    LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 30, // Hardware-level filter (30 meters)
        intervalDuration: const Duration(seconds: 15),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: 'TripCrew • Live Crew Sharing',
          notificationText: notifText,
          notificationChannelName: 'Live Crew Location',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 30,
      );
    }

    // 2. Fetch immediate initial location and write to Supabase
    try {
      final initialPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _userPositionController.add(initialPos);
      await _writeLocationToFirestore(initialPos, force: true);
    } catch (e) {
      developer.log(
        'Initial position fetch error (waiting for stream): $e',
        name: 'LiveCrewService',
      );
    }

    // 3. Start continuous position stream
    _positionSub =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (position) async {
            _userPositionController.add(position);
            await _handlePositionUpdate(position);
          },
          onError: (err) {
            developer.log(
              'Location stream error: $err',
              name: 'LiveCrewService',
            );
            _statusController.add(LocationServiceState.error);
          },
        );

    // 4. Timer to check sharingUntil expiration periodically
    _expiryCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_activeSharingUntil != null &&
          DateTime.now().isAfter(_activeSharingUntil!)) {
        developer.log(
          'Sharing duration expired. Automatically stopping location broadcast.',
          name: 'LiveCrewService',
        );
        await stopSharing();
      }
    });

    _statusController.add(LocationServiceState.sharing);
    return LocationServiceState.sharing;
  }

  /// Processes incoming GPS positions with throttling.
  Future<void> _handlePositionUpdate(Position position) async {
    if (_activeSharingUntil == null ||
        DateTime.now().isAfter(_activeSharingUntil!) ||
        DateTime.now().isAtSameMomentAs(_activeSharingUntil!)) {
      developer.log(
        'Sharing duration expired. Cleaning up stale coordinates before writing new position.',
        name: 'LiveCrewService',
      );
      await stopSharing();
      return;
    }

    final now = DateTime.now();
    if (_lastWriteTime == null || _lastWrittenPosition == null) {
      await _writeLocationToFirestore(position, force: true);
      return;
    }

    final elapsedSeconds = now.difference(_lastWriteTime!).inSeconds;
    final distanceMeters = LocationCalculator.calculateDistance(
      _lastWrittenPosition!.latitude,
      _lastWrittenPosition!.longitude,
      position.latitude,
      position.longitude,
    );

    if (elapsedSeconds < 15) {
      return;
    }

    if (distanceMeters >= 30.0 && elapsedSeconds >= 15) {
      await _writeLocationToFirestore(position);
      return;
    }

    if (elapsedSeconds >= 120) {
      await _writeLocationToFirestore(position);
      return;
    }
  }

  /// Commits current position to Supabase `live_locations` table.
  Future<void> _writeLocationToFirestore(
    Position position, {
    bool force = false,
  }) async {
    if (_activeTripId == null || _activeUid == null) return;

    if (_activeSharingUntil == null ||
        DateTime.now().isAfter(_activeSharingUntil!) ||
        DateTime.now().isAtSameMomentAs(_activeSharingUntil!)) {
      await stopSharing();
      return;
    }

    _lastWriteTime = DateTime.now();
    _lastWrittenPosition = position;
    _totalFirestoreWrites++;

    if (!SupabaseService.isInitialized) {
      developer.log('Live Crew offline', name: 'LiveCrewService');
      return;
    }

    final data = {
      'id': '${_activeTripId}_$_activeUid',
      'trip_id': _activeTripId,
      'user_id': _activeUid,
      'user_name': _activeDisplayName ?? 'Crew Member',
      'latitude': position.latitude,
      'longitude': position.longitude,
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      await SupabaseService.client.from('live_locations').upsert(data);
      developer.log('Live Crew location update sent', name: 'LiveCrewService');
    } catch (e) {
      developer.log('Live Crew upload failed: $e', name: 'LiveCrewService');
    }
  }

  /// Explicitly stops location sharing and deletes location from Supabase.
  Future<void> stopSharing() async {
    _expiryCheckTimer?.cancel();
    _expiryCheckTimer = null;

    if (_positionSub != null) {
      await _positionSub?.cancel();
      _positionSub = null;
    }

    _lastWrittenPosition = null;
    _lastWriteTime = null;
    _userPositionController.add(null);

    final tripId = _activeTripId;
    final uid = _activeUid;

    _activeSharingMode = 'off';
    _activeSharingUntil = null;
    _statusController.add(LocationServiceState.off);

    if (tripId != null && uid != null && SupabaseService.isInitialized) {
      try {
        await SupabaseService.client
            .from('live_locations')
            .delete()
            .eq('trip_id', tripId)
            .eq('user_id', uid);
        developer.log('Live location deleted in Supabase for [$uid]', name: 'LiveCrewService');
      } catch (e) {
        developer.log('Error deleting location: $e', name: 'LiveCrewService');
      }
    }
  }

  /// Idempotently checks and cleans up an expired location document in Supabase.
  Future<void> checkAndCleanupExpiredLocation({
    required String tripId,
    required String uid,
  }) async {
    if (!SupabaseService.isInitialized) return;

    try {
      await stopSharing();
      await SupabaseService.client
          .from('live_locations')
          .delete()
          .eq('trip_id', tripId)
          .eq('user_id', uid);
    } catch (e) {
      developer.log('Error in checkAndCleanupExpiredLocation: $e', name: 'LiveCrewService');
    }
  }

  void dispose() {
    stopSharing();
    _statusController.close();
    _userPositionController.close();
  }
}
