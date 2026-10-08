/// Domain model representing a member inside trips/{tripId}/members/{uid}.
class CrewMember {
  final String uid;
  final String displayName;
  final String role; // 'owner' or 'member'
  final String? photoUrl;
  final bool isOnline;
  final DateTime joinedAt;

  const CrewMember({
    required this.uid,
    required this.displayName,
    this.role = 'member',
    this.photoUrl,
    this.isOnline = true,
    required this.joinedAt,
  });

  bool get isOwner => role == 'owner';

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'displayName': displayName,
      'role': role,
      'photoUrl': photoUrl,
      'isOnline': isOnline,
      'joinedAt': joinedAt.toIso8601String(),
    };
  }

  factory CrewMember.fromMap(Map<String, dynamic> map, String id) {
    return CrewMember(
      uid: (map['uid'] ?? map['user_id'] ?? id) as String,
      displayName: (map['displayName'] ?? map['display_name']) as String? ?? 'Member',
      role: map['role'] as String? ?? 'member',
      photoUrl: (map['photoUrl'] ?? map['photo_url']) as String?,
      isOnline: map['isOnline'] as bool? ?? true,
      joinedAt: map['joinedAt'] != null
          ? DateTime.tryParse(map['joinedAt'].toString()) ?? DateTime.now()
          : (map['joined_at'] != null
              ? DateTime.tryParse(map['joined_at'].toString()) ?? DateTime.now()
              : DateTime.now()),
    );
  }
}
