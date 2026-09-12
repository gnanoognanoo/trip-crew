import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tripcrew/core/services/firebase_service.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
import 'package:tripcrew/features/trip_pay/models/payment_attempt.dart';
import 'package:tripcrew/features/trip_pay/models/payment_intent.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_summary.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_transaction.dart';
import 'package:tripcrew/features/trip_pay/providers/payment_provider.dart';
import 'package:tripcrew/features/trip_pay/providers/sandbox_payment_provider.dart';
import 'package:tripcrew/features/trip_pay/providers/sandbox_trip_pay_provider.dart';
import 'package:tripcrew/features/trip_pay/providers/setu_payment_provider.dart';
import 'package:tripcrew/features/trip_pay/providers/shared_pot_provider.dart';
import 'package:tripcrew/features/trip_pay/services/trusted_payment_service.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Supported payment provider engines.
enum PaymentProviderType {
  sandbox,
  setu;

  String get displayName {
    switch (this) {
      case PaymentProviderType.sandbox:
        return 'Sandbox Simulator';
      case PaymentProviderType.setu:
        return 'Setu UPI UAT';
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
    if (env.toLowerCase() == 'setu') {
      return PaymentProviderType.setu;
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

  late final SandboxTripPayProvider _provider;
  late PaymentProvider _paymentProvider;
  late TrustedPaymentService _trustedPaymentService;
  late SharedPotProvider _sharedPotProvider;

  PaymentProvider get paymentProvider => _paymentProvider;
  SharedPotProvider get sharedPotProvider => _sharedPotProvider;
  TrustedPaymentService get trustedPaymentService => _trustedPaymentService;

  @override
  TripPayState build() {
    final providerType = ref.watch(paymentProviderTypeProvider);
    _provider = SandboxTripPayProvider();

    if (providerType == PaymentProviderType.setu) {
      const backendUrl = String.fromEnvironment(
        'TRIPCREW_BACKEND_URL',
        defaultValue: '',
      );
      _paymentProvider = SetuPaymentProvider(
        backendBaseUrl: backendUrl.isNotEmpty ? backendUrl : null,
      );
    } else {
      _paymentProvider = SandboxPaymentProvider();
    }

    _trustedPaymentService = TrustedPaymentService(
      paymentProvider: _paymentProvider,
    );
    _sharedPotProvider = SandboxSharedPotProvider(innerProvider: _provider);

    ref.onDispose(() {
      _summarySub?.cancel();
      _transactionsSub?.cancel();
      _membersSub?.cancel();
      _attemptsSub?.cancel();
    });

    final activeTrip = ref.watch(activeTripProvider);
    if (activeTrip != null && FirebaseService.isInitialized) {
      _listenToTripPay(activeTrip.id);
      return TripPayState(isLoading: true, providerType: providerType);
    }
    return TripPayState(isLoading: false, providerType: providerType);
  }

  void setPaymentProviderType(PaymentProviderType type) {
    ref.read(paymentProviderTypeProvider.notifier).setType(type);
  }

  void _listenToTripPay(String tripId) {
    _summarySub?.cancel();
    _transactionsSub?.cancel();
    _membersSub?.cancel();
    _attemptsSub?.cancel();

    final firestore = FirebaseFirestore.instance;
    final currentUid = ref.read(authProvider).user?.uid;

    // Listen to summary
    _summarySub = firestore
        .collection('trips')
        .doc(tripId)
        .collection('tripPay')
        .doc('summary')
        .snapshots()
        .listen(
          (snap) {
            if (snap.exists && snap.data() != null) {
              final summary = TripPaySummary.fromMap(snap.data()!);
              state = state.copyWith(summary: summary, isLoading: false);
            } else {
              state = state.copyWith(
                summary: TripPaySummary.empty(tripId),
                isLoading: false,
              );
            }
          },
          onError: (e) {
            state = state.copyWith(
              error: 'Could not sync Trip Pot. Check your connection.',
              isLoading: false,
            );
          },
        );

    // Listen to transactions
    _transactionsSub = firestore
        .collection('trips')
        .doc(tripId)
        .collection('transactions')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (snap) {
            final txList = snap.docs
                .map((doc) => TripPayTransaction.fromMap(doc.data(), doc.id))
                .toList();
            state = state.copyWith(transactions: txList);
          },
          onError: (e) {
            state = state.copyWith(error: 'Could not sync transactions.');
          },
        );

    // Listen to members
    _membersSub = firestore
        .collection('trips')
        .doc(tripId)
        .collection('members')
        .snapshots()
        .listen((snap) {
          final names = <String, String>{};
          for (final doc in snap.docs) {
            names[doc.id] = doc.data()['displayName'] as String? ?? 'Member';
          }
          state = state.copyWith(memberNames: names);
        }, onError: (_) {});

    // Listen to payment attempts for the current user
    if (currentUid != null) {
      _attemptsSub = firestore
          .collection('trips')
          .doc(tripId)
          .collection('paymentAttempts')
          .where('uid', isEqualTo: currentUid)
          .snapshots()
          .listen((snap) {
            final attempts = snap.docs
                .map((d) => PaymentAttempt.fromMap(d.data(), d.id))
                .toList();
            attempts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            state = state.copyWith(paymentAttempts: attempts);
          }, onError: (_) {});
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
      final errorMsg = e is SetuUnconfiguredException
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
  /// ONLY verified success updates the balance and records an immutable ledger transaction.
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

  /// Adds a contribution to the Trip Pot (legacy / direct wrapper for tests).
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

  /// Initiates a payment from the Trip Pot (Layer B spending via SharedPotProvider).
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
}

final tripPayProvider = NotifierProvider<TripPayNotifier, TripPayState>(
  TripPayNotifier.new,
);
