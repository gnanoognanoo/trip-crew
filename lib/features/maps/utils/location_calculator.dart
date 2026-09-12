import 'dart:math' as math;

/// Configurable threshold for crew group proximity.
const double kTogetherThresholdMeters = 250.0;

/// Represents the overall group proximity status.
class GroupStatus {
  final bool isTogether;
  final int awayCount;
  final int totalSharing;
  final String statusTitle;
  final String statusSubtitle;

  const GroupStatus({
    required this.isTogether,
    required this.awayCount,
    required this.totalSharing,
    required this.statusTitle,
    required this.statusSubtitle,
  });

  factory GroupStatus.evaluate(
    List<double> distancesToMembers, {
    double thresholdMeters = kTogetherThresholdMeters,
  }) {
    if (distancesToMembers.isEmpty) {
      return const GroupStatus(
        isTogether: true,
        awayCount: 0,
        totalSharing: 0,
        statusTitle: 'No other active crew',
        statusSubtitle: 'Invite members to share location on this trip',
      );
    }

    final away = distancesToMembers.where((d) => d > thresholdMeters).length;
    final isTogether = away == 0;

    if (isTogether) {
      return GroupStatus(
        isTogether: true,
        awayCount: 0,
        totalSharing: distancesToMembers.length,
        statusTitle: '🟢 Everyone is together',
        statusSubtitle:
            'All crew members are within ${thresholdMeters.round()}m of each other',
      );
    } else {
      final memberText = away == 1
          ? '1 crew member is'
          : '$away crew members are';
      return GroupStatus(
        isTogether: false,
        awayCount: away,
        totalSharing: distancesToMembers.length,
        statusTitle: '⚠️ $memberText away from the group',
        statusSubtitle:
            '$away of ${distancesToMembers.length} active crew are >${thresholdMeters.round()}m away',
      );
    }
  }
}

/// Geographic distance and bearing calculation utilities.
class LocationCalculator {
  LocationCalculator._();

  static const double earthRadiusMeters = 6371000.0;

  /// Calculates geodesic distance in meters between two lat/lng coordinates (Haversine formula).
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    if (lat1 == lat2 && lon1 == lon2) return 0.0;

    final phi1 = lat1 * (math.pi / 180.0);
    final phi2 = lat2 * (math.pi / 180.0);
    final deltaPhi = (lat2 - lat1) * (math.pi / 180.0);
    final deltaLambda = (lon2 - lon1) * (math.pi / 180.0);

    final a =
        math.sin(deltaPhi / 2.0) * math.sin(deltaPhi / 2.0) +
        math.cos(phi1) *
            math.cos(phi2) *
            math.sin(deltaLambda / 2.0) *
            math.sin(deltaLambda / 2.0);

    final c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a));
    return earthRadiusMeters * c;
  }

  /// Calculates initial forward bearing in degrees (0..360, where 0 is North, 90 is East).
  static double calculateBearing(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final phi1 = lat1 * (math.pi / 180.0);
    final phi2 = lat2 * (math.pi / 180.0);
    final deltaLambda = (lon2 - lon1) * (math.pi / 180.0);

    final y = math.sin(deltaLambda) * math.cos(phi2);
    final x =
        math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);

    final theta = math.atan2(y, x);
    final bearing = theta * (180.0 / math.pi);
    return (bearing + 360.0) % 360.0;
  }

  /// Formats distance in meters: meters under 1km ("120 m away"), km above 1km ("1.3 km away").
  static String formatDistance(double meters) {
    if (meters < 0) return '--';
    if (meters < 1000.0) {
      return '${meters.round()} m away';
    } else {
      final km = meters / 1000.0;
      return '${km.toStringAsFixed(1)} km away';
    }
  }

  /// Compact distance label for badges (e.g. "120m", "1.3km").
  static String formatCompactDistance(double meters) {
    if (meters < 0) return '--';
    if (meters < 1000.0) {
      return '${meters.round()}m';
    } else {
      final km = meters / 1000.0;
      return '${km.toStringAsFixed(1)}km';
    }
  }
}
