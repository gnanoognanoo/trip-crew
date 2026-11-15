import 'package:intl/intl.dart';

enum MessageType {
  text,
  voice,
  location;

  static MessageType fromString(String? val) {
    if (val == 'voice') return MessageType.voice;
    if (val == 'location') return MessageType.location;
    return MessageType.text;
  }
}

class ChatMessage {
  final String id;
  final String tripId;
  final String userId;
  final String userName;
  final MessageType messageType;
  final String content;
  final int audioDurationSeconds;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.tripId,
    required this.userId,
    required this.userName,
    this.messageType = MessageType.text,
    required this.content,
    this.audioDurationSeconds = 0,
    this.latitude,
    this.longitude,
    required this.createdAt,
  });

  bool isMe(String currentUid) => userId == currentUid;
  bool get isVoice => messageType == MessageType.voice;
  bool get isLocation => messageType == MessageType.location;
  bool get isText => messageType == MessageType.text;

  String get formattedTime => DateFormat('hh:mm a').format(createdAt);

  String get formattedAudioDuration {
    final m = audioDurationSeconds ~/ 60;
    final s = audioDurationSeconds % 60;
    return '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'trip_id': tripId,
      'user_id': userId,
      'user_name': userName,
      'message_type': messageType.name,
      'content': content,
      'audio_duration_seconds': audioDurationSeconds,
      'latitude': latitude,
      'longitude': longitude,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v.toLocal();
      if (v is String) {
        final parsed = DateTime.tryParse(v);
        if (parsed != null) {
          final local = parsed.toLocal();
          // Guard against double timezone shift (if local is >2 min in the future)
          if (local.isAfter(DateTime.now().add(const Duration(minutes: 2)))) {
            return parsed;
          }
          return local;
        }
      }
      return DateTime.now();
    }

    return ChatMessage(
      id: map['id']?.toString() ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
      tripId: map['trip_id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      userName: map['user_name']?.toString() ?? 'Traveler',
      messageType: MessageType.fromString(map['message_type']?.toString()),
      content: map['content']?.toString() ?? '',
      audioDurationSeconds: (map['audio_duration_seconds'] as num?)?.toInt() ?? 0,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      createdAt: parseDate(map['created_at']),
    );
  }
}

