import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:tripcrew/features/trip_pay/models/payment_intent.dart';
import 'package:tripcrew/features/trip_pay/models/payment_status.dart';
import 'package:tripcrew/features/trip_pay/models/payment_verification.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_fee_config.dart';
import 'package:tripcrew/features/trip_pay/providers/payment_provider.dart';

/// Sandbox implementation of [PaymentProvider] for UPI contribution flows.
///
/// Simulates UPI payment intents, QR payloads, verification, and webhook processing
/// without moving real customer money or storing payment gateway secrets in Flutter.
///
/// Can be configured in developer/test mode to simulate:
/// - pending
/// - success
/// - failed
/// - expired / timeout
class SandboxPaymentProvider implements PaymentProvider {
  PaymentStatus simulatedStatus;
  Duration simulatedDelay;

  SandboxPaymentProvider({
    this.simulatedStatus = PaymentStatus.success,
    this.simulatedDelay = const Duration(milliseconds: 300),
  });

  @override
  String get providerName => 'sandbox';

  @override
  Future<PaymentIntent> createContributionIntent({
    required String tripId,
    required String uid,
    required int amountPaise,
    required String clientRequestId,
    Map<String, dynamic>? metadata,
  }) async {
    if (simulatedDelay > Duration.zero) {
      await Future.delayed(simulatedDelay);
    }

    final feePaise = TripPayFeeConfig.calculateFeePaise(amountPaise);
    final totalChargePaise = amountPaise + feePaise;
    final intentId =
        'pi_sb_${DateTime.now().millisecondsSinceEpoch}_${clientRequestId.hashCode.abs()}';
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(minutes: 15));

    final amountRupees = (totalChargePaise / 100.0).toStringAsFixed(2);
    final upiUrl =
        'upi://pay?pa=tripcrew.sandbox@upi&pn=TripCrew%20Trip%20Pot'
        '&am=$amountRupees&cu=INR&tn=Contribution%20to%20Trip';

