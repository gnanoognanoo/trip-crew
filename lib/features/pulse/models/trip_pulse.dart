import 'package:cloud_firestore/cloud_firestore.dart';

/// Supported Trip Pulse types representing a user's current need.
enum PulseType {
  hungry,
  needBreak,
  restroom,
  needFuel,
  tired,
  wantPhotos,
  emergency;

  String get key => name;

  String get title {
    switch (this) {
      case PulseType.hungry:
        return 'Hungry';
      case PulseType.needBreak:
        return 'Need a Break';
      case PulseType.restroom:
        return 'Restroom';
      case PulseType.needFuel:
        return 'Need Fuel';
      case PulseType.tired:
        return 'Tired';
      case PulseType.wantPhotos:
        return 'Want Photos';
      case PulseType.emergency:
        return 'Emergency';
    }
  }

  String get emoji {
    switch (this) {
      case PulseType.hungry:
        return '🍔';
      case PulseType.needBreak:
        return '☕';
      case PulseType.restroom:
        return '🚻';
      case PulseType.needFuel:
        return '⛽';
      case PulseType.tired:
        return '😴';
      case PulseType.wantPhotos:
        return '📸';
      case PulseType.emergency:
        return '🚨';
    }
  }

  Duration get defaultDuration {
    switch (this) {
      case PulseType.hungry:
        return const Duration(minutes: 60);
      case PulseType.needBreak:
        return const Duration(minutes: 30);
      case PulseType.restroom:
        return const Duration(minutes: 30);
      case PulseType.needFuel:
        return const Duration(minutes: 60);
      case PulseType.tired:
        return const Duration(minutes: 60);
      case PulseType.wantPhotos:
        return const Duration(minutes: 60);
      case PulseType.emergency:
        return const Duration(minutes: 120);
    }
  }

  static PulseType? fromString(String? val) {
    if (val == null) return null;
    final lower = val
        .toLowerCase()
        .replaceAll(' ', '')
        .replaceAll('_', '')
        .replaceAll('-', '');
    if (lower.contains('emergency') ||
        lower.contains('sos') ||
        lower.contains('help')) {
      return PulseType.emergency;
    }
    if (lower.contains('hungry') || lower.contains('food')) {
      return PulseType.hungry;
    }
    if (lower.contains('break') || lower.contains('coffee')) {
      return PulseType.needBreak;
    }
    if (lower.contains('restroom') ||
        lower.contains('toilet') ||
        lower.contains('washroom')) {
      return PulseType.restroom;
    }
    if (lower.contains('fuel') || lower.contains('gas')) {
      return PulseType.needFuel;
    }
    if (lower.contains('tired') || lower.contains('sleep')) {
      return PulseType.tired;
    }
    if (lower.contains('photo') || lower.contains('camera')) {
      return PulseType.wantPhotos;
    }
    return null;
  }
}

/// Domain model for Trip Pulse statuses inside trips/{tripId}/pulses/{uid}.
/// Represents a current, ephemeral state with explicit expiry (expiresAt).
class TripPulse {
  final String uid;
  final String memberName;
  final String pulseType; // Display title: e.g. 'Hungry', 'Need a Break'
  final String type; // Normalized key: e.g. 'hungry', 'needBreak'
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool isActive;

  const TripPulse({
    required this.uid,
    required this.memberName,
    required this.pulseType,
    required this.type,
    required this.createdAt,
    required this.expiresAt,
    this.isActive = true,
  });

  /// True if the pulse has expired past expiresAt or was marked inactive.
  bool get isExpired {
    if (!isActive) return true;
    return DateTime.now().isAfter(expiresAt) ||
        DateTime.now().isAtSameMomentAs(expiresAt);
  }

  /// Only active, unexpired pulses count.
  bool get isCurrentlyActive => isActive && !isExpired;

  bool get isEmergency => type == PulseType.emergency.key;

  String get emoji => PulseType.fromString(type)?.emoji ?? '📍';

  String get displayLabel => '$emoji $pulseType';

  DateTime get timestamp => createdAt; // Backwards compatibility

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'memberName': memberName,
      'pulseType': pulseType,
      'type': type,
      'createdAt': Timestamp.fromDate(createdAt),
      'timestamp': Timestamp.fromDate(createdAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'isActive': isActive,
    };
  }

  factory TripPulse.fromMap(Map<String, dynamic> map, String id) {
    DateTime parseDate(dynamic v, DateTime fallback) {
      if (v == null) return fallback;
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v) ?? fallback;
      return fallback;
    }

    final now = DateTime.now();
    final createdAt = parseDate(map['createdAt'] ?? map['timestamp'], now);
    final rawType =
        map['type'] as String? ?? map['pulseType'] as String? ?? 'hungry';
    final parsedEnum = PulseType.fromString(rawType) ?? PulseType.hungry;

    final expiresAt = map['expiresAt'] != null
        ? parseDate(map['expiresAt'], createdAt.add(parsedEnum.defaultDuration))
        : createdAt.add(parsedEnum.defaultDuration);

    final isActive = map['isActive'] as bool? ?? true;
    final pulseType = map['pulseType'] as String? ?? parsedEnum.title;

    return TripPulse(
      uid: id,
      memberName: map['memberName'] as String? ?? 'Crew Member',
      pulseType: pulseType,
      type: parsedEnum.key,
      createdAt: createdAt,
      expiresAt: expiresAt,
      isActive: isActive,
    );
  }

  TripPulse copyWith({
    String? uid,
    String? memberName,
    String? pulseType,
    String? type,
    DateTime? createdAt,
    DateTime? expiresAt,
    bool? isActive,
  }) {
    return TripPulse(
      uid: uid ?? this.uid,
      memberName: memberName ?? this.memberName,
      pulseType: pulseType ?? this.pulseType,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      isActive: isActive ?? this.isActive,
    );
  }
}
