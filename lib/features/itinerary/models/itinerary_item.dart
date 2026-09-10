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

  const ItineraryItem({
    required this.id,
    required this.dayNumber,
    required this.time,
    required this.title,
    this.placeName,
    this.notes,
    this.isVisited = false,
    required this.order,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'dayNumber': dayNumber,
      'time': time,
      'title': title,
      'placeName': placeName,
      'notes': notes,
      'isVisited': isVisited,
      'order': order,
    };
  }

  factory ItineraryItem.fromMap(Map<String, dynamic> map, String id) {
    return ItineraryItem(
      id: id,
      dayNumber: (map['dayNumber'] as num?)?.toInt() ?? 1,
      time: map['time'] as String? ?? '10:00 AM',
      title: map['title'] as String? ?? '',
      placeName: map['placeName'] as String?,
      notes: map['notes'] as String?,
      isVisited: map['isVisited'] as bool? ?? false,
      order: (map['order'] as num?)?.toInt() ?? 0,
    );
  }

  ItineraryItem copyWith({bool? isVisited, String? title, String? time}) {
    return ItineraryItem(
      id: id,
      dayNumber: dayNumber,
      time: time ?? this.time,
      title: title ?? this.title,
      placeName: placeName,
      notes: notes,
      isVisited: isVisited ?? this.isVisited,
      order: order,
    );
  }
}
