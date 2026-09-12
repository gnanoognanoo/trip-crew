import 'package:tripcrew/features/trip_pay/models/payment_status.dart';

/// Maps UPI Setu event strings and status codes to TripCrew domain [PaymentStatus].
///
/// Supports official UPI Setu payment lifecycle events:
/// - `payment.initiated`: Payment has been initiated by customer (maps to [PaymentStatus.pending])
/// - `payment.pending`: Payment is being processed by UPI Setu (maps to [PaymentStatus.pending])
/// - `payment.success`: Payment completed successfully (maps to [PaymentStatus.success])
/// - `payment.failed`: Payment failed or was declined (maps to [PaymentStatus.failed])
///
/// Fail-safe: Any unrecognized or ambiguous status safely resolves to [PaymentStatus.pending].
class SetuStatusMapper {
  const SetuStatusMapper._();

  /// Primary mapping for UPI Setu webhook event types (e.g. 'payment.initiated', 'payment.success').
  static PaymentStatus fromEventType(String? eventType) {
    if (eventType == null || eventType.trim().isEmpty) {
      return PaymentStatus.pending;
    }

    final normalized = eventType.trim().toLowerCase();

    switch (normalized) {
      // UPI Setu Payment Events
      case 'payment.success':
      case 'success':
      case 'successful':
        return PaymentStatus.success;

      case 'payment.failed':
      case 'failed':
      case 'declined':
      case 'user_dropped':
      case 'cancelled':
        return PaymentStatus.failed;

      case 'payment.initiated':
      case 'initiated':
      case 'payment.pending':
      case 'pending':
        return PaymentStatus.pending;

      // Refund Events (for future enablement)
      case 'refund.success':
      case 'refund_successful':
      case 'refunded':
        return PaymentStatus.refunded;

      default:
        return fromSetuStatus(eventType);
    }
  }

  /// Maps a Setu status or event string to [PaymentStatus].
  static PaymentStatus fromSetuStatus(String? status) {
    if (status == null || status.trim().isEmpty) {
      return PaymentStatus.pending;
    }

    final normalized = status.trim().toUpperCase();

    switch (normalized) {
      // Successful states
      case 'PAYMENT.SUCCESS':
      case 'PAYMENT_SUCCESS':
      case 'PAYMENT_SUCCESSFUL':
      case 'SUCCESS':
      case 'SUCCESSFUL':
      case 'BILL_PAID':
      case 'PAID':
      case 'SETTLED':
        return PaymentStatus.success;

      // Failed states
      case 'PAYMENT.FAILED':
      case 'PAYMENT_FAILED':
      case 'FAILED':
      case 'DECLINED':
      case 'USER_DROPPED':
      case 'CANCELLED':
        return PaymentStatus.failed;

      // Pending / Initiated states
      case 'PAYMENT.INITIATED':
      case 'PAYMENT_INITIATED':
      case 'INITIATED':
      case 'PAYMENT.PENDING':
      case 'PAYMENT_PENDING':
      case 'PENDING':
      case 'BILL_CREATED':
      case 'CREATED':
      case 'BAV_REVERSE_PENNY_DROP_CREATED':
        return PaymentStatus.pending;

      // Expired states
      case 'BILL_EXPIRED':
      case 'EXPIRED':
      case 'TIMEOUT':
        return PaymentStatus.expired;

      // Refunded states
      case 'REFUND.SUCCESS':
      case 'REFUND_SUCCESSFUL':
      case 'REFUNDED':
        return PaymentStatus.refunded;

      // Safe fallback for unmapped statuses
      default:
        return PaymentStatus.pending;
    }
  }
}
