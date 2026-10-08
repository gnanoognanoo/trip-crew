/// Domain model representing a trip expense in trips/{tripId}/expenses/{expenseId}.
class ExpenseModel {
  final String id;
  final String description;
  final int amountPaise; // Decimal-safe integer paise: ₹1200.50 -> 120050
  final String category; // Food, Travel, Stay, Fuel, Tickets, Shopping, Other
  final String paidByUid;
  final String paidByName;
  final List<String> participantUids;
  final String splitType; // equal, exact, percentage
  final String createdBy;
  final DateTime createdAt;

  const ExpenseModel({
    required this.id,
    required this.description,
    required this.amountPaise,
    required this.category,
    required this.paidByUid,
    required this.paidByName,
    required this.participantUids,
    this.splitType = 'equal',
    required this.createdBy,
    required this.createdAt,
  });

  double get amountRupees => amountPaise / 100.0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'description': description,
      'amountPaise': amountPaise,
      'category': category,
      'paidByUid': paidByUid,
      'paidByName': paidByName,
      'participantUids': participantUids,
      'splitType': splitType,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ExpenseModel.fromMap(Map<String, dynamic> map, String id) {
    return ExpenseModel(
      id: id,
      description: (map['description'] ?? map['title']) as String? ?? 'Expense',
      amountPaise: ((map['amountPaise'] ?? map['amount_paise']) as num?)?.toInt() ?? 0,
      category: map['category'] as String? ?? 'Food',
      paidByUid: (map['paidByUid'] ?? map['paid_by_user_id']) as String? ?? '',
      paidByName: (map['paidByName'] ?? map['paid_by_name']) as String? ?? 'Member',
      participantUids:
          (map['participantUids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      splitType: (map['splitType'] ?? map['split_type']) as String? ?? 'equal',
      createdBy: (map['createdBy'] ?? map['created_by']) as String? ?? '',
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : (map['created_at'] != null
              ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
              : DateTime.now()),
    );
  }
}
