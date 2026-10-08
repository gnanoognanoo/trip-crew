/// Domain representation of an authenticated user profile stored in Firestore users/{uid}.
class UserProfile {
  final String uid;
  final String name;
  final String email;
  final String? phone;
  final String? photoUrl;
  final int tripCount;
  final int distanceKm;
  final int memoryCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserProfile({
    required this.uid,
    required this.name,
    required this.email,
    this.phone,
    this.photoUrl,
    this.tripCount = 0,
    this.distanceKm = 0,
    this.memoryCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': uid,
      'uid': uid,
      'full_name': name,
      'name': name,
      'email': email,
      'phone': phone,
      'avatar_url': photoUrl,
      'photoUrl': photoUrl,
      'tripCount': tripCount,
      'distanceKm': distanceKm,
      'memoryCount': memoryCount,
      'created_at': createdAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map, String id) {
    return UserProfile(
      uid: (map['uid'] ?? map['id']) as String? ?? id,
      name: (map['name'] ?? map['full_name']) as String? ?? 'Traveler',
      email: map['email'] as String? ?? '',
      phone: map['phone'] as String?,
      photoUrl: (map['photoURL'] ?? map['photoUrl'] ?? map['avatar_url']) as String?,
      tripCount: (map['tripCount'] as num?)?.toInt() ?? 0,
      distanceKm: (map['distanceKm'] as num?)?.toInt() ?? 0,
      memoryCount: (map['memoryCount'] as num?)?.toInt() ?? 0,
      createdAt: (map['createdAt'] ?? map['created_at']) != null
          ? DateTime.tryParse((map['createdAt'] ?? map['created_at']).toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: (map['updatedAt'] ?? map['updated_at']) != null
          ? DateTime.tryParse((map['updatedAt'] ?? map['updated_at']).toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  UserProfile copyWith({
    String? name,
    String? email,
    String? phone,
    String? photoUrl,
    int? tripCount,
    int? distanceKm,
    int? memoryCount,
  }) {
    return UserProfile(
      uid: uid,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      photoUrl: photoUrl ?? this.photoUrl,
      tripCount: tripCount ?? this.tripCount,
      distanceKm: distanceKm ?? this.distanceKm,
      memoryCount: memoryCount ?? this.memoryCount,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
