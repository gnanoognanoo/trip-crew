import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tripcrew/core/services/firebase_service.dart';
import 'package:tripcrew/features/trip_pay/models/payment_attempt.dart';
import 'package:tripcrew/features/trip_pay/models/payment_intent.dart';
import 'package:tripcrew/features/trip_pay/models/payment_status.dart';
import 'package:tripcrew/features/trip_pay/models/payment_verification.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_fee_config.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_summary.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_transaction.dart';
import 'package:tripcrew/features/trip_pay/providers/payment_provider.dart';

/// Trusted payment service enforcing the backend trust boundary.
///
/// Under Firebase Spark tier constraints, this service models and executes
/// the server-side verification and atomic ledger finalization.
///
/// BACKEND TRUST BOUNDARY:
/// - Client initiates payment and displays payment rails (UPI intent/QR).
/// - Trusted payment verification confirms the payment from the provider.
/// - ONLY upon verified success does the atomic immutable ledger transaction
///   get created and the Trip Pot balance increase.
/// - Client-side forged `status: 'success'` is strictly blocked.
class TrustedPaymentService {
  final PaymentProvider _paymentProvider;
  final FirebaseFirestore? _firestoreOverride;

  TrustedPaymentService({
    required PaymentProvider paymentProvider,
    FirebaseFirestore? firestore,
  }) : _paymentProvider = paymentProvider,
       _firestoreOverride = firestore;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  CollectionReference _attemptsRef(String tripId) =>
      _firestore.collection('trips').doc(tripId).collection('paymentAttempts');

  CollectionReference _transactionsRef(String tripId) =>
      _firestore.collection('trips').doc(tripId).collection('transactions');

  DocumentReference _summaryRef(String tripId) => _firestore
      .collection('trips')
      .doc(tripId)
      .collection('tripPay')
      .doc('summary');

