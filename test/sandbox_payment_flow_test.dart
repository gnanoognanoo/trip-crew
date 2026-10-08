import 'package:flutter_test/flutter_test.dart';
import 'package:tripcrew/features/trip_pay/models/payment_status.dart';
import 'package:tripcrew/features/trip_pay/providers/sandbox_payment_provider.dart';
import 'package:tripcrew/features/trip_pay/services/trusted_payment_service.dart';

void main() {
  group('Sandbox Payment Flow & Status Persistence', () {
    late SandboxPaymentProvider sandboxProvider;
    late TrustedPaymentService trustedService;

    setUp(() {
      sandboxProvider = SandboxPaymentProvider(
        simulatedDelay: Duration.zero,
      );
      trustedService = TrustedPaymentService(
        paymentProvider: sandboxProvider,
      );
    });

    test('Simulate Success writes status=success and Refresh reads updated status', () async {
      const tripId = 'trip_sb_flow_1';
      const uid = 'user_sb_1';
      const amountPaise = 100000; // ₹1,000

      // Step 1: Create Intent
      final intent = await trustedService.initiateContribution(
        tripId: tripId,
        uid: uid,
        amountPaise: amountPaise,
        clientRequestId: 'req_sb_${DateTime.now().millisecondsSinceEpoch}',
      );

      expect(intent.id, isNotEmpty);

      // Step 2: Simulate Success -> writes status = success for this intent ID
      sandboxProvider.setSimulatedStatus(
        PaymentStatus.success,
        paymentIntentId: intent.id,
      );

      // Step 3: Refresh / Check Status -> reads updated status
      final status = await sandboxProvider.fetchPaymentStatus(
        paymentIntentId: intent.id,
      );

      expect(status, equals(PaymentStatus.success));

      // Step 4: Verify Payment -> returns verified success HTTP 200 equivalent
      final verification = await sandboxProvider.verifyPayment(
        paymentIntentId: intent.id,
        providerReference: 'upi_ref_12345',
        expectedAmountPaise: intent.totalChargePaise,
      );

      expect(verification.isVerified, isTrue);
      expect(verification.status, equals(PaymentStatus.success));

      // Step 5: Finalize contribution -> Trip Pot increases
      final tx = await trustedService.verifyAndFinalizeContribution(
        tripId: tripId,
        paymentAttemptId: 'att_sb_1',
        providerReference: 'upi_ref_12345',
        initiatedByName: 'Tester',
        amountPaise: amountPaise,
      );

      expect(tx, isNotNull);
      expect(tx!.amountPaise, equals(amountPaise));
    });

    test('Simulate Decline writes status=failed and Refresh reads failed status', () async {
      const tripId = 'trip_sb_flow_2';
      const uid = 'user_sb_2';

      final intent = await trustedService.initiateContribution(
        tripId: tripId,
        uid: uid,
        amountPaise: 50000,
        clientRequestId: 'req_sb_decline_${DateTime.now().millisecondsSinceEpoch}',
      );

      // Simulate Decline
      sandboxProvider.setSimulatedStatus(
        PaymentStatus.failed,
        paymentIntentId: intent.id,
      );

      final status = await sandboxProvider.fetchPaymentStatus(
        paymentIntentId: intent.id,
      );

      expect(status, equals(PaymentStatus.failed));

      final verification = await sandboxProvider.verifyPayment(
        paymentIntentId: intent.id,
        providerReference: 'declined_ref_123',
        expectedAmountPaise: intent.totalChargePaise,
      );

      expect(verification.isVerified, isFalse);
      expect(verification.status, equals(PaymentStatus.failed));
    });
  });
}
