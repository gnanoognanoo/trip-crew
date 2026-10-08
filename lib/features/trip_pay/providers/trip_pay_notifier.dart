import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tripcrew/core/services/supabase_service.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
import 'package:tripcrew/features/trip_pay/models/payment_attempt.dart';
import 'package:tripcrew/features/trip_pay/models/payment_intent.dart';
import 'package:tripcrew/features/trip_pay/models/settlement_model.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_summary.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_transaction.dart';
import 'package:tripcrew/features/trip_pay/providers/payment_provider.dart';
import 'package:tripcrew/features/trip_pay/providers/sandbox_payment_provider.dart';
import 'package:tripcrew/features/trip_pay/providers/sandbox_trip_pay_provider.dart';
import 'package:tripcrew/features/trip_pay/providers/razorpay_payment_provider.dart';
import 'package:tripcrew/features/trip_pay/providers/shared_pot_provider.dart';
import 'package:tripcrew/features/trip_pay/services/trusted_payment_service.dart';
import 'package:tripcrew/features/trip_pay/services/trip_settlement_service.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Supported payment provider engines.
enum PaymentProviderType {
  sandbox,
  razorpay;

  String get displayName {
    switch (this) {
      case PaymentProviderType.sandbox:
        return 'Sandbox Simulator';
      case PaymentProviderType.razorpay:
        return 'Razorpay Integration';
    }
  }
}

/// Filter options for the transaction history view.
enum TripPayFilter {
  all,
  contributions,
  payments,
  refunds,
  myActivity;

  String get label {
    switch (this) {
      case TripPayFilter.all:
        return 'All';
      case TripPayFilter.contributions:
        return 'Contributions';
      case TripPayFilter.payments:
        return 'Payments';
      case TripPayFilter.refunds:
        return 'Refunds';
      case TripPayFilter.myActivity:
        return 'My Activity';
    }
  }
}

/// Per-member contribution stats.
class MemberContribution {
  final String uid;
  final String displayName;
  final int totalContributedPaise;
  final int paymentsInitiated;
  final int totalSpendingInitiatedPaise;

  const MemberContribution({
    required this.uid,
    required this.displayName,
    this.totalContributedPaise = 0,
    this.paymentsInitiated = 0,
    this.totalSpendingInitiatedPaise = 0,
  });
}

/// Combined state for TripCrew Pay.
class TripPayState {
  final bool isLoading;
  final String? error;
  final TripPaySummary? summary;
  final List<TripPayTransaction> transactions;
  final List<PaymentAttempt> paymentAttempts;
  final Map<String, String> memberNames;
  final TripPayFilter activeFilter;
  final bool isProcessing;
  final bool isTestMode;
  final PaymentProviderType providerType;

  const TripPayState({
    this.isLoading = true,
    this.error,
    this.summary,
    this.transactions = const [],
    this.paymentAttempts = const [],
    this.memberNames = const {},
    this.activeFilter = TripPayFilter.all,
    this.isProcessing = false,
    this.isTestMode = true,
    this.providerType = PaymentProviderType.sandbox,
  });

