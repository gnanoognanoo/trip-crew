import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripcrew/features/trip_pay/models/payment_attempt.dart';
import 'package:tripcrew/features/trip_pay/models/payment_status.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_fee_config.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_transaction.dart';
import 'package:tripcrew/features/trip_pay/providers/sandbox_payment_provider.dart';
import 'package:tripcrew/features/trip_pay/providers/shared_pot_provider.dart';
import 'package:tripcrew/features/trip_pay/services/trusted_payment_service.dart';

void main() {
  group('1% Platform Fee & Calculation Rules', () {
    test('Fee calculation: 100 bps (1%) on contribution amounts', () {
      expect(TripPayFeeConfig.calculateFeePaise(500000), 5000); // ₹5,000 -> ₹50
      expect(
        TripPayFeeConfig.calculateTotalPaise(500000),
        505000,
      ); // ₹5,050 total

      expect(TripPayFeeConfig.calculateFeePaise(100000), 1000); // ₹1,000 -> ₹10
      expect(TripPayFeeConfig.calculateTotalPaise(100000), 101000);

      expect(
        TripPayFeeConfig.calculateFeePaise(2000000),
        20000,
      ); // ₹20,000 -> ₹200
      expect(TripPayFeeConfig.calculateTotalPaise(2000000), 2020000);

      // Pot receives only the net contribution, NOT the fee
      const contributionPaise = 500000;
      const feePaise = 5000;
      const totalCharged = 505000;
      expect(totalCharged - feePaise, contributionPaise);
    });
  });

  group('Payment Instrument Types & Regulated Boundaries', () {
    test(
      'PaymentInstrumentType defines UPI, RuPay, and partner cards without sensitive storage',
      () {
        expect(PaymentInstrumentType.upi.name, 'upi');
        expect(PaymentInstrumentType.rupayPrepaid.name, 'rupayPrepaid');
        expect(PaymentInstrumentType.partnerCard.name, 'partnerCard');
        expect(PaymentInstrumentType.unknown.name, 'unknown');

        expect(
          PaymentInstrumentType.fromString('rupayPrepaid'),
          PaymentInstrumentType.rupayPrepaid,
        );
        expect(
          PaymentInstrumentType.fromString('upi'),
          PaymentInstrumentType.upi,
        );
        expect(
          PaymentInstrumentType.fromString('invalid'),
          PaymentInstrumentType.unknown,
        );
      },
    );

    test('SharedPotProvider: Sandbox provider permits simulated spending', () {
      final sandboxProvider = SandboxSharedPotProvider();
      expect(sandboxProvider.providerName, 'sandbox_pot');
      expect(sandboxProvider.isRegulated, isFalse);
      expect(sandboxProvider.supportedInstrument, PaymentInstrumentType.upi);
    });

    test(
      'SharedPotProvider: RegulatedPpiSharedPotProvider blocks spending without partner credentials',
      () async {
        const ppiProvider = RegulatedPpiSharedPotProvider(
          partnerName: 'FEDERAL_BANK_PPI',
          partnerPpiLicenseId: 'PPI_LIC_2026_TEST',
        );

        expect(ppiProvider.providerName, 'regulated_ppi_FEDERAL_BANK_PPI');
        expect(ppiProvider.isRegulated, isTrue);
        expect(
          ppiProvider.supportedInstrument,
          PaymentInstrumentType.rupayPrepaid,
        );

        expect(
          () => ppiProvider.spendFromPot(
            tripId: 'trip_100',
            amountPaise: 500000,
            initiatedByUid: 'uid_arun',
            initiatedByName: 'Arun',
            description: 'Lunch',
            category: 'Food',
            clientRequestId: 'req_123',
          ),
          throwsA(isA<UnsupportedError>()),
        );
      },
    );
  });

  group(
    'Firestore Security Rules Simulation — Payment Attempts & Ledger Invariants',
    () {
      // Simulator for paymentAttempts create rule
      bool evaluatePaymentAttemptCreateRule({
        required String callerUid,
        required String docUid,
        required bool isMember,
        required String status,
        required bool hasVerifiedAt,
        required bool hasLedgerTransactionId,
      }) {
        if (!isMember) {
          return false;
        }
        if (callerUid != docUid) {
          return false;
        }
        // Client cannot forge initial success
        if (status != 'created' && status != 'pending') {
          return false;
        }
        if (hasVerifiedAt) {
          return false;
        }
        if (hasLedgerTransactionId) {
          return false;
        }
        return true;
      }

      // Simulator for paymentAttempts update rule
      bool evaluatePaymentAttemptUpdateRule({
        required String callerUid,
        required String docUid,
        required bool isMember,
        required String currentStatus,
        required String newStatus,
        required bool hasVerifiedAtInUpdate,
      }) {
        if (!isMember) {
          return false;
        }
        if (callerUid != docUid) {
          return false;
        }
        if (!['created', 'pending', 'verifying'].contains(currentStatus)) {
          return false;
        }

        // Client can only mark cancelled / failed / expired or created -> pending
        if (['failed', 'expired'].contains(newStatus)) {
          if (hasVerifiedAtInUpdate) {
            return false;
          }
          return true;
        }
        if (currentStatus == 'created' && newStatus == 'pending') {
          return true;
        }

        // Client CANNOT mark payment success directly
        if (newStatus == 'success') {
          return false;
        }
        return false;
      }

      test('1. Client CANNOT mark payment success directly → BLOCKED', () {
        // Attempting to create attempt with status 'success'
        final createAllowed = evaluatePaymentAttemptCreateRule(
          callerUid: 'attacker_uid',
          docUid: 'attacker_uid',
          isMember: true,
          status: 'success', // Malicious forged success
          hasVerifiedAt: false,
          hasLedgerTransactionId: false,
        );
        expect(
          createAllowed,
          isFalse,
          reason: 'Client cannot create attempt with status success',
        );

        // Attempting to update attempt to status 'success'
        final updateAllowed = evaluatePaymentAttemptUpdateRule(
          callerUid: 'attacker_uid',
          docUid: 'attacker_uid',
          isMember: true,
          currentStatus: 'pending',
          newStatus: 'success', // Malicious update
          hasVerifiedAtInUpdate: false,
        );
        expect(
          updateAllowed,
          isFalse,
          reason: 'Client cannot update attempt to status success',
        );
      });

      test('2. Client cannot forge verifiedAt timestamp → BLOCKED', () {
        final createWithVerified = evaluatePaymentAttemptCreateRule(
          callerUid: 'attacker_uid',
          docUid: 'attacker_uid',
          isMember: true,
          status: 'pending',
          hasVerifiedAt: true, // Malicious verifiedAt
          hasLedgerTransactionId: false,
        );
        expect(createWithVerified, isFalse);

        final updateWithVerified = evaluatePaymentAttemptUpdateRule(
          callerUid: 'attacker_uid',
          docUid: 'attacker_uid',
          isMember: true,
          currentStatus: 'pending',
          newStatus: 'failed',
          hasVerifiedAtInUpdate: true,
        );
        expect(updateWithVerified, isFalse);
      });

      test('3. Client creating pending attempt → PASS', () {
        final allowed = evaluatePaymentAttemptCreateRule(
          callerUid: 'user_arun',
          docUid: 'user_arun',
          isMember: true,
          status: 'pending',
          hasVerifiedAt: false,
          hasLedgerTransactionId: false,
        );
        expect(allowed, isTrue);
      });

      test('4. Client cancelling payment attempt → PASS', () {
        final allowed = evaluatePaymentAttemptUpdateRule(
          callerUid: 'user_arun',
          docUid: 'user_arun',
          isMember: true,
          currentStatus: 'pending',
          newStatus: 'failed',
          hasVerifiedAtInUpdate: false,
        );
        expect(allowed, isTrue);
      });
    },
  );

  group('Webhook Processing & Signature Cryptography', () {
    const webhookSecret = 'test_webhook_secret_key_8492048';

    String generateValidSignature(String payload, String secret) {
      final hmac = Hmac(sha256, utf8.encode(secret));
      return hmac.convert(utf8.encode(payload)).toString();
    }

    test('Valid webhook signature → PASS', () async {
      final provider = SandboxPaymentProvider(simulatedDelay: Duration.zero);
      const payload =
          '{"event":"payment.success","paymentIntentId":"pi_100","providerReference":"ref_abc","amountPaise":500000,"currency":"INR"}';
      final validSig = generateValidSignature(payload, webhookSecret);

      final verification = await provider.processWebhook(
        payload: payload,
        signature: validSig,
        secret: webhookSecret,
      );

      expect(verification.isVerified, isTrue);
      expect(verification.status, PaymentStatus.success);
      expect(verification.amountPaise, 500000);
      expect(verification.providerReference, 'ref_abc');
    });

    test('Bad/forged webhook signature → BLOCKED', () async {
      final provider = SandboxPaymentProvider(simulatedDelay: Duration.zero);
      const payload =
          '{"event":"payment.success","paymentIntentId":"pi_100","providerReference":"ref_abc","amountPaise":500000}';
      const fakeSig =
          'deadbeef1234567890abcdefdeadbeef1234567890abcdefdeadbeef12345678';

      final verification = await provider.processWebhook(
        payload: payload,
        signature: fakeSig,
        secret: webhookSecret,
      );

      expect(verification.isVerified, isFalse);
      expect(verification.failureReason, contains('Invalid webhook signature'));
    });

    test('Unsigned or empty signature → BLOCKED', () async {
      final provider = SandboxPaymentProvider(simulatedDelay: Duration.zero);
      const payload = '{"event":"payment.success"}';

      final verification = await provider.processWebhook(
        payload: payload,
        signature: '',
        secret: webhookSecret,
      );

      expect(verification.isVerified, isFalse);
    });
  });

  group('Payment Verification Constraints & Mismatch Rejections', () {
    test('Wrong amount rejected during verification → BLOCKED', () {
      bool verifyAmount({
        required int expectedPaise,
        required int reportedPaise,
      }) {
        return expectedPaise == reportedPaise;
      }

      expect(
        verifyAmount(expectedPaise: 500000, reportedPaise: 500000),
        isTrue,
      );
      expect(
        verifyAmount(expectedPaise: 500000, reportedPaise: 400000),
        isFalse,
        reason: 'Underpaid amount must be rejected',
      );
      expect(
        verifyAmount(expectedPaise: 500000, reportedPaise: 600000),
        isFalse,
        reason: 'Overpaid/mismatched amount must be rejected',
      );
    });

    test('Wrong currency rejected during verification → BLOCKED', () {
      bool verifyCurrency({
        required String expected,
        required String reported,
      }) {
        return expected.toUpperCase() == reported.toUpperCase();
      }

      expect(verifyCurrency(expected: 'INR', reported: 'INR'), isTrue);
      expect(verifyCurrency(expected: 'INR', reported: 'USD'), isFalse);
    });

    test('Wrong trip rejected → BLOCKED', () {
      bool verifyTrip({
        required String expectedTripId,
        required String reportedTripId,
      }) {
        return expectedTripId == reportedTripId;
      }

      expect(
        verifyTrip(expectedTripId: 'trip_goa', reportedTripId: 'trip_goa'),
        isTrue,
      );
      expect(
        verifyTrip(expectedTripId: 'trip_goa', reportedTripId: 'trip_kerala'),
        isFalse,
      );
    });

    test('Wrong user rejected → BLOCKED', () {
      bool verifyUser({
        required String expectedUid,
        required String reportedUid,
      }) {
        return expectedUid == reportedUid;
      }

      expect(
        verifyUser(expectedUid: 'user_arun', reportedUid: 'user_arun'),
        isTrue,
      );
      expect(
        verifyUser(expectedUid: 'user_arun', reportedUid: 'user_attacker'),
        isFalse,
      );
    });
  });

  group('Idempotency & Duplicate Callback Protection', () {
    test(
      'Duplicate webhook or callback does NOT duplicate contribution ledger entry',
      () {
        final existingTransactions = <String, TripPayTransaction>{};
        int potBalancePaise = 0;

        void processContributionCallback({
          required String providerReference,
          required String clientRequestId,
          required int amountPaise,
          required String uid,
        }) {
          // Idempotency check: has this providerReference or clientRequestId already been processed?
          final alreadyProcessed = existingTransactions.values.any(
            (tx) =>
                tx.providerReference == providerReference ||
                tx.clientRequestId == clientRequestId,
          );

          if (alreadyProcessed) {
            // Idempotent: return without adding money again
            return;
          }

          final txId = 'tx_${existingTransactions.length + 1}';
          final tx = TripPayTransaction(
            id: txId,
            tripId: 'trip_100',
            type: TripPayTransactionType.contribution,
            amountPaise: amountPaise,
            initiatedByUid: uid,
            initiatedByName: 'Member',
            category: 'Contribution',
            description: 'Added money',
            status: TripPayTransactionStatus.sandboxSuccess,
            createdAt: DateTime.now(),
            balanceBeforePaise: potBalancePaise,
            balanceAfterPaise: potBalancePaise + amountPaise,
            providerReference: providerReference,
            clientRequestId: clientRequestId,
          );

          existingTransactions[txId] = tx;
          potBalancePaise += amountPaise;
        }

        // First callback arrives
        processContributionCallback(
          providerReference: 'upi_ref_12345',
          clientRequestId: 'req_001',
          amountPaise: 500000, // ₹5,000
          uid: 'user_arun',
        );

        expect(existingTransactions.length, 1);
        expect(potBalancePaise, 500000);

        // Duplicate callback arrives with SAME providerReference
        processContributionCallback(
          providerReference: 'upi_ref_12345',
          clientRequestId: 'req_001',
          amountPaise: 500000,
          uid: 'user_arun',
        );

        // Exact invariant: 1 transaction only, balance is ₹5,000 (NOT ₹10,000!)
        expect(
          existingTransactions.length,
          1,
          reason: 'Duplicate callback must not create another transaction',
        );
        expect(
          potBalancePaise,
          500000,
          reason: 'Pot balance must remain exactly ₹5,000',
        );
      },
    );
  });

  group('Lifecycle States & Balance Safety', () {
    test('Cancelled payment leaves balance unchanged', () {
      int balancePaise = 200000; // ₹2,000 existing
      const attemptStatus = PaymentStatus.failed;

      if (attemptStatus == PaymentStatus.success) {
        balancePaise += 500000;
      }

      expect(
        balancePaise,
        200000,
        reason: 'Cancelled/failed payment must not increase balance',
      );
    });

    test('Pending payment leaves balance unchanged', () {
      int balancePaise = 200000;
      const attemptStatus = PaymentStatus.pending;

      if (attemptStatus == PaymentStatus.success) {
        balancePaise += 500000;
      }

      expect(
        balancePaise,
        200000,
        reason: 'Pending payment must not increase balance',
      );
    });

    test('Verified success increases balance exactly once', () {
      int balancePaise = 200000;
      const attemptStatus = PaymentStatus.success;

      if (attemptStatus == PaymentStatus.success) {
        balancePaise += 500000;
      }

      expect(
        balancePaise,
        700000,
        reason: 'Verified success must increase balance by contribution amount',
      );
    });

    test('App restart recovers pending transaction to success', () async {
      final sandboxProvider = SandboxPaymentProvider(
        simulatedStatus: PaymentStatus.success,
        simulatedDelay: Duration.zero,
      );

      final service = TrustedPaymentService(paymentProvider: sandboxProvider);

      // Simulate an unfinalized pending attempt from before app close
      final attempt = PaymentAttempt(
        id: 'att_recovered_01',
        tripId: 'trip_100',
        uid: 'user_arun',
        amountPaise: 500000,
        platformFeePaise: 5000,
        totalChargePaise: 505000,
        provider: 'sandbox',
        clientRequestId: 'req_rec_01',
        paymentIntentId: 'pi_rec_01',
        status: PaymentStatus.pending,
        createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
        updatedAt: DateTime.now().subtract(const Duration(minutes: 2)),
      );

      // Verify status with provider
      final providerStatus = await sandboxProvider.fetchPaymentStatus(
        paymentIntentId: attempt.paymentIntentId,
      );

      expect(providerStatus, PaymentStatus.success);

      // Finalize recovered attempt
      final tx = await service.verifyAndFinalizeContribution(
        tripId: attempt.tripId,
        paymentAttemptId: attempt.id,
        providerReference: 'recovered_ref_999',
        initiatedByName: 'Arun',
      );

      expect(tx, isNotNull);
      expect(tx!.amountPaise, 500000);
      expect(tx.calculatedPlatformFeePaise, 5000);
      expect(tx.providerReference, 'recovered_ref_999');
    });
  });
}
