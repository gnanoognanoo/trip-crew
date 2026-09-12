import 'package:cloud_firestore/cloud_firestore.dart';

/// Domain model representing a shared trip memory in Firestore `trips/{tripId}/memories/{memoryId}`.
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

  /// Backwards-compatible alias for [imageUrl].
  String get mediaUrl => imageUrl;

  /// Backwards-compatible alias for [dayIndex].
  int get dayNumber => dayIndex;

  /// Converts the model into a map for local serialization or Firestore.
  /// If [useServerTimestamp] is true, `createdAt` uses Firestore's `FieldValue.serverTimestamp()`.
  Map<String, dynamic> toFirestoreMap({bool useServerTimestamp = false}) {
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
      'createdAt': useServerTimestamp
          ? FieldValue.serverTimestamp()
          : createdAt.toIso8601String(),
      'capturedAt': capturedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toMap() => toFirestoreMap(useServerTimestamp: false);

  factory MemoryModel.fromMap(Map<String, dynamic> map, String id) {
    // Robust date parsing supporting Firestore Timestamp, ISO string, and int epoch
    DateTime parseDateTime(dynamic raw, DateTime fallback) {
      if (raw is Timestamp) return raw.toDate();
      if (raw is String) return DateTime.tryParse(raw) ?? fallback;
      if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
      return fallback;
    }

    final fallbackNow = DateTime.now();
    final created = parseDateTime(map['createdAt'], fallbackNow);
    final captured = parseDateTime(map['capturedAt'], created);

    // Prefer imageUrl; fallback to legacy mediaUrl
    final resolvedUrl = (map['imageUrl'] as String?)?.isNotEmpty == true
        ? map['imageUrl'] as String
        : (map['mediaUrl'] as String? ?? '');

    // Prefer dayIndex; fallback to legacy dayNumber
    final resolvedDay =
        (map['dayIndex'] as num?)?.toInt() ??
        (map['dayNumber'] as num?)?.toInt() ??
        1;

    return MemoryModel(
      id: id,
      tripId: map['tripId'] as String? ?? '',
      uploaderId: map['uploaderId'] as String? ?? '',
      photographerName: map['photographerName'] as String? ?? 'Crew Member',
      imageUrl: resolvedUrl,
      publicId: map['publicId'] as String? ?? '',
      mediaType: map['mediaType'] as String? ?? 'photo',
      dayIndex: resolvedDay,
      caption: map['caption'] as String?,
      createdAt: created,
      capturedAt: captured,
    );
  }
}