  TripPayState copyWith({
    bool? isLoading,
    String? error,
    bool clearError = false,
    TripPaySummary? summary,
    List<TripPayTransaction>? transactions,
    List<PaymentAttempt>? paymentAttempts,
    Map<String, String>? memberNames,
    TripPayFilter? activeFilter,
    bool? isProcessing,
    bool? isTestMode,
    PaymentProviderType? providerType,
  }) {
    return TripPayState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      summary: summary ?? this.summary,
      transactions: transactions ?? this.transactions,
      paymentAttempts: paymentAttempts ?? this.paymentAttempts,
      memberNames: memberNames ?? this.memberNames,
      activeFilter: activeFilter ?? this.activeFilter,
      isProcessing: isProcessing ?? this.isProcessing,
      isTestMode: isTestMode ?? this.isTestMode,
      providerType: providerType ?? this.providerType,
    );
  }

  /// Dynamic settlement plan computed for current trip state.
  SettlementPlan get settlementPlan {
    final service = TripSettlementService();
    return service.buildSettlementPlan(
      tripId: summary?.tripId ?? '',
      memberNames: memberNames,
      transactions: transactions,
      summary: summary,
    );
  }

  /// Transactions filtered by the active filter.
  List<TripPayTransaction> filteredTransactions(String? currentUid) {
    switch (activeFilter) {
      case TripPayFilter.all:
        return transactions;
      case TripPayFilter.contributions:
        return transactions
            .where((tx) => tx.type == TripPayTransactionType.contribution)
            .toList();
      case TripPayFilter.payments:
        return transactions
            .where((tx) => tx.type == TripPayTransactionType.payment)
            .toList();
      case TripPayFilter.refunds:
        return transactions
            .where((tx) => tx.type == TripPayTransactionType.refund)
            .toList();
      case TripPayFilter.myActivity:
        if (currentUid == null) return [];
        return transactions
            .where((tx) => tx.initiatedByUid == currentUid)
            .toList();
    }
  }

  /// Calculates per-member contribution and spending stats from ledger.
  List<MemberContribution> get memberContributions {
    final Map<String, int> contributed = {};
    final Map<String, int> paymentCount = {};
    final Map<String, int> spendingInitiated = {};

    for (final tx in transactions) {
      final uid = tx.initiatedByUid;
      if (tx.type == TripPayTransactionType.contribution &&
          tx.status == TripPayTransactionStatus.sandboxSuccess) {
        contributed[uid] = (contributed[uid] ?? 0) + tx.amountPaise;
      }
      if (tx.type == TripPayTransactionType.payment &&
          tx.status == TripPayTransactionStatus.sandboxSuccess) {
        paymentCount[uid] = (paymentCount[uid] ?? 0) + 1;
        spendingInitiated[uid] = (spendingInitiated[uid] ?? 0) + tx.amountPaise;
      }
    }

    return memberNames.entries.map((entry) {
      return MemberContribution(
        uid: entry.key,
        displayName: entry.value,
        totalContributedPaise: contributed[entry.key] ?? 0,
        paymentsInitiated: paymentCount[entry.key] ?? 0,
        totalSpendingInitiatedPaise: spendingInitiated[entry.key] ?? 0,
      );
    }).toList();
  }

  /// Trip-end settlement preview.
  /// Returns map of uid -> net position paise (positive = gets refund, negative = under-contributed).
  Map<String, int> calculateSettlementPreview() {
    if (summary == null) return {};
    final remaining = summary!.availableBalancePaise;
    if (remaining <= 0) return {};

    final contributions = memberContributions;
    final totalContributed = summary!.totalContributedPaise;
    if (totalContributed <= 0) return {};

    final Map<String, int> settlements = {};
    for (final mc in contributions) {
      if (mc.totalContributedPaise > 0) {
        // Proportional refund based on contribution ratio
        final share = mc.totalContributedPaise * remaining ~/ totalContributed;
        settlements[mc.uid] = share;
      }
    }
    return settlements;
  }
}

/// Notifier for currently active payment engine.
class PaymentProviderTypeNotifier extends Notifier<PaymentProviderType> {
  @override
  PaymentProviderType build() {
    const env = String.fromEnvironment(
      'PAYMENT_PROVIDER',
      defaultValue: 'sandbox',
    );
    if (env.toLowerCase() == 'razorpay') {
      return PaymentProviderType.razorpay;
    }
    return PaymentProviderType.sandbox;
  }

  void setType(PaymentProviderType type) {
    state = type;
  }
}

/// Global provider for currently active payment engine.
final paymentProviderTypeProvider =
    NotifierProvider<PaymentProviderTypeNotifier, PaymentProviderType>(
      PaymentProviderTypeNotifier.new,
    );

/// Riverpod notifier managing TripCrew Pay state with real-time Firestore listeners.
class TripPayNotifier extends Notifier<TripPayState> {
  StreamSubscription? _summarySub;
  StreamSubscription? _transactionsSub;
  StreamSubscription? _membersSub;
  StreamSubscription? _attemptsSub;

  final SandboxTripPayProvider _provider = SandboxTripPayProvider();
  late PaymentProvider _paymentProvider;
  late TrustedPaymentService _trustedPaymentService;
  late SharedPotProvider _sharedPotProvider;
  late TripSettlementService _settlementService;

  PaymentProvider get paymentProvider => _paymentProvider;
  SharedPotProvider get sharedPotProvider => _sharedPotProvider;
  TrustedPaymentService get trustedPaymentService => _trustedPaymentService;
  TripSettlementService get settlementService => _settlementService;

