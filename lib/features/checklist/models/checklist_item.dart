/// Domain model representing a packing checklist item in trips/{tripId}/checklist/{itemId}.
class ChecklistItem {
  final String id;
  final String title;
  final String
  category; // 'Clothes', 'Travel Essentials', 'Health', 'Electronics', 'Trip Specific'
  final bool isCompleted;
  final String? assignedToMemberName;
  final String? assignedToUid;
  final bool isShared;

  const ChecklistItem({
    required this.id,
    required this.title,
    required this.category,
    this.isCompleted = false,
    this.assignedToMemberName,
    this.assignedToUid,
    this.isShared = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'category': category,
      'isCompleted': isCompleted,
      'assignedToMemberName': assignedToMemberName,
      'assignedToUid': assignedToUid,
      'isShared': isShared,
    };
  }

  factory ChecklistItem.fromMap(Map<String, dynamic> map, String id) {
    return ChecklistItem(
      id: id,
      title: map['title'] as String? ?? '',
      category: map['category'] as String? ?? 'Clothes',
      isCompleted: map['isCompleted'] as bool? ?? false,
      assignedToMemberName: map['assignedToMemberName'] as String?,
      assignedToUid: map['assignedToUid'] as String?,
      isShared: map['isShared'] as bool? ?? true,
    );
  }

  ChecklistItem copyWith({
    bool? isCompleted,
    String? assignedToMemberName,
    String? assignedToUid,
  }) {
    return ChecklistItem(
      id: id,
      title: title,
      category: category,
      isCompleted: isCompleted ?? this.isCompleted,
      assignedToMemberName: assignedToMemberName ?? this.assignedToMemberName,
      assignedToUid: assignedToUid ?? this.assignedToUid,
      isShared: isShared,
    );
  }
}
