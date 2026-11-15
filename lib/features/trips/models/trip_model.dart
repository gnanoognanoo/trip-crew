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
  final String? coverPhotoUrl;
  final double? startLat;
  final double? startLng;
  final double? destLat;
  final double? destLng;
  final String? startingPlaceAddress;
  final String? destinationAddress;
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
    this.budget = 2500.0,
    this.currency = 'INR (₹)',
    required this.inviteCode,
    this.status = 'active',
    this.isActive = true,
    this.memberCount = 1,
    this.totalSpendingPaise = 0,
    this.coverPhotoUrl,
    this.startLat,
    this.startLng,
    this.destLat,
    this.destLng,
    this.startingPlaceAddress,
    this.destinationAddress,
    required this.createdAt,
    required this.updatedAt,
  });

  int get daysToGo {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDay = DateTime(startDate.year, startDate.month, startDate.day);
    return startDay.difference(today).inDays;
  }

  int get durationDays {
    return endDate.difference(startDate).inDays + 1;
  }

  /// Whether the trip was cancelled or not carried out
  bool get isCancelled =>
      status.toLowerCase() == 'cancelled' ||
      status.toLowerCase() == 'not_carried_out' ||
      status.toLowerCase() == 'not_carried_on';

  /// Whether the trip was carried out and completed
  bool get isCompleted =>
      status.toLowerCase() == 'completed' ||
      status.toLowerCase() == 'carried_out' ||
      status.toLowerCase() == 'carried_on';

  /// Has the trip end date completely passed?
  bool get isPast {
    final now = DateTime.now();
    final endDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
    return now.isAfter(endDay);
  }

  /// Is the trip currently taking place (between start and end date)?
  bool get isOngoing {
    if (isCancelled || isCompleted) return false;
    final now = DateTime.now();
    final startDay = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
    final endDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
    return !now.isBefore(startDay) && !now.isAfter(endDay);
  }

  /// Is the trip scheduled for the future?
  bool get isUpcoming {
    if (isCancelled || isCompleted) return false;
    final now = DateTime.now();
    final startDay = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
    return now.isBefore(startDay);
  }

  /// User-friendly label for current lifecycle state
  String get displayStatusLabel {
    if (isCancelled) return 'Cancelled';
    if (isCompleted) return 'Carried Out';
    if (isOngoing) return 'Active Now';
    if (isUpcoming) return 'Upcoming';
    return 'Past Trip';
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
      'coverPhotoUrl': coverPhotoUrl,
      'startLat': startLat,
      'startLng': startLng,
      'destLat': destLat,
      'destLng': destLng,
      'startingPlaceAddress': startingPlaceAddress,
      'destinationAddress': destinationAddress,
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
    final endDay = DateTime(endDateParsed.year, endDateParsed.month, endDateParsed.day, 23, 59, 59);

    if (statusStr.isEmpty) {
      if (now.isAfter(endDay)) {
        statusStr = 'past';
      } else if (startDateParsed.isAfter(today)) {
        statusStr = 'upcoming';
      } else {
        statusStr = 'active';
      }
    } else if ((statusStr == 'upcoming' || statusStr == 'active') && now.isAfter(endDay)) {
      // Reconcile outdated status from database only for non-final statuses
      statusStr = 'past';
    }

    final activeBool = map['isActive'] as bool? ??
        map['is_active'] as bool? ??
        (statusStr == 'active');
    final nameStr = (map['name'] ?? map['title']) as String? ?? 'Trip';
    final coverPhoto = (map['coverPhotoUrl'] ?? map['cover_photo_url']) as String?;

    return TripModel(
      id: id,
      ownerId: (map['ownerId'] ?? map['created_by'] ?? map['owner_id']) as String? ?? '',
      name: nameStr,
      startingPlace: (map['startingPlace'] ?? map['starting_place']) as String? ?? '',
      destination: (map['destination']) as String? ?? '',
      startDate: startDateParsed,
      endDate: endDateParsed,
      tripType: (map['tripType'] ?? map['trip_type']) as String? ?? 'Road Trip',
      budget: ((map['budget'] ?? map['trip_budget']) as num?)?.toDouble() ?? 2500.0,
      currency: map['currency'] as String? ?? 'INR (₹)',
      inviteCode: (map['inviteCode'] ?? map['invite_code']) as String? ?? '',
      status: statusStr,
      isActive: activeBool,
      memberCount: ((map['memberCount'] ?? map['member_count']) as num?)?.toInt() ?? 1,
      totalSpendingPaise: ((map['totalSpendingPaise'] ?? map['total_spending_paise']) as num?)?.toInt() ?? 0,
      coverPhotoUrl: coverPhoto,
      startLat: (map['startLat'] ?? map['start_lat'] as num?)?.toDouble(),
      startLng: (map['startLng'] ?? map['start_lng'] as num?)?.toDouble(),
      destLat: (map['destLat'] ?? map['dest_lat'] as num?)?.toDouble(),
      destLng: (map['destLng'] ?? map['dest_lng'] as num?)?.toDouble(),
      startingPlaceAddress: (map['startingPlaceAddress'] ?? map['starting_place_address']) as String?,
      destinationAddress: (map['destinationAddress'] ?? map['destination_address']) as String?,
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
    String? coverPhotoUrl,
    double? startLat,
    double? startLng,
    double? destLat,
    double? destLng,
    String? startingPlaceAddress,
    String? destinationAddress,
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
      coverPhotoUrl: coverPhotoUrl ?? this.coverPhotoUrl,
      startLat: startLat ?? this.startLat,
      startLng: startLng ?? this.startLng,
      destLat: destLat ?? this.destLat,
      destLng: destLng ?? this.destLng,
      startingPlaceAddress: startingPlaceAddress ?? this.startingPlaceAddress,
      destinationAddress: destinationAddress ?? this.destinationAddress,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