  @override
  TripPayState build() {
    final providerType = ref.watch(paymentProviderTypeProvider);

    if (providerType == PaymentProviderType.razorpay) {
      const backendUrl = String.fromEnvironment(
        'TRIPCREW_BACKEND_URL',
        defaultValue: 'https://trip-creww-production.up.railway.app',
      );
      const verifyUrl = String.fromEnvironment(
        'TRIPCREW_VERIFY_URL',
        defaultValue: '',
      );
      final defaultSupabaseVerifyUrl =
          '${SupabaseService.defaultUrl.replaceAll(RegExp(r'/$'), '')}/functions/v1/razorpay-verify';

      _paymentProvider = RazorpayPaymentProvider(
        backendBaseUrl: backendUrl.isNotEmpty ? backendUrl : 'https://trip-creww-production.up.railway.app',
        verificationUrl: verifyUrl.isNotEmpty ? verifyUrl : defaultSupabaseVerifyUrl,
      );
    } else {
      _paymentProvider = SandboxPaymentProvider();
    }

    _trustedPaymentService = TrustedPaymentService(
      paymentProvider: _paymentProvider,
    );
    _sharedPotProvider = SandboxSharedPotProvider(innerProvider: _provider);
    _settlementService = TripSettlementService();

    ref.onDispose(() {
      _summarySub?.cancel();
      _transactionsSub?.cancel();
      _membersSub?.cancel();
      _attemptsSub?.cancel();
    });

    final activeTrip = ref.watch(activeTripProvider);
    if (activeTrip != null) {
      _listenToTripPay(activeTrip.id);
      return TripPayState(isLoading: true, providerType: providerType);
    }
    return TripPayState(isLoading: false, providerType: providerType);
  }

  void setPaymentProviderType(PaymentProviderType type) {
    ref.read(paymentProviderTypeProvider.notifier).setType(type);
  }

  Future<void> fetchTripPay(String tripId) async {
    final currentUid = ref.read(authProvider).user?.uid;
    developer.log('[TRIPPAY_DEBUG] fetchTripPay START | tripId = $tripId | current user = $currentUid', name: 'TripPayNotifier');
    developer.log('[TRIPPAY_DEBUG] Supabase.isInitialized = ${SupabaseService.isInitialized}', name: 'TripPayNotifier');

    if (!SupabaseService.isInitialized) {
      state = state.copyWith(isLoading: false);
      developer.log('[TRIPPAY_DEBUG] Aborting: Supabase is not initialized', name: 'TripPayNotifier');
      return;
    }
    try {
      // 1. Fetch Summary
      developer.log('[TRIPPAY_DEBUG] summary query START', name: 'TripPayNotifier');
      final summaryRes = await SupabaseService.client
          .from('trip_pay_summary')
          .select()
          .eq('trip_id', tripId)
          .maybeSingle();

      developer.log('[TRIPPAY_DEBUG] summary query RESULT = $summaryRes', name: 'TripPayNotifier');

      final summary = summaryRes != null
          ? TripPaySummary.fromMap(Map<String, dynamic>.from(summaryRes))
          : TripPaySummary.empty(tripId);

      // 2. Fetch Transactions
      developer.log('[TRIPPAY_DEBUG] transactions query START', name: 'TripPayNotifier');
      final txRes = await SupabaseService.client
          .from('transactions')
          .select()
          .eq('trip_id', tripId)
          .order('created_at', ascending: false);

      developer.log('[TRIPPAY_DEBUG] transactions query RESULT = ${txRes.length} rows', name: 'TripPayNotifier');

      final txList = txRes
          .map((m) => TripPayTransaction.fromMap(Map<String, dynamic>.from(m), m['id'] as String))
          .toList();

      // 3. Fetch Trip Members & Profiles (Safe 2-step fetch without unconstrained join)
      final names = <String, String>{};
      try {
        developer.log('[TRIPPAY_DEBUG] trip_members query START', name: 'TripPayNotifier');
        final membersRes = await SupabaseService.client
            .from('trip_members')
            .select('user_id, role')
            .eq('trip_id', tripId);

        developer.log('[TRIPPAY_DEBUG] trip_members RESULT = ${membersRes.length} rows', name: 'TripPayNotifier');

        final uids = membersRes.map((m) => m['user_id'] as String).toList();
        if (uids.isNotEmpty) {
          try {
            developer.log('[TRIPPAY_DEBUG] profiles query START', name: 'TripPayNotifier');
            final profilesRes = await SupabaseService.client
                .from('profiles')
                .select('id, display_name, full_name')
                .inFilter('id', uids);

            developer.log('[TRIPPAY_DEBUG] profiles RESULT = ${profilesRes.length} rows', name: 'TripPayNotifier');

            for (final p in profilesRes) {
              final pid = p['id'] as String;
              final dName = p['display_name'] as String? ?? p['full_name'] as String? ?? 'Member';
              names[pid] = dName;
            }
          } catch (pe) {
            developer.log('[TRIPPAY_DEBUG] profiles ERROR = $pe', name: 'TripPayNotifier');
          }
        }
        for (final u in uids) {
          names.putIfAbsent(u, () => 'Member');
        }
      } catch (me) {
        developer.log('[TRIPPAY_DEBUG] trip_members ERROR = $me', name: 'TripPayNotifier');
      }

      // 4. Fetch Payment Attempts
      List<PaymentAttempt> attempts = [];
      if (currentUid != null) {
        try {
          final attRes = await SupabaseService.client
              .from('payment_attempts')
              .select()
              .eq('trip_id', tripId)
              .eq('user_id', currentUid)
              .order('created_at', ascending: false);

          attempts = attRes
              .map((m) => PaymentAttempt.fromMap(Map<String, dynamic>.from(m), m['id'] as String))
              .toList();
        } catch (_) {}
      }

      state = state.copyWith(
        isLoading: false,
        summary: summary,
        transactions: txList,
        memberNames: names,
        paymentAttempts: attempts,
      );

      developer.log('[TRIPPAY_DEBUG] fetchTripPay END | final isLoading = ${state.isLoading} | summary balance = ${summary.availableBalancePaise}', name: 'TripPayNotifier');
    } catch (e) {
      developer.log('[TRIPPAY_DEBUG] fetchTripPay FATAL ERROR = $e', name: 'TripPayNotifier');
      state = state.copyWith(
        isLoading: false,
        summary: TripPaySummary.empty(tripId),
        error: e.toString(),
      );
    }
  }

