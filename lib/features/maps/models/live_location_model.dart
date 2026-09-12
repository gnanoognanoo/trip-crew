import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tripcrew/features/pulse/models/trip_pulse.dart';

enum LocationFreshness { live, recent, stale, offline }

/// Model representing a crew member's latest location in `trips/{tripId}/locations/{uid}`.
///
/// Data Retention & Privacy Guarantees:
/// - NO GPS HISTORY: TripCrew never intentionally creates location-history documents.
/// - LATEST LOCATION: Only the latest position is stored in the member's single document.
/// - HARD EXPIRY: Active sharing always requires an explicit `sharingUntil` timestamp.
/// - CLIENT CLEANUP: Coordinates are deleted when sharing stops or expires whenever the client runs.
/// - ZERO EXPIRED EXPOSURE: If `sharingUntil <= now`, the client treats location as offline/expired
///   and never displays or calculates distance from stale coordinates, even if process-death prevented physical Firestore deletion.
/// - SERVER-SIDE GUARANTEED EXPIRY: Not available on Firebase Spark architecture.
class LiveLocationModel {
  final String uid;
  final String displayName;
  final String? photoUrl;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final DateTime updatedAt;
  final String
  sharingMode; // 'off', '1_hour', 'until_end_of_day', 'until_trip_ends'
  final DateTime? sharingUntil;
  final bool isSharing;
  final double? batteryLevel;
  final String?
  lastPulse; // Optional Trip Pulse preview (e.g. 'Hungry', 'Coffee')
  final TripPulse? activePulse; // Realtime active, unexpired pulse if present

  const LiveLocationModel({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    this.latitude,
    this.longitude,
    this.accuracy,
    required this.updatedAt,
    this.sharingMode = 'off',
    this.sharingUntil,
    required this.isSharing,
    this.batteryLevel,
    this.lastPulse,
    this.activePulse,
  });

  /// True only when an active, unexpired pulse is attached
  bool get hasActivePulse =>
      activePulse != null && activePulse!.isCurrentlyActive;

  /// Effective pulse display label (e.g. '🍔 Hungry', '😴 Tired')
  String? get effectivePulseLabel {
    if (hasActivePulse) return activePulse!.displayLabel;
    return lastPulse;
  }

  /// Compact emoji for Radar dot marker
  String? get radarPulseEmoji {
    if (hasActivePulse) return activePulse!.emoji;
    if (lastPulse != null) {
      final pEnum = PulseType.fromString(lastPulse);
      if (pEnum != null) return pEnum.emoji;
    }
    return null;
  }

  /// True only when non-null coordinates are present
  bool get hasCoordinates => latitude != null && longitude != null;

  /// Check if sharing duration has expired or coordinates are cleared.
  /// Hard expiry rule: If sharingUntil is null or in the past, sharing is expired.
  bool get isExpired {
    if (!isSharing || !hasCoordinates) return true;
    if (sharingUntil == null) return true;
    return DateTime.now().isAfter(sharingUntil!) ||
        DateTime.now().isAtSameMomentAs(sharingUntil!);
  }

  /// Whether location is actively shared, unexpired, and has coordinates
  bool get isLiveActive => isSharing && hasCoordinates && !isExpired;

  /// Evaluates freshness based on elapsed seconds since last update.
  /// Decouples SHARING EXPIRY from LOCATION FRESHNESS:
  /// Even if sharingUntil is still valid, an update > 5m old is marked stale.
  LocationFreshness get freshness {
    if (!isSharing || isExpired || !hasCoordinates) {
      return LocationFreshness.offline;
    }
    final elapsedSec = DateTime.now().difference(updatedAt).inSeconds;
    if (elapsedSec <= 60) return LocationFreshness.live;
    if (elapsedSec <= 300) return LocationFreshness.recent;
    return LocationFreshness.stale;
  }

  String get freshnessLabel {
    if (!isSharing || !hasCoordinates) return 'Location sharing off';
    if (isExpired) return 'Location expired';
    final elapsedSec = DateTime.now().difference(updatedAt).inSeconds;
    if (elapsedSec <= 15) return 'Live now';
    if (elapsedSec <= 60) return 'Updated ${elapsedSec}s ago';
    if (elapsedSec <= 300) {
      final elapsedMin = (elapsedSec / 60).floor();
      return 'Updated ${elapsedMin}m ago';
    }
    final elapsedMin = (elapsedSec / 60).floor();
    return 'Location unavailable (Last updated ${elapsedMin}m ago)';
  }

  LiveLocationModel copyWith({
    String? uid,
    String? displayName,
    String? photoUrl,
    double? latitude,
    double? longitude,
    double? accuracy,
    bool clearCoordinates = false,
    DateTime? updatedAt,
    String? sharingMode,
    DateTime? sharingUntil,
    bool clearSharingUntil = false,
    bool? isSharing,
    double? batteryLevel,
    String? lastPulse,
    TripPulse? activePulse,
    bool clearPulse = false,
  }) {
    return LiveLocationModel(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      latitude: clearCoordinates ? null : (latitude ?? this.latitude),
      longitude: clearCoordinates ? null : (longitude ?? this.longitude),
      accuracy: clearCoordinates ? null : (accuracy ?? this.accuracy),
      updatedAt: updatedAt ?? this.updatedAt,
      sharingMode: sharingMode ?? this.sharingMode,
      sharingUntil: clearSharingUntil
          ? null
          : (sharingUntil ?? this.sharingUntil),
      isSharing: isSharing ?? this.isSharing,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      lastPulse: clearPulse ? null : (lastPulse ?? this.lastPulse),
      activePulse: clearPulse ? null : (activePulse ?? this.activePulse),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'displayName': displayName,
      'photoUrl': photoUrl,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (accuracy != null) 'accuracy': accuracy,
      'updatedAt': updatedAt.toIso8601String(),
      'sharingMode': sharingMode,
      if (sharingUntil != null) 'sharingUntil': sharingUntil?.toIso8601String(),
      'isSharing': isSharing,
      'batteryLevel': batteryLevel,
      'lastPulse': lastPulse,
    };
  }

  Map<String, dynamic> toFirestoreMap({bool useServerTimestamp = true}) {
    final map = toMap();
    if (useServerTimestamp) {
      map['updatedAt'] = FieldValue.serverTimestamp();
    }
    return map;
  }

  factory LiveLocationModel.fromMap(Map<String, dynamic> map, String id) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    DateTime? parseNullableDate(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return LiveLocationModel(
      uid: id,
      displayName: map['displayName'] as String? ?? 'Crew Member',
      photoUrl: map['photoUrl'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      accuracy: (map['accuracy'] as num?)?.toDouble(),
      updatedAt: parseDate(map['updatedAt']),
      sharingMode: map['sharingMode'] as String? ?? 'off',
      sharingUntil: parseNullableDate(map['sharingUntil']),
      isSharing: map['isSharing'] as bool? ?? false,
      batteryLevel: (map['batteryLevel'] as num?)?.toDouble(),
      lastPulse: map['lastPulse'] as String?,
    );
  }
}
