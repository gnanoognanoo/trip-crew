import 'package:tripcrew/features/trip_pay/models/payment_status.dart';

/// Pure domain utility mapping Razorpay status codes and event types to domain [PaymentStatus].
class RazorpayStatusMapper {
  RazorpayStatusMapper._();

  /// Maps a Razorpay API status string (order/payment status) into a domain [PaymentStatus].
  static PaymentStatus fromRazorpayStatus(String? status) {
    if (status == null || status.trim().isEmpty) {
      return PaymentStatus.pending;
    }

    final normalized = status.trim().toLowerCase();

    switch (normalized) {
      case 'created':
      case 'attempted':
      case 'authorized':
      case 'pending':
        return PaymentStatus.pending;

      case 'captured':
      case 'paid':
      case 'success':
      case 'successful':
      case 'payment.captured':
      case 'order.paid':
        return PaymentStatus.success;

      case 'failed':
      case 'cancelled':
      case 'rejected':
      case 'payment.failed':
        return PaymentStatus.failed;

      case 'expired':
      case 'timeout':
        return PaymentStatus.expired;

      case 'refunded':
        return PaymentStatus.refunded;

      default:
        return PaymentStatus.pending;
    }
  }

  /// Maps a Razorpay webhook event string (e.g. `payment.captured`, `payment.failed`)
  /// into a domain [PaymentStatus].
  static PaymentStatus fromEventType(String? eventType) {
    if (eventType == null || eventType.trim().isEmpty) {
      return PaymentStatus.pending;
    }

    final normalized = eventType.trim().toLowerCase();

    if (normalized.contains('captured') || normalized == 'order.paid') {
      return PaymentStatus.success;
    }
    if (normalized.contains('failed')) {
      return PaymentStatus.failed;
    }
    if (normalized.contains('authorized') || normalized.contains('created')) {
      return PaymentStatus.pending;
    }
    if (normalized.contains('refunded')) {
      return PaymentStatus.refunded;
    }

    return fromRazorpayStatus(eventType);
  }
}