  void _listenToTripPay(String tripId) {
    _summarySub?.cancel();
    _transactionsSub?.cancel();

    fetchTripPay(tripId);

    if (SupabaseService.isInitialized) {
      try {
        _summarySub = SupabaseService.client
            .from('trip_pay_summary')
            .stream(primaryKey: ['trip_id'])
            .eq('trip_id', tripId)
            .listen((data) {
              final summary = data.isNotEmpty
                  ? TripPaySummary.fromMap(Map<String, dynamic>.from(data.first))
                  : TripPaySummary.empty(tripId);
              state = state.copyWith(summary: summary, isLoading: false);
            });

        _transactionsSub = SupabaseService.client
            .from('transactions')
            .stream(primaryKey: ['id'])
            .eq('trip_id', tripId)
            .listen((data) {
              final txList = data
                  .map((m) => TripPayTransaction.fromMap(Map<String, dynamic>.from(m), m['id'] as String))
                  .toList();
              txList.sort((a, b) => b.createdAt.compareTo(a.createdAt));
              state = state.copyWith(transactions: txList, isLoading: false);
            });
      } catch (_) {
        state = state.copyWith(isLoading: false);
      }
    }
  }

  void setFilter(TripPayFilter filter) {
    state = state.copyWith(activeFilter: filter);
  }

  /// Step 1: Creates a contribution intent with provider rails (UPI intent/QR).
  Future<PaymentIntent?> initiateContributionIntent({
    required String tripId,
    required int amountPaise,
    required String clientRequestId,
  }) async {
    final user = ref.read(authProvider).user;
    if (user == null) return null;

    state = state.copyWith(isProcessing: true, clearError: true);
    try {
      final intent = await _trustedPaymentService.initiateContribution(
        tripId: tripId,
        uid: user.uid,
        amountPaise: amountPaise,
        clientRequestId: clientRequestId,
      );
      state = state.copyWith(isProcessing: false);
      return intent;
    } catch (e) {
      final errorMsg = e is RazorpayUnconfiguredException
          ? e.message
          : e
                .toString()
                .replaceAll('Exception: ', '')
                .replaceAll('StateError: ', '');
      state = state.copyWith(isProcessing: false, error: errorMsg);
      return null;
    }
  }

