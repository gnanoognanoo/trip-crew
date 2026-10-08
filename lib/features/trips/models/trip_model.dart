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
  final bool isActive;
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
    this.status = 'active',
    this.isActive = true,
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
      'isActive': isActive,
      'memberCount': memberCount,
      'totalSpendingPaise': totalSpendingPaise,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory TripModel.fromMap(Map<String, dynamic> map, String id) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final startDateParsed = map['startDate'] != null
        ? DateTime.tryParse(map['startDate'].toString()) ?? today
        : (map['start_date'] != null
            ? DateTime.tryParse(map['start_date'].toString()) ?? today
            : today);

    final endDateParsed = map['endDate'] != null
        ? DateTime.tryParse(map['endDate'].toString()) ?? today.add(const Duration(days: 3))
        : (map['end_date'] != null
            ? DateTime.tryParse(map['end_date'].toString()) ?? today.add(const Duration(days: 3))
            : today.add(const Duration(days: 3)));

    String statusStr = (map['status'] ?? map['trip_status']) as String? ?? '';
    if (statusStr.isEmpty) {
      if (startDateParsed.isAfter(today)) {
        statusStr = 'upcoming';
      } else if (endDateParsed.isBefore(today)) {
        statusStr = 'completed';
      } else {
        statusStr = 'active';
      }
    }

    final activeBool = map['isActive'] as bool? ??
        map['is_active'] as bool? ??
        (statusStr == 'active');
    final nameStr = (map['name'] ?? map['title']) as String? ?? 'Trip';

    return TripModel(
      id: id,
      ownerId: (map['ownerId'] ?? map['created_by'] ?? map['owner_id']) as String? ?? '',
      name: nameStr,
      startingPlace: (map['startingPlace'] ?? map['starting_place']) as String? ?? '',
      destination: (map['destination']) as String? ?? '',
      startDate: startDateParsed,
      endDate: endDateParsed,
      tripType: (map['tripType'] ?? map['trip_type']) as String? ?? 'Road Trip',
      budget: (map['budget'] as num?)?.toDouble() ?? 20000.0,
      currency: map['currency'] as String? ?? 'INR (₹)',
      inviteCode: (map['inviteCode'] ?? map['invite_code']) as String? ?? '',
      status: statusStr,
      isActive: activeBool,
      memberCount: ((map['memberCount'] ?? map['member_count']) as num?)?.toInt() ?? 1,
      totalSpendingPaise: ((map['totalSpendingPaise'] ?? map['total_spending_paise']) as num?)?.toInt() ?? 0,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : (map['created_at'] != null
              ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
              : DateTime.now()),
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'].toString()) ?? DateTime.now()
          : (map['updated_at'] != null
              ? DateTime.tryParse(map['updated_at'].toString()) ?? DateTime.now()
              : DateTime.now()),
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
    bool? isActive,
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
      isActive: isActive ?? this.isActive,
      memberCount: memberCount ?? this.memberCount,
      totalSpendingPaise: totalSpendingPaise ?? this.totalSpendingPaise,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
