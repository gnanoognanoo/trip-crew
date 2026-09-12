import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tripcrew/core/services/firebase_service.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_fee_config.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_summary.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_transaction.dart';
import 'package:tripcrew/features/trip_pay/providers/trip_pay_provider_interface.dart';

/// Sandbox implementation of [TripPayProvider].
///
/// All transactions are simulated — no real money moves.
/// Uses Firestore transactions for atomic read-validate-write operations.
///
/// IMPORTANT: This provider does NOT move real funds. Every transaction is
/// created with mode = 'sandbox' and status = 'sandbox_success'.
class SandboxTripPayProvider implements TripPayProvider {
  final FirebaseFirestore? _firestoreOverride;

  SandboxTripPayProvider({FirebaseFirestore? firestore})
    : _firestoreOverride = firestore;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  /// Verifies user is an active trip member.
  Future<bool> _isTripMember(String tripId, String uid) async {
    if (!FirebaseService.isInitialized) return true;
    final memberDoc = await _firestore
        .collection('trips')
        .doc(tripId)
        .collection('members')
        .doc(uid)
        .get();
    return memberDoc.exists;
  }

  /// Checks for duplicate clientRequestId to prevent double-submissions.
  Future<bool> _isDuplicateRequest(
    String tripId,
    String clientRequestId,
  ) async {
    final existing = await _firestore
        .collection('trips')
        .doc(tripId)
        .collection('transactions')
        .where('clientRequestId', isEqualTo: clientRequestId)
        .limit(1)
        .get();
    return existing.docs.isNotEmpty;
  }

  DocumentReference _summaryRef(String tripId) {
    return _firestore
        .collection('trips')
        .doc(tripId)
        .collection('tripPay')
        .doc('summary');
  }

  CollectionReference _transactionsRef(String tripId) {
    return _firestore
        .collection('trips')
        .doc(tripId)
        .collection('transactions');
  }

  @override
  Future<TripPayTransaction> createContribution({
    required String tripId,
    required int amountPaise,
    required String initiatedByUid,
    required String initiatedByName,
    required String clientRequestId,
  }) async {
    if (amountPaise <= 0) {
      throw ArgumentError('Contribution amount must be positive.');
    }

    if (!await _isTripMember(tripId, initiatedByUid)) {
      throw StateError('User is not a member of this trip.');
    }

    if (await _isDuplicateRequest(tripId, clientRequestId)) {
      throw StateError('Duplicate contribution request detected.');
    }

    final feePaise = TripPayFeeConfig.calculateFeePaise(amountPaise);
    final txId =
        'tx_${DateTime.now().millisecondsSinceEpoch}_${initiatedByUid.hashCode.abs()}';
    final now = DateTime.now();

    // Atomic Firestore transaction
    final transaction = await _firestore.runTransaction<TripPayTransaction>((
      firestoreTx,
    ) async {
      // Read current summary
      final summarySnap = await firestoreTx.get(_summaryRef(tripId));

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
      final balanceAfter = currentAvailable + amountPaise;

      final newTx = TripPayTransaction(
        id: txId,
        tripId: tripId,
        type: TripPayTransactionType.contribution,
        amountPaise: amountPaise,
        initiatedByUid: initiatedByUid,
        initiatedByName: initiatedByName,
        category: 'Contribution',
        description: '$initiatedByName added money',
        status: TripPayTransactionStatus.sandboxSuccess,
        createdAt: now,
        balanceBeforePaise: balanceBefore,
        balanceAfterPaise: balanceAfter,
        calculatedPlatformFeePaise: feePaise,
        mode: 'sandbox',
        clientRequestId: clientRequestId,
      );

      // Write transaction
      firestoreTx.set(_transactionsRef(tripId).doc(txId), newTx.toMap());

      // Update summary
      final updatedSummary = TripPaySummary(
        tripId: tripId,
        totalContributedPaise: currentContributed + amountPaise,
        totalSpentPaise: currentSpent,
        availableBalancePaise: balanceAfter,
        updatedAt: now,
      );

      if (summarySnap.exists) {
        firestoreTx.update(_summaryRef(tripId), updatedSummary.toMap());
      } else {
        firestoreTx.set(_summaryRef(tripId), updatedSummary.toMap());
      }

      return newTx;
    });

    return transaction;
  }