  /// Step 2: Verifies payment with trusted backend and atomically updates Trip Pot balance.
  Future<bool> verifyAndFinalizeContribution({
    required String tripId,
    required String paymentAttemptId,
    required String providerReference,
  }) async {
    final user = ref.read(authProvider).user;
    if (user == null) return false;

    state = state.copyWith(isProcessing: true, clearError: true);
    try {
      final tx = await _trustedPaymentService.verifyAndFinalizeContribution(
        tripId: tripId,
        paymentAttemptId: paymentAttemptId,
        providerReference: providerReference,
        initiatedByName: user.name,
      );
      if (tx != null) {
        await fetchTripPay(tripId);
      }
      state = state.copyWith(isProcessing: false);
      return tx != null;
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        error: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  /// Recovers pending or unresolved payment attempts after app restart or reopen.
  Future<void> recoverPendingPayments(String tripId) async {
    final user = ref.read(authProvider).user;
    if (user == null) return;

    try {
      await _trustedPaymentService.recoverPendingAttempts(
        tripId: tripId,
        uid: user.uid,
        userName: user.name,
      );
    } catch (_) {}
  }

  /// Adds a contribution to the Trip Pot.
  Future<bool> addContribution({
    required String tripId,
    required int amountPaise,
    required String clientRequestId,
  }) async {
    final user = ref.read(authProvider).user;
    if (user == null) return false;

    state = state.copyWith(isProcessing: true, clearError: true);
    try {
      final intent = await _trustedPaymentService.initiateContribution(
        tripId: tripId,
        uid: user.uid,
        amountPaise: amountPaise,
        clientRequestId: clientRequestId,
      );

      final attemptId = state.paymentAttempts.isNotEmpty
          ? state.paymentAttempts.first.id
          : 'att_${DateTime.now().millisecondsSinceEpoch}';

      final tx = await _trustedPaymentService.verifyAndFinalizeContribution(
        tripId: tripId,
        paymentAttemptId: attemptId,
        providerReference: 'ref_${intent.id}',
        initiatedByName: user.name,
      );

      state = state.copyWith(isProcessing: false);
      return tx != null;
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        error: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  /// Initiates a payment from the Trip Pot.
  Future<bool> makePayment({
    required String tripId,
    required int amountPaise,
    required String description,
    required String category,
    String? merchantName,
    required String clientRequestId,
  }) async {
    final user = ref.read(authProvider).user;
    if (user == null) return false;

    state = state.copyWith(isProcessing: true, clearError: true);
    try {
      await _sharedPotProvider.spendFromPot(
        tripId: tripId,
        amountPaise: amountPaise,
        initiatedByUid: user.uid,
        initiatedByName: user.name,
        description: description,
        category: category,
        merchantName: merchantName,
        clientRequestId: clientRequestId,
      );
      state = state.copyWith(isProcessing: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        error: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  /// Initiates a sandbox refund for a previous payment back to the Trip Pot.
  Future<bool> refundPayment({
    required String tripId,
    required String originalTransactionId,
    required int amountPaise,
    required String clientRequestId,
  }) async {
    final user = ref.read(authProvider).user;
    if (user == null) return false;

    state = state.copyWith(isProcessing: true, clearError: true);
    try {
      await _provider.refundPayment(
        tripId: tripId,
        originalTransactionId: originalTransactionId,
        amountPaise: amountPaise,
        initiatedByUid: user.uid,
        initiatedByName: user.name,
        clientRequestId: clientRequestId,
      );
      state = state.copyWith(isProcessing: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        error: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  /// Executes atomic settlement for the active trip on Firestore.
  Future<bool> executeSettlement({required String tripId}) async {
    final user = ref.read(authProvider).user;
    if (user == null) return false;

    state = state.copyWith(isProcessing: true, clearError: true);
    try {
      final plan = state.settlementPlan;
      final success = await _settlementService.executeAtomicSettlement(
        tripId: tripId,
        plan: plan,
        initiatedByUid: user.uid,
        initiatedByName: user.name,
      );
      state = state.copyWith(isProcessing: false);
      return success;
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        error: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }
}

final tripPayProvider = NotifierProvider<TripPayNotifier, TripPayState>(
  TripPayNotifier.new,
);
