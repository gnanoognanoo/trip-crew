/// Domain model representing a shared trip memory in memories table.
///
/// Stores Cloudinary media references and trip metadata:
/// [tripId], [uploaderId], [imageUrl], [publicId], [caption], [createdAt], [capturedAt], [dayIndex].
class MemoryModel {
  final String id;
  final String tripId;
  final String uploaderId;
  final String photographerName;
  final String imageUrl;
  final String publicId;
  final String mediaType; // 'photo' or 'video'
  final int dayIndex;
  final String? caption;
  final DateTime createdAt;
  final DateTime capturedAt;

  const MemoryModel({
    required this.id,
    required this.tripId,
    required this.uploaderId,
    this.photographerName = 'Crew Member',
    required this.imageUrl,
    this.publicId = '',
    this.mediaType = 'photo',
    this.dayIndex = 1,
    this.caption,
    required this.createdAt,
    DateTime? capturedAt,
  }) : capturedAt = capturedAt ?? createdAt;

  String get mediaUrl => imageUrl;
  int get dayNumber => dayIndex;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tripId': tripId,
      'uploaderId': uploaderId,
      'photographerName': photographerName,
      'imageUrl': imageUrl,
      'publicId': publicId,
      'mediaType': mediaType,
      'dayIndex': dayIndex,
      'caption': caption,
      'createdAt': createdAt.toIso8601String(),
      'capturedAt': capturedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toFirestoreMap({bool useServerTimestamp = false}) => toMap();

  factory MemoryModel.fromMap(Map<String, dynamic> map, String id) {
    DateTime parseDateTime(dynamic raw, DateTime fallback) {
      if (raw is String) return DateTime.tryParse(raw) ?? fallback;
      if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
      return fallback;
    }

    final fallbackNow = DateTime.now();
    final created = parseDateTime(map['createdAt'] ?? map['created_at'], fallbackNow);
    final captured = parseDateTime(map['capturedAt'] ?? map['captured_at'], created);

    final resolvedUrl = (map['imageUrl'] ?? map['media_url'] ?? map['mediaUrl']) as String? ?? '';

    final resolvedDay =
        (map['dayIndex'] ?? map['day_index'] ?? map['dayNumber']) as num? ?? 1;

    return MemoryModel(
      id: id,
      tripId: (map['tripId'] ?? map['trip_id']) as String? ?? '',
      uploaderId: (map['uploaderId'] ?? map['user_id'] ?? map['uploader_id']) as String? ?? '',
      photographerName: (map['photographerName'] ?? map['photographer_name']) as String? ?? 'Crew Member',
      imageUrl: resolvedUrl,
      publicId: (map['publicId'] ?? map['cloudinary_public_id']) as String? ?? '',
      mediaType: (map['mediaType'] ?? map['media_type']) as String? ?? 'photo',
      dayIndex: resolvedDay.toInt(),
      caption: map['caption'] as String?,
      createdAt: created,
      capturedAt: captured,
    );
  }
}
