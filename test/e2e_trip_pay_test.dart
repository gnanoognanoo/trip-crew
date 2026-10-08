import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripcrew/features/trip_pay/models/payment_status.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_transaction.dart';
import 'package:tripcrew/features/trip_pay/providers/razorpay_payment_provider.dart';
import 'package:tripcrew/features/trip_pay/services/trusted_payment_service.dart';

void main() {
  group('End-to-End Trip Pay Razorpay Test Mode Integration', () {
    const backendUrl = 'https://trip-creww-production.up.railway.app';
    const razorpaySecret = 'pI7sfYEzaCYXxKGekUyaiD7G';

    test('Full End-to-End Flow: Intent -> Test Checkout -> HMAC Verification -> Pot Increase', () async {
      final razorpayProvider = RazorpayPaymentProvider(
        backendBaseUrl: backendUrl,
        keySecret: razorpaySecret,
      );

      final trustedService = TrustedPaymentService(
        paymentProvider: razorpayProvider,
      );

      const tripId = 'trip_e2e_demo_100';
      const uid = 'uid_test_traveler_1';
      const contributionAmountPaise = 500000; // ₹5,000
      final clientRequestId = 'req_e2e_${DateTime.now().millisecondsSinceEpoch}';

      // Step 1: Create Contribution Intent
      final intent = await trustedService.initiateContribution(
        tripId: tripId,
        uid: uid,
        amountPaise: contributionAmountPaise,
        clientRequestId: clientRequestId,
      );

      expect(intent.id, isNotEmpty);
      expect(intent.amountPaise, contributionAmountPaise);
      expect(intent.totalChargePaise, 505000); // 1% platform fee (₹50)
      expect(intent.provider, equals('razorpay'));

      // Step 2 & 3: Simulate Razorpay Test Mode Checkout & Generate HMAC Signature
      final simulatedPaymentId = 'pay_simulated_${DateTime.now().millisecondsSinceEpoch}';
      final hmac = Hmac(sha256, utf8.encode(razorpaySecret));
      final rawPayload = '${intent.id}|$simulatedPaymentId';
      final validSignature = hmac.convert(utf8.encode(rawPayload)).toString();

      final providerReference = '$simulatedPaymentId|$validSignature';

      // Step 4 & 5 & 6: Verify Backend Signature & Finalize Contribution
      final verification = await razorpayProvider.verifyPayment(
        paymentIntentId: intent.id,
        providerReference: providerReference,
        expectedAmountPaise: intent.totalChargePaise,
        expectedCurrency: 'INR',
      );

      expect(verification.isVerified, isTrue);
      expect(verification.status, PaymentStatus.success);

      final attemptId = 'att_${DateTime.now().millisecondsSinceEpoch}_1';
      final transaction = await trustedService.verifyAndFinalizeContribution(
        tripId: tripId,
        paymentAttemptId: attemptId,
        providerReference: providerReference,
        initiatedByName: 'Test Traveler',
      );

      expect(transaction, isNotNull);
      expect(transaction!.id, startsWith('tx_'));
      expect(transaction.amountPaise, contributionAmountPaise);
      expect(transaction.status, TripPayTransactionStatus.sandboxSuccess);

      print('\n==================================================');
      print('[E2E TEST RESULT] End-to-End Trip Pay Test Succeeded!');
      print('Transaction ID: ${transaction.id}');
      print('Provider Reference: $providerReference');
      print('Net Contribution Added: ₹${(transaction.amountPaise / 100).toStringAsFixed(2)}');
      print('==================================================\n');
    });
  });
}
