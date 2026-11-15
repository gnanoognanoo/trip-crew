import 'dart:convert';

/// Domain model representing an itinerary stop in trips/{tripId}/itinerary/{itemId}.
class ItineraryItem {
  final String id;
  final int dayNumber; // Day 1, Day 2, etc.
  final String time; // e.g. "07:00 AM"
  final String title; // e.g. "Start from Chennai"
  final String? placeName;
  final String? notes;
  final bool isVisited;
  final int order;
  final double? latitude;
  final double? longitude;

  const ItineraryItem({
    required this.id,
    required this.dayNumber,
    required this.time,
    required this.title,
    this.placeName,
    this.notes,
    this.isVisited = false,
    required this.order,
    this.latitude,
    this.longitude,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'dayNumber': dayNumber,
      'day_number': dayNumber,
      'time': time,
      'title': title,
      'placeName': placeName,
      'location': placeName,
      'notes': notes,
      'isVisited': isVisited,
      'is_visited': isVisited,
      'order': order,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory ItineraryItem.fromMap(Map<String, dynamic> map, String id) {
    int parsedDay = ((map['dayNumber'] ?? map['day_number']) as num?)?.toInt() ?? 1;
    String parsedTime = map['time'] as String? ?? '10:00 AM';
    String? userNotes = map['notes'] as String?;
    final notesRaw = map['notes'] as String?;
    if (notesRaw != null && notesRaw.startsWith('{') && notesRaw.endsWith('}')) {
      try {
        final decoded = jsonDecode(notesRaw) as Map<String, dynamic>;
        if (decoded.containsKey('day')) {
          parsedDay = (decoded['day'] as num).toInt();
        } else if (decoded.containsKey('dayNumber')) {
          parsedDay = (decoded['dayNumber'] as num).toInt();
        } else if (decoded.containsKey('day_number')) {
          parsedDay = (decoded['day_number'] as num).toInt();
        }
        if (decoded.containsKey('time')) {
          parsedTime = decoded['time'] as String;
        }
        if (decoded.containsKey('notes')) {
          userNotes = decoded['notes'] as String?;
        } else if (decoded.containsKey('note')) {
          userNotes = decoded['note'] as String?;
        }
      } catch (_) {}
    }

    return ItineraryItem(
      id: id,
      dayNumber: parsedDay,
      time: parsedTime,
      title: map['title'] as String? ?? '',
      placeName: (map['placeName'] ?? map['location']) as String?,
      notes: userNotes,
      isVisited: (map['isVisited'] ?? map['is_visited'] ?? map['is_completed']) as bool? ?? false,
      order: (map['order'] as num?)?.toInt() ?? 0,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
    );
  }

  ItineraryItem copyWith({
    bool? isVisited,
    String? title,
    String? time,
    String? placeName,
    String? notes,
    int? dayNumber,
    double? latitude,
    double? longitude,
  }) {
    return ItineraryItem(
      id: id,
      dayNumber: dayNumber ?? this.dayNumber,
      time: time ?? this.time,
      title: title ?? this.title,
      placeName: placeName ?? this.placeName,
      notes: notes ?? this.notes,
      isVisited: isVisited ?? this.isVisited,
      order: order,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }
}
