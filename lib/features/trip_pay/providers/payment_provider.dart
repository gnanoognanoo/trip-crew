import 'package:tripcrew/features/trip_pay/models/payment_intent.dart';
import 'package:tripcrew/features/trip_pay/models/payment_status.dart';
import 'package:tripcrew/features/trip_pay/models/payment_verification.dart';

/// Clean payment provider interface decoupling TripCrew from specific payment SDKs.
///
/// Current implementation: [SandboxPaymentProvider]
/// Production adapters: SetuProvider, RazorpayProvider, CashfreeProvider.
///
/// Note: Secrets (API keys, client secrets, webhook secrets) must NEVER be
/// stored in or accessed directly by client-side code.
abstract class PaymentProvider {
  /// Name or identifier of this payment provider (e.g. 'sandbox', 'setu', 'razorpay').
  String get providerName;

  /// Creates a payment intent for a crew member's contribution.
  /// Generates UPI intent URL / QR payload for external payment initiation.
  Future<PaymentIntent> createContributionIntent({
    required String tripId,
    required String uid,
    required int amountPaise,
    required String clientRequestId,
    Map<String, dynamic>? metadata,
  });

  /// Fetches the latest payment status from the external provider.
  Future<PaymentStatus> fetchPaymentStatus({
    required String paymentIntentId,
    String? providerReference,
  });

  /// Verifies a payment with the provider or trusted backend.
  /// Confirms that money actually settled with the expected amount and currency.
  Future<PaymentVerification> verifyPayment({
    required String paymentIntentId,
    required String providerReference,
    required int expectedAmountPaise,
    String expectedCurrency = 'INR',
  });

  /// Processes an external webhook payload with cryptographic signature verification.
  Future<PaymentVerification> processWebhook({
    required String payload,
    required String signature,
    required String secret,
  });

  /// Initiates a contribution refund via the external provider rail.
  Future<PaymentVerification> refundContribution({
    required String paymentIntentId,
    required String providerReference,
    required int amountPaise,
    required String reason,
  });
}
