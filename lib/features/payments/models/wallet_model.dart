/// Model representing user's TripCrew Wallet balance and transactions.
class WalletTransaction {
  final String id;
  final String title;
  final String subtitle;
  final double amount;
  final bool isCredit;
  final DateTime date;
  final String status;

  const WalletTransaction({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.isCredit,
    required this.date,
    this.status = 'Completed',
  });
}

class WalletModel {
  final double balance;
  final double feePercentage;
  final List<WalletTransaction> recentTransactions;

  const WalletModel({
    this.balance = 5250.0,
    this.feePercentage = 0.01, // 1% platform service fee
    this.recentTransactions = const [],
  });

  /// Calculates the 1% platform service fee for a settlement.
  double calculateFee(double amount) {
    return (amount * feePercentage).roundToDouble();
  }

  /// Calculates total charge including service fee.
  double calculateTotal(double amount) {
    return amount + calculateFee(amount);
  }
}
