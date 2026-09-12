/// Domain model representing a Trip in trips/{tripId}.
class TripModel {
  final String id;
  final String ownerId;
  final String name;
  final String startingPlace;
  final String destination;
  final DateTime startDate;
  final DateTime endDate;
  final String tripType; // Road Trip, Vacation, Family, Adventure, Custom
  final double budget;
  final String currency;
  final String inviteCode;
  final String status; // active, upcoming, completed
  final int memberCount;
  final int totalSpendingPaise;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TripModel({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.startingPlace,
    required this.destination,
    required this.startDate,
    required this.endDate,
    this.tripType = 'Road Trip',
    this.budget = 20000.0,
    this.currency = 'INR (₹)',
    required this.inviteCode,
    this.status = 'upcoming',
    this.memberCount = 1,
    this.totalSpendingPaise = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  int get daysToGo {
    final now = DateTime.now();
    final difference = startDate
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    return difference < 0 ? 0 : difference;
  }

  int get durationDays {
    return endDate.difference(startDate).inDays + 1;
  }

  bool get isActive {
    final now = DateTime.now();
    return now.isAfter(startDate.subtract(const Duration(hours: 12))) &&
        now.isBefore(endDate.add(const Duration(hours: 24)));
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ownerId': ownerId,
      'name': name,
      'startingPlace': startingPlace,
      'destination': destination,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'tripType': tripType,
      'budget': budget,
      'currency': currency,
      'inviteCode': inviteCode,
      'status': status,
      'memberCount': memberCount,
      'totalSpendingPaise': totalSpendingPaise,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory TripModel.fromMap(Map<String, dynamic> map, String id) {
    return TripModel(
      id: id,
      ownerId: map['ownerId'] as String? ?? '',
      name: map['name'] as String? ?? 'Trip',
      startingPlace: map['startingPlace'] as String? ?? '',
      destination: map['destination'] as String? ?? '',
      startDate: map['startDate'] != null
          ? DateTime.tryParse(map['startDate'].toString()) ?? DateTime.now()
          : DateTime.now(),
      endDate: map['endDate'] != null
          ? DateTime.tryParse(map['endDate'].toString()) ?? DateTime.now()
          : DateTime.now().add(const Duration(days: 3)),
      tripType: map['tripType'] as String? ?? 'Road Trip',
      budget: (map['budget'] as num?)?.toDouble() ?? 20000.0,
      currency: map['currency'] as String? ?? 'INR (₹)',
      inviteCode: map['inviteCode'] as String? ?? '',
      status: map['status'] as String? ?? 'upcoming',
      memberCount: (map['memberCount'] as num?)?.toInt() ?? 1,
      totalSpendingPaise: (map['totalSpendingPaise'] as num?)?.toInt() ?? 0,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  TripModel copyWith({
    String? name,
    String? startingPlace,
    String? destination,
    DateTime? startDate,
    DateTime? endDate,
    String? tripType,
    double? budget,
    String? currency,
    String? status,
    int? memberCount,
    int? totalSpendingPaise,
  }) {
    return TripModel(
      id: id,
      ownerId: ownerId,
      name: name ?? this.name,
      startingPlace: startingPlace ?? this.startingPlace,
      destination: destination ?? this.destination,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      tripType: tripType ?? this.tripType,
      budget: budget ?? this.budget,
      currency: currency ?? this.currency,
      inviteCode: inviteCode,
      status: status ?? this.status,
      memberCount: memberCount ?? this.memberCount,
      totalSpendingPaise: totalSpendingPaise ?? this.totalSpendingPaise,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
