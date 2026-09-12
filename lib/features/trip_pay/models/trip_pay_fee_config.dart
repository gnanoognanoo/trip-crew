/// Fee configuration for TripCrew Pay platform service fee.
///
/// Uses integer basis-point arithmetic to avoid floating-point precision issues.
/// 100 basis points = 1%. All calculations are in paise (smallest currency unit).
///
/// Designed for future override via Firebase Remote Config.
class TripPayFeeConfig {
  TripPayFeeConfig._();

  /// Platform fee rate in basis points. 100 bp = 1%.
  static const int feeRateBasisPoints = 100;

  /// Calculates the platform fee in paise using integer arithmetic.
  ///
  /// Formula: amountPaise * feeRateBasisPoints ~/ 10000
  ///
  /// Example:
  ///   ₹5,000 = 500000 paise
  ///   fee = 500000 * 100 ~/ 10000 = 5000 paise = ₹50
  static int calculateFeePaise(int amountPaise) {
    if (amountPaise <= 0) return 0;
    return amountPaise * feeRateBasisPoints ~/ 10000;
  }

  /// Returns the total charge (amount + fee) in paise.
  static int calculateTotalPaise(int amountPaise) {
    return amountPaise + calculateFeePaise(amountPaise);
  }

  /// Returns the fee rate as a human-readable percentage string.
  static String get feePercentageLabel {
    final percent = feeRateBasisPoints / 100;
    return '${percent.toStringAsFixed(percent.truncateToDouble() == percent ? 0 : 1)}%';
  }
}