  @override
  Future<TripPayTransaction> createPayment({
    required String tripId,
    required int amountPaise,
    required String initiatedByUid,
    required String initiatedByName,
    required String description,
    required String category,
    String? merchantName,
    required String clientRequestId,
  }) async {
    if (amountPaise <= 0) {
      throw ArgumentError('Payment amount must be positive.');
    }

    if (!await _isTripMember(tripId, initiatedByUid)) {
      throw StateError('User is not a member of this trip.');
    }

    if (await _isDuplicateRequest(tripId, clientRequestId)) {
      throw StateError('Duplicate payment request detected.');
    }

    final txId =
        'tx_${DateTime.now().millisecondsSinceEpoch}_${initiatedByUid.hashCode.abs()}';
    final expenseId =
        'exp_${DateTime.now().millisecondsSinceEpoch}_${initiatedByUid.hashCode.abs()}';
    final now = DateTime.now();

    final transaction = await _firestore.runTransaction<TripPayTransaction>((
      firestoreTx,
    ) async {
      // Read current summary
      final summarySnap = await firestoreTx.get(_summaryRef(tripId));

      if (!summarySnap.exists || summarySnap.data() == null) {
        throw StateError(
          'Trip Pot has not been initialized. Add a contribution first.',
        );
      }

      final data = summarySnap.data()! as Map<String, dynamic>;
      final currentContributed =
          (data['totalContributedPaise'] as num?)?.toInt() ?? 0;
      final currentSpent = (data['totalSpentPaise'] as num?)?.toInt() ?? 0;
      final currentAvailable =
          (data['availableBalancePaise'] as num?)?.toInt() ?? 0;

      if (amountPaise > currentAvailable) {
        throw StateError('Insufficient Trip Pot balance.');
      }

      final balanceBefore = currentAvailable;
      final balanceAfter = currentAvailable - amountPaise;

      // Read member UIDs for auto-expense participant list
      final membersSnap = await firestoreTx.get(
        _firestore
            .collection('trips')
            .doc(tripId)
            .collection('members')
            .doc(initiatedByUid),
      );
      // We verified membership above; just need all member UIDs for expense
      // Since we can't query inside a transaction, we'll set participants
      // to just the initiator and let the expense be visible to all members
      // via the security rules.

      final newTx = TripPayTransaction(
        id: txId,
        tripId: tripId,
        type: TripPayTransactionType.payment,
        amountPaise: amountPaise,
        initiatedByUid: initiatedByUid,
        initiatedByName: initiatedByName,
        category: category,
        description: description,
        merchantName: merchantName,
        status: TripPayTransactionStatus.sandboxSuccess,
        createdAt: now,
        balanceBeforePaise: balanceBefore,
        balanceAfterPaise: balanceAfter,
        relatedExpenseId: expenseId,
        mode: 'sandbox',
        clientRequestId: clientRequestId,
      );

      // Write transaction
      firestoreTx.set(_transactionsRef(tripId).doc(txId), newTx.toMap());

      // Update summary
      final updatedSummary = TripPaySummary(
        tripId: tripId,
        totalContributedPaise: currentContributed,
        totalSpentPaise: currentSpent + amountPaise,
        availableBalancePaise: balanceAfter,
        updatedAt: now,
      );
      firestoreTx.update(_summaryRef(tripId), updatedSummary.toMap());

      // Auto-create linked expense
      final expenseRef = _firestore
          .collection('trips')
          .doc(tripId)
          .collection('expenses')
          .doc(expenseId);

      firestoreTx.set(expenseRef, {
        'id': expenseId,
        'description': description,
        'amountPaise': amountPaise,
        'category': category,
        'paidByUid': initiatedByUid,
        'paidByName': '$initiatedByName (Trip Pot)',
        'participantUids': [initiatedByUid],
        'splitType': 'trip_pot',
        'createdBy': initiatedByUid,
        'createdAt': now.toIso8601String(),
        'source': 'tripcrew_pay',
        'paymentSource': 'TripCrew Pay',
        'relatedTransactionId': txId,
      });

      // Suppress unused variable warning — we validated membership via
      // the _isTripMember check above. The read here is just to satisfy
      // Firestore transaction requirements if needed.
      final _ = membersSnap;

      return newTx;
    });

    return transaction;
  }

