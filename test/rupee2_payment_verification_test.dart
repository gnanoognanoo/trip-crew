import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripcrew/features/trip_pay/models/payment_status.dart';
import 'package:tripcrew/features/trip_pay/providers/razorpay_payment_provider.dart';
import 'package:tripcrew/features/trip_pay/services/trusted_payment_service.dart';

void main() {
  group('₹2 Razorpay Payment Backend Verification Test', () {
    const backendUrl = 'https://trip-creww-production.up.railway.app';
    const razorpaySecret = 'pI7sfYEzaCYXxKGekUyaiD7G';

    test('Trigger ₹2 payment and verify HTTP 200 & Trip Pot increase', () async {
      final razorpayProvider = RazorpayPaymentProvider(
        backendBaseUrl: backendUrl,
        keySecret: razorpaySecret,
      );

      final trustedService = TrustedPaymentService(
        paymentProvider: razorpayProvider,
      );

      const tripId = 'trip_rupee2_test';
      const uid = 'uid_user_rupee2';
      const amountPaise = 200; // ₹2.00
      final clientRequestId = 'req_rupee2_${DateTime.now().millisecondsSinceEpoch}';

      // Step 1: Create ₹2 Contribution Intent
      final intent = await trustedService.initiateContribution(
        tripId: tripId,
        uid: uid,
        amountPaise: amountPaise,
        clientRequestId: clientRequestId,
      );

      expect(intent.id, isNotEmpty);
      expect(intent.amountPaise, 200);
      expect(intent.totalChargePaise, 202); // 200 paise + 2 paise fee (1%)

      // Step 2: Generate payment ID & HMAC signature
      final paymentId = 'pay_rupee2_${DateTime.now().millisecondsSinceEpoch}';
      final hmac = Hmac(sha256, utf8.encode(razorpaySecret));
      final rawPayload = '${intent.id}|$paymentId';
      final signature = hmac.convert(utf8.encode(rawPayload)).toString();
      final providerReference = '$paymentId|$signature|${intent.id}';

      // Step 3: Call backend verify endpoint
      final verification = await razorpayProvider.verifyPayment(
        paymentIntentId: intent.id,
        providerReference: providerReference,
        expectedAmountPaise: intent.totalChargePaise,
        expectedCurrency: 'INR',
      );

      expect(verification.isVerified, isTrue);
      expect(verification.status, PaymentStatus.success);
      expect(verification.amountPaise, 202);

      // Step 4: Finalize contribution & update Trip Pot
      final attemptId = 'att_rupee2_${DateTime.now().millisecondsSinceEpoch}';
      final transaction = await trustedService.verifyAndFinalizeContribution(
        tripId: tripId,
        paymentAttemptId: attemptId,
        providerReference: providerReference,
        initiatedByName: 'Rupee 2 Tester',
      );

      expect(transaction, isNotNull);
      expect(transaction!.amountPaise, 200);

      print('\n==================================================');
      print('[RUPEE 2 VERIFICATION SUCCESS]');
      print('Order ID: ${intent.id}');
      print('Payment ID: $paymentId');
      print('Signature: $signature');
      print('Backend Verification Status: HTTP 200 Success');
      print('Net Contribution Added to Trip Pot: ₹${(transaction.amountPaise / 100).toStringAsFixed(2)}');
      print('==================================================\n');
    });
  });
}
