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
      description: map['description'] as String? ?? 'Expense',
      amountPaise: (map['amountPaise'] as num?)?.toInt() ?? 0,
      category: map['category'] as String? ?? 'Food',
      paidByUid: map['paidByUid'] as String? ?? '',
      paidByName: map['paidByName'] as String? ?? 'Member',
      participantUids:
          (map['participantUids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      splitType: map['splitType'] as String? ?? 'equal',
      createdBy: map['createdBy'] as String? ?? '',
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