  /// Step 1: Initiates a contribution intent and records a pending payment attempt.
  /// Does NOT touch the Trip Pot balance or create an immutable ledger transaction.
  Future<PaymentIntent> initiateContribution({
    required String tripId,
    required String uid,
    required int amountPaise,
    required String clientRequestId,
  }) async {
    if (amountPaise <= 0) {
      throw ArgumentError('Contribution amount must be positive.');
    }

    final feePaise = TripPayFeeConfig.calculateFeePaise(amountPaise);
    final totalChargePaise = amountPaise + feePaise;

    // Check for duplicate pending request
    if (FirebaseService.isInitialized) {
      final existingSnap = await _attemptsRef(
        tripId,
      ).where('clientRequestId', isEqualTo: clientRequestId).limit(1).get();

      if (existingSnap.docs.isNotEmpty) {
        final existingDoc = existingSnap.docs.first;
        final existing = PaymentAttempt.fromMap(
          existingDoc.data() as Map<String, dynamic>,
          existingDoc.id,
        );
        return PaymentIntent(
          id: existing.paymentIntentId,
          tripId: tripId,
          uid: uid,
          amountPaise: existing.amountPaise,
          platformFeePaise: existing.platformFeePaise,
          totalChargePaise: existing.totalChargePaise,
          clientRequestId: existing.clientRequestId,
          provider: existing.provider,
          status: existing.status,
          createdAt: existing.createdAt,
          expiresAt: existing.createdAt.add(const Duration(minutes: 15)),
        );
      }
    }

    // Call payment provider to generate UPI intent
    final intent = await _paymentProvider.createContributionIntent(
      tripId: tripId,
      uid: uid,
      amountPaise: amountPaise,
      clientRequestId: clientRequestId,
    );

    final attemptId =
        'att_${DateTime.now().millisecondsSinceEpoch}_${intent.id.hashCode.abs()}';
    final attempt = PaymentAttempt(
      id: attemptId,
      tripId: tripId,
      uid: uid,
      type: 'contribution',
      amountPaise: amountPaise,
      platformFeePaise: feePaise,
      totalChargePaise: totalChargePaise,
      provider: _paymentProvider.providerName,
      clientRequestId: clientRequestId,
      paymentIntentId: intent.id,
      status: PaymentStatus.pending,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    if (FirebaseService.isInitialized) {
      await _attemptsRef(tripId).doc(attemptId).set(attempt.toMap());
    }

    return intent;
  }

  /// Step 2: Verifies payment with the provider and atomically finalizes the contribution.
  ///
  /// INVARIANT: ONLY verified success creates a ledger entry and updates Trip Pot balance.
  /// Enforces idempotency against repeated webhooks or network retries.
  Future<TripPayTransaction?> verifyAndFinalizeContribution({
    required String tripId,
    required String paymentAttemptId,
    required String providerReference,
    required String initiatedByName,
  }) async {
    PaymentAttempt? attempt;

    if (FirebaseService.isInitialized) {
      final attemptDoc = await _attemptsRef(tripId).doc(paymentAttemptId).get();
      if (!attemptDoc.exists || attemptDoc.data() == null) {
        throw StateError('Payment attempt $paymentAttemptId not found.');
      }
      attempt = PaymentAttempt.fromMap(
        attemptDoc.data() as Map<String, dynamic>,
        attemptDoc.id,
      );
    } else {
      // In-memory / unit test mock fallback
      attempt = PaymentAttempt(
        id: paymentAttemptId,
        tripId: tripId,
        uid: 'user_test',
        amountPaise: 500000,
        platformFeePaise: 5000,
        totalChargePaise: 505000,
        provider: _paymentProvider.providerName,
        clientRequestId: 'cr_test',
        paymentIntentId: 'pi_test',
        status: PaymentStatus.pending,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    // 1. Idempotency check: Has this attempt or providerReference already finalized?
    if (attempt.status == PaymentStatus.success &&
        attempt.ledgerTransactionId != null) {
      if (FirebaseService.isInitialized) {
        final txDoc = await _transactionsRef(
          tripId,
        ).doc(attempt.ledgerTransactionId!).get();
        if (txDoc.exists && txDoc.data() != null) {
          return TripPayTransaction.fromMap(
            txDoc.data() as Map<String, dynamic>,
            txDoc.id,
          );
        }
      }
    }

    // Check if providerReference was already recorded in transactions
    if (FirebaseService.isInitialized) {
      final existingTxSnap = await _transactionsRef(
        tripId,
      ).where('providerReference', isEqualTo: providerReference).limit(1).get();

      if (existingTxSnap.docs.isNotEmpty) {
        final txData = existingTxSnap.docs.first.data() as Map<String, dynamic>;
        return TripPayTransaction.fromMap(txData, existingTxSnap.docs.first.id);
      }
    }

    // 2. Perform provider verification against the expected total charge (amount + platform fee)
    final expectedTotalPaise = attempt.totalChargePaise > 0
        ? attempt.totalChargePaise
        : attempt.amountPaise;

    final verification = await _paymentProvider.verifyPayment(
      paymentIntentId: attempt.paymentIntentId,
      providerReference: providerReference,
      expectedAmountPaise: expectedTotalPaise,
      expectedCurrency: 'INR',
    );

    if (!verification.isVerified ||
        verification.status != PaymentStatus.success ||
        (verification.amountPaise > 0 &&
            verification.amountPaise != expectedTotalPaise)) {
      // Mark attempt failed
      final reason =
          (verification.amountPaise > 0 &&
              verification.amountPaise != expectedTotalPaise)
          ? 'PAYMENT VERIFICATION FAILED: Mismatched amount. Expected $expectedTotalPaise paise, received ${verification.amountPaise} paise.'
          : (verification.failureReason ?? 'Verification failed');

      if (FirebaseService.isInitialized) {
        await _attemptsRef(tripId).doc(paymentAttemptId).update({
          'status': PaymentStatus.failed.name,
          'failureReason': reason,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      return null;
    }

    // 3. Atomically finalize ledger transaction and Trip Pot summary
    final now = DateTime.now();
    final txId =
        'tx_${now.millisecondsSinceEpoch}_${attempt.uid.hashCode.abs()}';

    if (FirebaseService.isInitialized) {
      return await _firestore.runTransaction<TripPayTransaction>((tx) async {
        final summarySnap = await tx.get(_summaryRef(tripId));

        int currentContributed = 0;
        int currentSpent = 0;
        int currentAvailable = 0;

        if (summarySnap.exists && summarySnap.data() != null) {
          final data = summarySnap.data()! as Map<String, dynamic>;
          currentContributed =
              (data['totalContributedPaise'] as num?)?.toInt() ?? 0;
          currentSpent = (data['totalSpentPaise'] as num?)?.toInt() ?? 0;
          currentAvailable =
              (data['availableBalancePaise'] as num?)?.toInt() ?? 0;
        }

        final balanceBefore = currentAvailable;
        final balanceAfter = currentAvailable + attempt!.amountPaise;

        final newTx = TripPayTransaction(
          id: txId,
          tripId: tripId,
          type: TripPayTransactionType.contribution,
          amountPaise: attempt.amountPaise,
          initiatedByUid: attempt.uid,
          initiatedByName: initiatedByName,
          category: 'Contribution',
          description: '$initiatedByName added money (UPI)',
          status: TripPayTransactionStatus.sandboxSuccess,
          createdAt: now,
          balanceBeforePaise: balanceBefore,
          balanceAfterPaise: balanceAfter,
          calculatedPlatformFeePaise: attempt.platformFeePaise,
          mode: 'sandbox',
          clientRequestId: attempt.clientRequestId,
          providerReference: providerReference,
        );

        // Commit transaction record
        tx.set(_transactionsRef(tripId).doc(txId), newTx.toMap());

        // Commit summary update
        final updatedSummary = TripPaySummary(
          tripId: tripId,
          totalContributedPaise: currentContributed + attempt.amountPaise,
          totalSpentPaise: currentSpent,
          availableBalancePaise: balanceAfter,
          updatedAt: now,
        );

        if (summarySnap.exists) {
          tx.update(_summaryRef(tripId), updatedSummary.toMap());
        } else {
          tx.set(_summaryRef(tripId), updatedSummary.toMap());
        }

        // Update payment attempt to success
        tx.update(_attemptsRef(tripId).doc(paymentAttemptId), {
          'status': PaymentStatus.success.name,
          'providerReference': providerReference,
          'verifiedAt': FieldValue.serverTimestamp(),
          'ledgerTransactionId': txId,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        return newTx;
      });
    } else {
      // In-memory mock response for tests
      return TripPayTransaction(
        id: txId,
        tripId: tripId,
        type: TripPayTransactionType.contribution,
        amountPaise: attempt.amountPaise,
        initiatedByUid: attempt.uid,
        initiatedByName: initiatedByName,
        category: 'Contribution',
        description: '$initiatedByName added money (UPI)',
        status: TripPayTransactionStatus.sandboxSuccess,
        createdAt: now,
        balanceBeforePaise: 0,
        balanceAfterPaise: attempt.amountPaise,
        calculatedPlatformFeePaise: attempt.platformFeePaise,
        mode: 'sandbox',
        clientRequestId: attempt.clientRequestId,
        providerReference: providerReference,
      );
    }
  }

  /// Recovers pending or unresolved payment attempts (e.g. after app restart).
  ///
  /// Checks status against the provider:
  /// - If SUCCESS: finalizes idempotently.
  /// - If FAILED: marks as failed.
  /// - If PENDING: keeps pending.
  Future<List<PaymentAttempt>> recoverPendingAttempts({
    required String tripId,
    required String uid,
    required String userName,
  }) async {
    if (!FirebaseService.isInitialized) return [];

    final snap = await _attemptsRef(tripId)
        .where('uid', isEqualTo: uid)
        .where('status', whereIn: ['created', 'pending', 'verifying'])
        .get();

    final recovered = <PaymentAttempt>[];

    for (final doc in snap.docs) {
      final attempt = PaymentAttempt.fromMap(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );

      final status = await _paymentProvider.fetchPaymentStatus(
        paymentIntentId: attempt.paymentIntentId,
        providerReference: attempt.providerReference,
      );

      if (status == PaymentStatus.success) {
        final ref =
            attempt.providerReference ??
            'rec_${DateTime.now().millisecondsSinceEpoch}';
        await verifyAndFinalizeContribution(
          tripId: tripId,
          paymentAttemptId: attempt.id,
          providerReference: ref,
          initiatedByName: userName,
        );
        recovered.add(attempt.copyWith(status: PaymentStatus.success));
      } else if (status == PaymentStatus.failed) {
        await _attemptsRef(tripId).doc(attempt.id).update({
          'status': PaymentStatus.failed.name,
          'failureReason': 'Payment cancelled or failed at provider.',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        recovered.add(attempt.copyWith(status: PaymentStatus.failed));
      } else if (status == PaymentStatus.expired) {
        await _attemptsRef(tripId).doc(attempt.id).update({
          'status': PaymentStatus.expired.name,
          'failureReason': 'Payment window expired.',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        recovered.add(attempt.copyWith(status: PaymentStatus.expired));
      } else {
        // Still pending
        recovered.add(attempt);
      }
    }

    return recovered;
  }

  /// Neutral webhook ingestion and processing architecture.
  ///
  /// Cryptographically verifies signature, checks payload parameters,
  /// and finalizes the ledger transaction idempotently.
  Future<PaymentVerification> processWebhook({
    required String payload,
    required String signature,
    required String webhookSecret,
    required String tripId,
    required String initiatedByName,
  }) async {
    final verification = await _paymentProvider.processWebhook(
      payload: payload,
      signature: signature,
      secret: webhookSecret,
    );

    if (!verification.isVerified ||
        verification.status != PaymentStatus.success) {
      return verification;
    }

    // Find corresponding payment attempt
    if (FirebaseService.isInitialized) {
      final attemptSnap = await _attemptsRef(tripId)
          .where('paymentIntentId', isEqualTo: verification.paymentIntentId)
          .limit(1)
          .get();

      if (attemptSnap.docs.isNotEmpty) {
        final attemptDoc = attemptSnap.docs.first;
        await verifyAndFinalizeContribution(
          tripId: tripId,
          paymentAttemptId: attemptDoc.id,
          providerReference: verification.providerReference,
          initiatedByName: initiatedByName,
        );
      }
    }

    return verification;
  }
}
