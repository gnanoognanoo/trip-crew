import 'package:intl/intl.dart';

/// Utilities for decimal-safe money and currency presentation.
class CurrencyFormatter {
  CurrencyFormatter._();

  /// Converts an amount in rupees (e.g. 1200.50) to smallest currency unit (paise: 120050).
  static int toSmallestUnit(double amount) {
    return (amount * 100).round();
  }

  /// Converts smallest currency unit (paise: 120050) back to rupees (1200.50).
  static double fromSmallestUnit(int units) {
    return units / 100.0;
  }

  /// Formats an amount with currency symbol (e.g. ₹18,450 or ₹1,200.50).
  static String format(
    double amount, {
    String currency = '₹',
    bool showDecimals = false,
  }) {
    final format = NumberFormat.currency(
      symbol: currency,
      decimalDigits: showDecimals ? 2 : 0,
      locale: 'en_IN',
    );
    return format.format(amount);
  }

  /// Formats paise units directly.
  static String formatUnits(
    int units, {
    String currency = '₹',
    bool showDecimals = false,
  }) {
    return format(
      fromSmallestUnit(units),
      currency: currency,
      showDecimals: showDecimals,
    );
  }
}
