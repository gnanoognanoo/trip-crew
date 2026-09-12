import 'package:tripcrew/features/trip_pay/models/trip_pay_transaction.dart';

/// Abstract payment provider interface for TripCrew Pay.
///
/// Current implementation: [SandboxTripPayProvider]
/// Future implementations may include licensed payment partners supporting
/// UPI, RuPay, or bank-linked payments.
///
/// This abstraction isolates business/UI logic from payment processing.
abstract class TripPayProvider {
  /// Creates a contribution to the shared trip pot.
  Future<TripPayTransaction> createContribution({
    required String tripId,
    required int amountPaise,
    required String initiatedByUid,
    required String initiatedByName,
    required String clientRequestId,
  });

  /// Creates a payment from the shared trip pot.
  Future<TripPayTransaction> createPayment({
    required String tripId,
    required int amountPaise,
    required String initiatedByUid,
    required String initiatedByName,
    required String description,
    required String category,
    String? merchantName,
    required String clientRequestId,
  });

  /// Creates a refund transaction referencing the original payment.
  Future<TripPayTransaction> refundPayment({
    required String tripId,
    required String originalTransactionId,
    required int amountPaise,
    required String initiatedByUid,
    required String initiatedByName,
    required String clientRequestId,
  });

  /// Queries the current status of a transaction.
  Future<TripPayTransactionStatus> getTransactionStatus(
    String tripId,
    String transactionId,
  );
}
