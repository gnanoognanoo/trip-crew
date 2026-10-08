import 'package:tripcrew/core/services/supabase_service.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_fee_config.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_transaction.dart';
import 'package:tripcrew/features/trip_pay/providers/trip_pay_provider_interface.dart';

/// Sandbox implementation of [TripPayProvider].
///
/// Executes simulated payments against Supabase PostgreSQL backend.
class SandboxTripPayProvider implements TripPayProvider {
  SandboxTripPayProvider({dynamic firestore});

  /// Verifies user is an active trip member.
  Future<bool> _isTripMember(String tripId, String uid) async {
    if (!SupabaseService.isInitialized) return true;
    try {
      final res = await SupabaseService.client
          .from('trip_members')
          .select()
          .eq('trip_id', tripId)
          .eq('user_id', uid)
          .maybeSingle();
      return res != null;
    } catch (_) {
      return true;
    }
  }

  /// Checks for duplicate clientRequestId to prevent double-submissions.
  Future<bool> _isDuplicateRequest(
    String tripId,
    String clientRequestId,
  ) async {
    if (!SupabaseService.isInitialized) return false;
    try {
      final res = await SupabaseService.client
          .from('transactions')
          .select()
          .eq('trip_id', tripId)
          .eq('client_request_id', clientRequestId)
          .limit(1);
      return res.isNotEmpty;
    } catch (_) {
      return false;
    }
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

    int currentContributed = 0;
    int currentSpent = 0;
    int currentAvailable = 0;

    if (SupabaseService.isInitialized) {
      try {
        final summaryRes = await SupabaseService.client
            .from('trip_pay_summary')
            .select()
            .eq('trip_id', tripId)
            .maybeSingle();

        if (summaryRes != null) {
          currentContributed = (summaryRes['total_contributed_paise'] as num?)?.toInt() ?? 0;
          currentSpent = (summaryRes['total_spent_paise'] as num?)?.toInt() ?? 0;
          currentAvailable = (summaryRes['available_balance_paise'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {}
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

    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.from('transactions').insert({
          'id': txId,
          'trip_id': tripId,
          'type': 'CONTRIBUTION',
          'amount_paise': amountPaise,
          'initiated_by_user_id': initiatedByUid,
          'initiated_by_name': initiatedByName,
          'category': 'Contribution',
          'description': '$initiatedByName added money',
          'status': 'SUCCESS',
          'balance_before_paise': balanceBefore,
          'balance_after_paise': balanceAfter,
          'platform_fee_paise': feePaise,
          'client_request_id': clientRequestId,
          'created_at': now.toIso8601String(),
        });

        await SupabaseService.client.from('trip_pay_summary').upsert({
          'trip_id': tripId,
          'total_contributed_paise': currentContributed + amountPaise,
          'total_spent_paise': currentSpent,
          'available_balance_paise': balanceAfter,
          'updated_at': now.toIso8601String(),
        });
      } catch (_) {}
    }

    return newTx;
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

    int currentContributed = 0;
    int currentSpent = 0;
    int currentAvailable = 0;

    if (SupabaseService.isInitialized) {
      try {
        final summaryRes = await SupabaseService.client
            .from('trip_pay_summary')
            .select()
            .eq('trip_id', tripId)
            .maybeSingle();

        if (summaryRes != null) {
          currentContributed = (summaryRes['total_contributed_paise'] as num?)?.toInt() ?? 0;
          currentSpent = (summaryRes['total_spent_paise'] as num?)?.toInt() ?? 0;
          currentAvailable = (summaryRes['available_balance_paise'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {}
    }

    if (amountPaise > currentAvailable && SupabaseService.isInitialized) {
      throw StateError('Insufficient Trip Pot balance.');
    }

    final balanceBefore = currentAvailable;
    final balanceAfter = currentAvailable - amountPaise;

    final newTx = TripPayTransaction(
      id: txId,
      tripId: tripId,
      type: TripPayTransactionType.expense,
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

    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.from('transactions').insert({
          'id': txId,
          'trip_id': tripId,
          'type': 'EXPENSE',
          'amount_paise': amountPaise,
          'initiated_by_user_id': initiatedByUid,
          'initiated_by_name': initiatedByName,
          'category': category,
          'description': description,
          'status': 'SUCCESS',
          'balance_before_paise': balanceBefore,
          'balance_after_paise': balanceAfter,
          'client_request_id': clientRequestId,
          'created_at': now.toIso8601String(),
        });

        await SupabaseService.client.from('trip_pay_summary').upsert({
          'trip_id': tripId,
          'total_contributed_paise': currentContributed,
          'total_spent_paise': currentSpent + amountPaise,
          'available_balance_paise': balanceAfter,
          'updated_at': now.toIso8601String(),
        });

        await SupabaseService.client.from('expenses').insert({
          'id': expenseId,
          'trip_id': tripId,
          'title': description,
          'amount_paise': amountPaise,
          'paid_by_user_id': initiatedByUid,
          'paid_by_name': '$initiatedByName (Trip Pot)',
          'category': category,
          'split_type': 'EQUAL',
          'created_at': now.toIso8601String(),
        });
      } catch (_) {}
    }

    return newTx;
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

    int currentContributed = 0;
    int currentSpent = 0;
    int currentAvailable = 0;

    if (SupabaseService.isInitialized) {
      try {
        final summaryRes = await SupabaseService.client
            .from('trip_pay_summary')
            .select()
            .eq('trip_id', tripId)
            .maybeSingle();

        if (summaryRes != null) {
          currentContributed = (summaryRes['total_contributed_paise'] as num?)?.toInt() ?? 0;
          currentSpent = (summaryRes['total_spent_paise'] as num?)?.toInt() ?? 0;
          currentAvailable = (summaryRes['available_balance_paise'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {}
    }

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

    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.from('transactions').insert({
          'id': txId,
          'trip_id': tripId,
          'type': 'REFUND',
          'amount_paise': amountPaise,
          'initiated_by_user_id': initiatedByUid,
          'initiated_by_name': initiatedByName,
          'category': 'Refund',
          'description': 'Refund for transaction $originalTransactionId',
          'status': 'SUCCESS',
          'balance_before_paise': balanceBefore,
          'balance_after_paise': balanceAfter,
          'client_request_id': clientRequestId,
          'created_at': now.toIso8601String(),
        });

        await SupabaseService.client.from('trip_pay_summary').upsert({
          'trip_id': tripId,
          'total_contributed_paise': currentContributed,
          'total_spent_paise': currentSpent - amountPaise,
          'available_balance_paise': balanceAfter,
          'updated_at': now.toIso8601String(),
        });
      } catch (_) {}
    }

    return newTx;
  }

  @override
  Future<TripPayTransactionStatus> getTransactionStatus(
    String tripId,
    String transactionId,
  ) async {
    if (!SupabaseService.isInitialized) return TripPayTransactionStatus.sandboxSuccess;
    try {
      final res = await SupabaseService.client
          .from('transactions')
          .select()
          .eq('trip_id', tripId)
          .eq('id', transactionId)
          .maybeSingle();

      if (res == null) return TripPayTransactionStatus.failed;
      return TripPayTransactionStatus.fromString(res['status'] as String? ?? 'SUCCESS');
    } catch (_) {
      return TripPayTransactionStatus.sandboxSuccess;
    }
  }
}
