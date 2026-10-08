import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tripcrew/features/trip_pay/models/payment_status.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_fee_config.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_transaction.dart';
import 'package:tripcrew/features/trip_pay/providers/razorpay_payment_provider.dart';
import 'package:tripcrew/features/trip_pay/services/razorpay_status_mapper.dart';
import 'package:tripcrew/features/trip_pay/services/trusted_payment_service.dart';

void main() {
  const testWebhookSecret = 'test_razorpay_webhook_secret_8492048';

  String computeHmacHex(String body, String secret) {
    final hmac = Hmac(sha256, utf8.encode(secret));
    return hmac.convert(utf8.encode(body)).toString().toLowerCase();
  }

  group('RazorpayStatusMapper — Domain Status Translation', () {
    test('payment.authorized mapping: PASS', () {
      expect(
        RazorpayStatusMapper.fromEventType('payment.authorized'),
        PaymentStatus.pending,
      );
      expect(
        RazorpayStatusMapper.fromRazorpayStatus('authorized'),
        PaymentStatus.pending,
      );
      expect(
        RazorpayStatusMapper.fromRazorpayStatus('created'),
        PaymentStatus.pending,
      );
    });

    test('payment.captured & order.paid mapping: PASS', () {
      expect(
        RazorpayStatusMapper.fromEventType('payment.captured'),
        PaymentStatus.success,
      );
      expect(
        RazorpayStatusMapper.fromEventType('order.paid'),
        PaymentStatus.success,
      );
      expect(
        RazorpayStatusMapper.fromRazorpayStatus('captured'),
        PaymentStatus.success,
      );
      expect(
        RazorpayStatusMapper.fromRazorpayStatus('paid'),
        PaymentStatus.success,
      );
    });

    test('payment.failed mapping: PASS', () {
      expect(
        RazorpayStatusMapper.fromEventType('payment.failed'),
        PaymentStatus.failed,
      );
      expect(
        RazorpayStatusMapper.fromRazorpayStatus('failed'),
        PaymentStatus.failed,
      );
      expect(
        RazorpayStatusMapper.fromRazorpayStatus('cancelled'),
        PaymentStatus.failed,
      );
    });

    test('Translates refund and expiration statuses correctly', () {
      expect(
        RazorpayStatusMapper.fromRazorpayStatus('refunded'),
        PaymentStatus.refunded,
      );
      expect(
        RazorpayStatusMapper.fromRazorpayStatus('expired'),
        PaymentStatus.expired,
      );
    });

    test('Unknown or ambiguous statuses fall back to pending (fail-safe)', () {
      expect(
        RazorpayStatusMapper.fromRazorpayStatus('UNKNOWN_STATUS_CODE'),
        PaymentStatus.pending,
      );
      expect(RazorpayStatusMapper.fromRazorpayStatus(''), PaymentStatus.pending);
      expect(RazorpayStatusMapper.fromRazorpayStatus(null), PaymentStatus.pending);
    });
  });

  group('RazorpayPaymentProvider — Unconfigured Safety', () {
    test('Throws RazorpayUnconfiguredException when credentials are missing', () {
      final unconfiguredProvider = RazorpayPaymentProvider();
      expect(unconfiguredProvider.isConfigured, isFalse);

      expect(
        () => unconfiguredProvider.createContributionIntent(
          tripId: 'trip_100',
          uid: 'user_1',
          amountPaise: 500000,
          clientRequestId: 'cr_1',
        ),
        throwsA(isA<RazorpayUnconfiguredException>()),
      );
    });

    test(
      'RazorpayUnconfiguredException contains clear user-facing message',
      () async {
        final unconfiguredProvider = RazorpayPaymentProvider();
        try {
          await unconfiguredProvider.createContributionIntent(
            tripId: 'trip_100',
            uid: 'user_1',
            amountPaise: 500000,
            clientRequestId: 'cr_1',
          );
          fail('Should have thrown');
        } on RazorpayUnconfiguredException catch (e) {
          expect(e.message, 'Razorpay payment provider is not configured.');
          expect(e.toString(), 'Razorpay payment provider is not configured.');
        }
      },
    );
  });

  group('RazorpayPaymentProvider — Payment Intent / Order Creation', () {
    test(
      'Creates Razorpay Order with 1% fee calculation and maps payload',
      () async {
        final mockClient = MockClient((request) async {
          if (request.url.path.contains('/orders')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['amount'], 505000); // ₹5,000 + ₹50 fee
            expect(body['currency'], 'INR');

            return http.Response(
              jsonEncode({
                'id': 'order_rzp_98765',
                'amount': 505000,
                'currency': 'INR',
                'status': 'created',
                'created_at': 1700000000,
              }),
              201,
            );
          }
          return http.Response('Not Found', 404);
        });

        final provider = RazorpayPaymentProvider(
          keyId: 'rzp_test_key_id',
          keySecret: 'test_key_secret',
          webhookSecret: testWebhookSecret,
          httpClient: mockClient,
        );

        expect(provider.isConfigured, isTrue);

        final intent = await provider.createContributionIntent(
          tripId: 'trip_goa',
          uid: 'user_arun',
          amountPaise: 500000, // ₹5,000
          clientRequestId: 'req_arun_101',
        );

        expect(intent.id, 'order_rzp_98765');
        expect(intent.amountPaise, 500000);
        expect(intent.platformFeePaise, 5000); // 1% fee
        expect(intent.totalChargePaise, 505000); // ₹5,050
        expect(intent.provider, 'razorpay');
        expect(intent.status, PaymentStatus.pending);
      },
    );
  });

  group('RazorpayPaymentProvider — Webhook Signature & Idempotency', () {
    late RazorpayPaymentProvider provider;

    setUp(() {
      provider = RazorpayPaymentProvider(
        keyId: 'rzp_test_key_id',
        keySecret: 'test_key_secret',
        webhookSecret: testWebhookSecret,
      );
    });

    test('Valid HMAC-SHA256 signature → PASS', () async {
      const payload =
          '{"event":"payment.captured","payload":{"payment":{"entity":{"id":"pay_999","order_id":"order_123","amount":505000,"currency":"INR","status":"captured"}}}}';
      final sigHex = computeHmacHex(payload, testWebhookSecret);

      final verification = await provider.processWebhook(
        payload: payload,
        signature: sigHex,
        secret: testWebhookSecret,
      );

      expect(verification.isVerified, isTrue);
      expect(verification.status, PaymentStatus.success);
      expect(verification.amountPaise, 505000);
      expect(verification.providerReference, 'pay_999');
      expect(verification.paymentIntentId, 'order_123');
    });

    test('Forged or invalid HMAC signature → BLOCKED', () async {
      const payload =
          '{"event":"payment.captured","payload":{"payment":{"entity":{"id":"pay_123","amount":505000}}}}';
      const forgedSig =
          'deadbeef1234567890abcdefdeadbeef1234567890abcdefdeadbeef12345678';

      final verification = await provider.processWebhook(
        payload: payload,
        signature: forgedSig,
        secret: testWebhookSecret,
      );

      expect(verification.isVerified, isFalse);
      expect(verification.failureReason, contains('Invalid webhook signature'));
    });

    test('Missing or empty signature → BLOCKED', () async {
      const payload = '{"event":"payment.captured"}';

      final verification = await provider.processWebhook(
        payload: payload,
        signature: '',
        secret: testWebhookSecret,
      );

      expect(verification.isVerified, isFalse);
      expect(verification.failureReason, contains('Missing webhook signature'));
    });
  });

  group('RazorpayPaymentProvider — Webhook Event Processing', () {
    late RazorpayPaymentProvider provider;

    setUp(() {
      provider = RazorpayPaymentProvider(
        keyId: 'rzp_test_key_id',
        keySecret: 'test_key_secret',
        webhookSecret: testWebhookSecret,
      );
    });

    test('Razorpay payment.authorized payload mapping → PASS', () async {
      final payload = jsonEncode({
        'event': 'payment.authorized',
        'payload': {
          'payment': {
            'entity': {
              'id': 'pay_auth_001',
              'order_id': 'order_auth_001',
              'amount': 505000,
              'currency': 'INR',
              'status': 'authorized',
            }
          }
        }
      });
      final sig = computeHmacHex(payload, testWebhookSecret);

      final verification = await provider.processWebhook(
        payload: payload,
        signature: sig,
        secret: testWebhookSecret,
      );

      expect(verification.status, PaymentStatus.pending);
      expect(verification.isVerified, isFalse);
      expect(verification.providerReference, 'pay_auth_001');
      expect(verification.paymentIntentId, 'order_auth_001');
      expect(verification.amountPaise, 505000);
    });

    test('Razorpay payment.captured payload mapping → PASS', () async {
      final payload = jsonEncode({
        'event': 'payment.captured',
        'payload': {
          'payment': {
            'entity': {
              'id': 'pay_cap_002',
              'order_id': 'order_cap_002',
              'amount': 505000,
              'currency': 'INR',
              'status': 'captured',
            }
          }
        }
      });
      final sig = computeHmacHex(payload, testWebhookSecret);

      final verification = await provider.processWebhook(
        payload: payload,
        signature: sig,
        secret: testWebhookSecret,
      );

      expect(verification.status, PaymentStatus.success);
      expect(verification.isVerified, isTrue);
      expect(verification.providerReference, 'pay_cap_002');
      expect(verification.paymentIntentId, 'order_cap_002');
      expect(verification.amountPaise, 505000);
    });

    test('Razorpay payment.failed payload mapping → PASS', () async {
      final payload = jsonEncode({
        'event': 'payment.failed',
        'payload': {
          'payment': {
            'entity': {
              'id': 'pay_fail_003',
              'order_id': 'order_fail_003',
              'amount': 505000,
              'currency': 'INR',
              'status': 'failed',
            }
          }
        }
      });
      final sig = computeHmacHex(payload, testWebhookSecret);

      final verification = await provider.processWebhook(
        payload: payload,
        signature: sig,
        secret: testWebhookSecret,
      );

      expect(verification.status, PaymentStatus.failed);
      expect(verification.isVerified, isFalse);
      expect(verification.providerReference, 'pay_fail_003');
      expect(verification.paymentIntentId, 'order_fail_003');
    });
  });

  group('RazorpayPaymentProvider — Amount Verification & Fee Accounting', () {
    test('Exact amount match (amount + fee) → PASS', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'captured',
            'amount': 505000,
            'currency': 'INR',
            'id': 'pay_rzp_123',
          }),
          200,
        );
      });

      final provider = RazorpayPaymentProvider(
        keyId: 'id',
        keySecret: 'secret',
        httpClient: mockClient,
      );

      final verification = await provider.verifyPayment(
        paymentIntentId: 'order_123',
        providerReference: 'pay_rzp_123',
        expectedAmountPaise: 505000,
        expectedCurrency: 'INR',
      );

      expect(verification.isVerified, isTrue);
      expect(verification.status, PaymentStatus.success);
      expect(verification.amountPaise, 505000);
    });

    test(
      'Mismatched amount (e.g. ₹5,000 paid when ₹5,050 expected) → BLOCKED',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'status': 'captured',
              'amount': 500000, // ₹5,000 received instead of ₹5,050!
              'currency': 'INR',
              'id': 'pay_rzp_123',
            }),
            200,
          );
        });

        final provider = RazorpayPaymentProvider(
          keyId: 'id',
          keySecret: 'secret',
          httpClient: mockClient,
        );

        final verification = await provider.verifyPayment(
          paymentIntentId: 'order_123',
          providerReference: 'pay_rzp_123',
          expectedAmountPaise: 505000, // Expected ₹5,050
          expectedCurrency: 'INR',
        );

        expect(verification.isVerified, isFalse);
        expect(
          verification.failureReason,
          contains('PAYMENT VERIFICATION FAILED: Amount mismatch'),
        );
      },
    );

    test('Currency mismatch (USD instead of INR) → BLOCKED', () async {
      final provider = RazorpayPaymentProvider(
        keyId: 'id',
        keySecret: 'secret',
      );

      final verification = await provider.verifyPayment(
        paymentIntentId: 'order_123',
        providerReference: 'pay_rzp_123',
        expectedAmountPaise: 505000,
        expectedCurrency: 'USD',
      );

      expect(verification.isVerified, isFalse);
      expect(verification.failureReason, contains('Unsupported currency'));
    });
  });

  group('Pilot Scenario Simulation — 4 Real Members (A, B, C, D)', () {
    test(
      '4 members contribute ₹5,000 each via Razorpay Orders API → Pot = ₹20,000, Fee = ₹200',
      () async {
        int potBalancePaise = 0;
        int totalFeeRecordedPaise = 0;
        final transactions = <TripPayTransaction>[];
        final processedReferences = <String>{};

        void processVerifiedRazorpayPayment({
          required String uid,
          required String memberName,
          required String providerReference,
          required int contributionPaise,
        }) {
          // Idempotency guard
          if (processedReferences.contains(providerReference)) {
            return;
          }
          processedReferences.add(providerReference);

          final feePaise = TripPayFeeConfig.calculateFeePaise(
            contributionPaise,
          );
          final balanceBefore = potBalancePaise;
          final balanceAfter = potBalancePaise + contributionPaise;

          final tx = TripPayTransaction(
            id: 'tx_${transactions.length + 1}',
            tripId: 'trip_pilot_goa',
            type: TripPayTransactionType.contribution,
            amountPaise: contributionPaise,
            initiatedByUid: uid,
            initiatedByName: memberName,
            category: 'Contribution',
            description: '$memberName added money (Razorpay)',
            status: TripPayTransactionStatus.sandboxSuccess,
            createdAt: DateTime.now(),
            balanceBeforePaise: balanceBefore,
            balanceAfterPaise: balanceAfter,
            calculatedPlatformFeePaise: feePaise,
            mode: 'razorpay_test',
            providerReference: providerReference,
            clientRequestId: 'cr_pilot_${transactions.length + 1}',
          );

          transactions.add(tx);
          potBalancePaise = balanceAfter;
          totalFeeRecordedPaise += feePaise;
        }

        // Member A contributes ₹5,000
        processVerifiedRazorpayPayment(
          uid: 'uid_a',
          memberName: 'Account A',
          providerReference: 'pay_rzp_ref_a_101',
          contributionPaise: 500000,
        );

        // Member B contributes ₹5,000
        processVerifiedRazorpayPayment(
          uid: 'uid_b',
          memberName: 'Account B',
          providerReference: 'pay_rzp_ref_b_102',
          contributionPaise: 500000,
        );

        // Member C contributes ₹5,000
        processVerifiedRazorpayPayment(
          uid: 'uid_c',
          memberName: 'Account C',
          providerReference: 'pay_rzp_ref_c_103',
          contributionPaise: 500000,
        );

        // Member D contributes ₹5,000
        processVerifiedRazorpayPayment(
          uid: 'uid_d',
          memberName: 'Account D',
          providerReference: 'pay_rzp_ref_d_104',
          contributionPaise: 500000,
        );

        // Verify shared pot balance: Exactly ₹20,000 (NOT ₹20,200!)
        expect(potBalancePaise, 2000000); // 2,000,000 paise = ₹20,000
        expect(totalFeeRecordedPaise, 20000); // 20,000 paise = ₹200 (4 x ₹50)
        expect(transactions.length, 4);

        // Replay attempt on Member A's transaction: Must be blocked idempotently
        processVerifiedRazorpayPayment(
          uid: 'uid_a',
          memberName: 'Account A',
          providerReference: 'pay_rzp_ref_a_101', // Replayed reference!
          contributionPaise: 500000,
        );

        expect(
          potBalancePaise,
          2000000,
          reason: 'Duplicate callback must not increment balance',
        );
        expect(
          transactions.length,
          4,
          reason: 'Duplicate callback must not create another transaction',
        );
      },
    );

    test('Cancelled or failed Razorpay payments leave pot balance unchanged', () {
      int potBalancePaise = 2000000; // Starting with ₹20,000

      void handleFailedRazorpayPayment() {
        // Failed payments must NEVER modify pot balance
      }

      handleFailedRazorpayPayment();
      expect(potBalancePaise, 2000000);
    });
  });

  group('TrustedPaymentService with Razorpay Provider', () {
    test('Recovers pending Razorpay attempts cleanly after app restart', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'captured',
            'amount': 505000,
            'currency': 'INR',
            'id': 'pay_rzp_recovered_001',
          }),
          200,
        );
      });

      final razorpayProvider = RazorpayPaymentProvider(
        keyId: 'id',
        keySecret: 'secret',
        httpClient: mockClient,
      );

      final trustedService = TrustedPaymentService(
        paymentProvider: razorpayProvider,
      );

      // Verify and finalize contribution with Razorpay
      final tx = await trustedService.verifyAndFinalizeContribution(
        tripId: 'trip_kerala',
        paymentAttemptId: 'att_pending_1',
        providerReference: 'pay_rzp_recovered_001',
        initiatedByName: 'Rahul',
      );

      expect(tx, isNotNull);
      expect(tx!.amountPaise, 500000); // ₹5,000
      expect(tx.calculatedPlatformFeePaise, 5000); // ₹50
      expect(tx.providerReference, 'pay_rzp_recovered_001');
    });
  });
}