  @override
  Future<TripPayTransaction> refundPayment({
    required String tripId,
    required String originalTransactionId,
    required int amountPaise,
    required String initiatedByUid,
    required String initiatedByName,
    required String clientRequestId,
  }) async {
    if (amountPaise <= 0) {
      throw ArgumentError('Refund amount must be positive.');
    }

    if (!await _isTripMember(tripId, initiatedByUid)) {
      throw StateError('User is not a member of this trip.');
    }

    if (await _isDuplicateRequest(tripId, clientRequestId)) {
      throw StateError('Duplicate refund request detected.');
    }

    final txId = 'tx_${DateTime.now().millisecondsSinceEpoch}_ref';
    final now = DateTime.now();

    final transaction = await _firestore.runTransaction<TripPayTransaction>((
      firestoreTx,
    ) async {
      final summarySnap = await firestoreTx.get(_summaryRef(tripId));

      if (!summarySnap.exists || summarySnap.data() == null) {
        throw StateError('Trip Pot summary not found.');
      }

      final data = summarySnap.data()! as Map<String, dynamic>;
      final currentContributed =
          (data['totalContributedPaise'] as num?)?.toInt() ?? 0;
      final currentSpent = (data['totalSpentPaise'] as num?)?.toInt() ?? 0;
      final currentAvailable =
          (data['availableBalancePaise'] as num?)?.toInt() ?? 0;

      final balanceBefore = currentAvailable;
      final balanceAfter = currentAvailable + amountPaise;

      final newTx = TripPayTransaction(
        id: txId,
        tripId: tripId,
        type: TripPayTransactionType.refund,
        amountPaise: amountPaise,
        initiatedByUid: initiatedByUid,
        initiatedByName: initiatedByName,
        category: 'Refund',
        description: 'Refund for transaction $originalTransactionId',
        status: TripPayTransactionStatus.sandboxSuccess,
        createdAt: now,
        balanceBeforePaise: balanceBefore,
        balanceAfterPaise: balanceAfter,
        relatedTransactionId: originalTransactionId,
        mode: 'sandbox',
        clientRequestId: clientRequestId,
      );

      firestoreTx.set(_transactionsRef(tripId).doc(txId), newTx.toMap());

      final updatedSummary = TripPaySummary(
        tripId: tripId,
        totalContributedPaise: currentContributed,
        totalSpentPaise: currentSpent - amountPaise,
        availableBalancePaise: balanceAfter,
        updatedAt: now,
      );
      firestoreTx.update(_summaryRef(tripId), updatedSummary.toMap());

      return newTx;
    });

    return transaction;
  }

  @override
  Future<TripPayTransactionStatus> getTransactionStatus(
    String tripId,
    String transactionId,
  ) async {
    final doc = await _transactionsRef(tripId).doc(transactionId).get();
    if (!doc.exists) {
      return TripPayTransactionStatus.failed;
    }
    final data = doc.data() as Map<String, dynamic>?;
    return TripPayTransactionStatus.fromString(
      data?['status'] as String? ?? 'pending',
    );
  }
}
