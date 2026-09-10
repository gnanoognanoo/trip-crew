/// Domain model representing a shared trip memory in trips/{tripId}/memories/{memoryId}.
class MemoryModel {
  final String id;
  final String tripId;
  final String uploaderId;
  final String photographerName;
  final String mediaUrl;
  final String mediaType; // 'photo' or 'video'
  final int dayNumber;
  final String? caption;
  final DateTime createdAt;

  const MemoryModel({
    required this.id,
    required this.tripId,
    required this.uploaderId,
    required this.photographerName,
    required this.mediaUrl,
    this.mediaType = 'photo',
    this.dayNumber = 1,
    this.caption,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tripId': tripId,
      'uploaderId': uploaderId,
      'photographerName': photographerName,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'dayNumber': dayNumber,
      'caption': caption,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory MemoryModel.fromMap(Map<String, dynamic> map, String id) {
    return MemoryModel(
      id: id,
      tripId: map['tripId'] as String? ?? '',
      uploaderId: map['uploaderId'] as String? ?? '',
      photographerName: map['photographerName'] as String? ?? 'Crew Member',
      mediaUrl: map['mediaUrl'] as String? ?? '',
      mediaType: map['mediaType'] as String? ?? 'photo',
      dayNumber: (map['dayNumber'] as num?)?.toInt() ?? 1,
      caption: map['caption'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