    return PaymentIntent(
      id: intentId,
      tripId: tripId,
      uid: uid,
      amountPaise: amountPaise,
      platformFeePaise: feePaise,
      totalChargePaise: totalChargePaise,
      currency: 'INR',
      clientRequestId: clientRequestId,
      provider: providerName,
      status: PaymentStatus.created,
      upiIntentUrl: upiUrl,
      qrCodeData: upiUrl,
      paymentUrl: 'https://sandbox.tripcrew.app/pay/$intentId',
      createdAt: now,
      expiresAt: expiresAt,
      metadata: metadata ?? {},
    );
  }

  @override
  Future<PaymentStatus> fetchPaymentStatus({
    required String paymentIntentId,
    String? providerReference,
  }) async {
    if (simulatedDelay > Duration.zero) {
      await Future.delayed(simulatedDelay);
    }
    return simulatedStatus;
  }

  @override
  Future<PaymentVerification> verifyPayment({
    required String paymentIntentId,
    required String providerReference,
    required int expectedAmountPaise,
    String expectedCurrency = 'INR',
  }) async {
    if (simulatedDelay > Duration.zero) {
      await Future.delayed(simulatedDelay);
    }

    if (expectedCurrency != 'INR') {
      return PaymentVerification(
        isVerified: false,
        providerReference: providerReference,
        paymentIntentId: paymentIntentId,
        status: PaymentStatus.failed,
        amountPaise: 0,
        currency: expectedCurrency,
        verifiedAt: DateTime.now(),
        failureReason: 'Unsupported currency: $expectedCurrency',
      );
    }

    if (simulatedStatus == PaymentStatus.failed) {
      return PaymentVerification(
        isVerified: false,
        providerReference: providerReference,
        paymentIntentId: paymentIntentId,
        status: PaymentStatus.failed,
        amountPaise: expectedAmountPaise,
        currency: expectedCurrency,
        verifiedAt: DateTime.now(),
        failureReason: 'Payment was declined by sandbox issuer.',
      );
    }

    if (simulatedStatus == PaymentStatus.expired) {
      return PaymentVerification(
        isVerified: false,
        providerReference: providerReference,
        paymentIntentId: paymentIntentId,
        status: PaymentStatus.expired,
        amountPaise: expectedAmountPaise,
        currency: expectedCurrency,
        verifiedAt: DateTime.now(),
        failureReason: 'Payment window expired.',
      );
    }

    // Success verification
    return PaymentVerification(
      isVerified: true,
      providerReference: providerReference,
      paymentIntentId: paymentIntentId,
      status: PaymentStatus.success,
      amountPaise: expectedAmountPaise,
      currency: expectedCurrency,
      verifiedAt: DateTime.now(),
      rawResponse: {
        'provider': providerName,
        'mode': 'sandbox',
        'authCode': 'SB_AUTH_OK',
      },
    );
  }

  @override
  Future<PaymentVerification> processWebhook({
    required String payload,
    required String signature,
    required String secret,
  }) async {
    // Cryptographic HMAC-SHA256 signature verification
    final hmac = Hmac(sha256, utf8.encode(secret));
    final digest = hmac.convert(utf8.encode(payload));
    final computedSignature = digest.toString();

    if (computedSignature.toLowerCase() != signature.toLowerCase()) {
      return PaymentVerification(
        isVerified: false,
        providerReference: '',
        paymentIntentId: '',
        status: PaymentStatus.failed,
        amountPaise: 0,
        verifiedAt: DateTime.now(),
        failureReason: 'Invalid webhook signature.',
      );
    }

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final event = data['event'] as String? ?? '';
      final paymentIntentId = data['paymentIntentId'] as String? ?? '';
      final providerReference = data['providerReference'] as String? ?? '';
      final amountPaise = (data['amountPaise'] as num?)?.toInt() ?? 0;
      final currency = data['currency'] as String? ?? 'INR';

      if (event == 'payment.failed') {
        return PaymentVerification(
          isVerified: false,
          providerReference: providerReference,
          paymentIntentId: paymentIntentId,
          status: PaymentStatus.failed,
          amountPaise: amountPaise,
          currency: currency,
          verifiedAt: DateTime.now(),
          failureReason: data['failureReason'] as String? ?? 'Payment failed',
        );
      }

      if (event != 'payment.captured' && event != 'payment.success') {
        return PaymentVerification(
          isVerified: false,
          providerReference: providerReference,
          paymentIntentId: paymentIntentId,
          status: PaymentStatus.pending,
          amountPaise: amountPaise,
          currency: currency,
          verifiedAt: DateTime.now(),
          failureReason: 'Unhandled webhook event: $event',
        );
      }

      return PaymentVerification(
        isVerified: true,
        providerReference: providerReference,
        paymentIntentId: paymentIntentId,
        status: PaymentStatus.success,
        amountPaise: amountPaise,
        currency: currency,
        verifiedAt: DateTime.now(),
        rawResponse: data,
      );
    } catch (e) {
      return PaymentVerification(
        isVerified: false,
        providerReference: '',
        paymentIntentId: '',
        status: PaymentStatus.failed,
        amountPaise: 0,
        verifiedAt: DateTime.now(),
        failureReason: 'Malformed webhook payload: $e',
      );
    }
  }

  @override
  Future<PaymentVerification> refundContribution({
    required String paymentIntentId,
    required String providerReference,
    required int amountPaise,
    required String reason,
  }) async {
    return PaymentVerification(
      isVerified: true,
      providerReference: 'ref_sb_${DateTime.now().millisecondsSinceEpoch}',
      paymentIntentId: paymentIntentId,
      status: PaymentStatus.refunded,
      amountPaise: amountPaise,
      verifiedAt: DateTime.now(),
      rawResponse: {'reason': reason, 'mode': 'sandbox'},
    );
  }
}
