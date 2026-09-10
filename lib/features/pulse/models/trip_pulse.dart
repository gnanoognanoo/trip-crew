/// Domain model for Trip Pulse statuses inside trips/{tripId}/pulses/{uid}.
class TripPulse {
  final String uid;
  final String memberName;
  final String
  pulseType; // Hungry, Need Coffee, Need Fuel, Restroom, Tired, Want Photos, Need Break, Emergency
  final DateTime timestamp;

  const TripPulse({
    required this.uid,
    required this.memberName,
    required this.pulseType,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'memberName': memberName,
      'pulseType': pulseType,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory TripPulse.fromMap(Map<String, dynamic> map, String id) {
    return TripPulse(
      uid: id,
      memberName: map['memberName'] as String? ?? 'Crew Member',
      pulseType: map['pulseType'] as String? ?? 'Hungry',
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
