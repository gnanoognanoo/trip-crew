import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/core/utils/currency_formatter.dart';
import 'package:tripcrew/core/widgets/app_empty_state.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
import 'package:tripcrew/features/shared/presentation/beta_feedback_sheet.dart';
import 'package:tripcrew/features/trip_pay/models/payment_attempt.dart';
import 'package:tripcrew/features/trip_pay/models/settlement_model.dart';
import 'package:tripcrew/features/trip_pay/models/trip_pay_transaction.dart';
import 'package:tripcrew/features/trip_pay/providers/trip_pay_notifier.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Tracks users who have already seen the first-use explanation for TripCrew Pay.
class TripPayIntroNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void markSeen(String uid) {
    state = {...state, uid};
  }
}

final tripPayIntroSeenUsersProvider =
    NotifierProvider<TripPayIntroNotifier, Set<String>>(
      TripPayIntroNotifier.new,
    );

/// Main TripCrew Pay hub screen with complete Transaction History.
/// Features:
/// - Real-time Firestore snapshots via Riverpod stream listener
/// - Filter chips (All, Contributions, Payments, Refunds, My Activity)
/// - Date grouping headers (Today, Yesterday, EEE, dd MMM yyyy)
/// - Running balance displayed on each transaction tile
/// - Member avatar with initials & color coding
/// - Interactive merchant & description search bar
class TripPayScreen extends ConsumerStatefulWidget {
  const TripPayScreen({super.key});

  @override
  ConsumerState<TripPayScreen> createState() => _TripPayScreenState();
}

class _TripPayScreenState extends ConsumerState<TripPayScreen> {
  int _activeSection = 0; // 0: History, 1: Crew Activity, 2: Settlement
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isRetryingVerification = false;
  String? _retryingAttemptId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final activeTrip = ref.read(activeTripProvider);
      final currentUser = ref.read(authProvider).user;

      if (activeTrip != null) {
        AnalyticsService.logTripPayOpened(activeTrip.id);
        ref
            .read(tripPayProvider.notifier)
            .recoverPendingPayments(activeTrip.id);
      }

      if (currentUser != null && currentUser.uid.isNotEmpty) {
        final seen = ref.read(tripPayIntroSeenUsersProvider);
        if (!seen.contains(currentUser.uid)) {
          _showExplanationModal(context);
        }
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showExplanationModal(BuildContext context, {bool force = false}) {
    final currentUser = ref.read(authProvider).user;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF0F4C81,
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.savings_rounded,
                          color: Color(0xFF0F4C81),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'TripCrew Pay',
                        style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'SANDBOX',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Everyone in your crew adds their share to one shared Trip Pot.\n\n'
                'Any joined crew member can use the pot during the trip.\n\n'
                'Every payment records who initiated it so the entire crew can see where the money went.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      color: Color(0xFFB45309),
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'SANDBOX • No real money is transferred. This outing is a group simulation.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (currentUser != null && currentUser.uid.isNotEmpty) {
                      ref
                          .read(tripPayIntroSeenUsersProvider.notifier)
                          .markSeen(currentUser.uid);
                    }
                    Navigator.pop(ctx);
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateHeader(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final txDate = DateTime(dt.year, dt.month, dt.day);

    if (txDate == today) {
      return 'Today';
    } else if (txDate == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('EEE, dd MMM yyyy').format(dt);
    }
  }

  Map<String, List<TripPayTransaction>> _groupTransactionsByDate(
    List<TripPayTransaction> transactions,
  ) {
    final Map<String, List<TripPayTransaction>> grouped = {};
    for (final tx in transactions) {
      final key = _formatDateHeader(tx.createdAt);
      grouped.putIfAbsent(key, () => []).add(tx);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tripPayState = ref.watch(tripPayProvider);
    final activeTrip = ref.watch(activeTripProvider);
    final currentUser = ref.watch(authProvider).user;

    if (activeTrip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('TripCrew Pay')),
        body: const Center(child: Text('No active trip selected.')),
      );
    }

    final summary = tripPayState.summary;
    final allFilteredTx = tripPayState.filteredTransactions(currentUser?.uid);

    // Filter by search query (Merchant, Notes, Category, Initiator)
    final filteredTx = allFilteredTx.where((tx) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase().trim();
      final merchant = tx.merchantName?.toLowerCase() ?? '';
      final desc = tx.description.toLowerCase();
      final category = tx.category.toLowerCase();
      final initiator = tx.initiatedByName.toLowerCase();
      return merchant.contains(q) ||
          desc.contains(q) ||
          category.contains(q) ||
          initiator.contains(q);
    }).toList();

    final groupedTx = _groupTransactionsByDate(filteredTx);
    final memberContribs = tripPayState.memberContributions;

    int myContributionPaise = 0;
    if (currentUser != null) {
      for (final mc in memberContribs) {
        if (mc.uid == currentUser.uid) {
          myContributionPaise = mc.totalContributedPaise;
          break;
        }
      }
    }

    final targetPaise = CurrencyFormatter.toSmallestUnit(activeTrip.budget);
    final collectedPaise = summary?.totalContributedPaise ?? 0;
    final progress = targetPaise > 0 ? (collectedPaise / targetPaise) : 0.0;
    final percent = (progress * 100).clamp(0, 999).toStringAsFixed(0);
    final pendingAttempts = tripPayState.paymentAttempts
        .where((a) => a.isPending)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('TripCrew Pay'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.rate_review_outlined),
            tooltip: 'Beta Feedback',
            onPressed: () =>
                BetaFeedbackSheet.show(context, tripId: activeTrip.id),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: 'How TripCrew Pay works',
            onPressed: () => _showExplanationModal(context, force: true),
          ),
        ],
      ),
      body: SafeArea(
        child: tripPayState.isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spaceLg,
                      ),
                      children: [
                        const SizedBox(height: AppConstants.spaceSm),

                        // Mode Banner
                        _buildSandboxBanner(),
                        const SizedBox(height: AppConstants.spaceSm),

                        // Pending Payment Recovery Banner
                        if (pendingAttempts.isNotEmpty)
                          _buildPendingRecoveryBanner(
                            theme,
                            pendingAttempts.first,
                            activeTrip.id,
                          ),
                        const SizedBox(height: AppConstants.spaceSm),

                        // Shared Pot Overview Card
                        _buildPotCard(
                          theme,
                          summary,
                          activeTrip.name,
                          myContributionPaise,
                        ),
                        const SizedBox(height: AppConstants.spaceMd),

                        // Contribution Progress Card
                        _buildContributionProgressCard(
                          theme,
                          targetPaise,
                          collectedPaise,
                          percent,
                          progress,
                          memberContribs,
                        ),
                        const SizedBox(height: AppConstants.spaceLg),

                        // Action Buttons: Add Your Share & Pay from Pot
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () =>
                                    context.push('/trip-pay/contribute'),
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text('Add Your Share'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppConstants.spaceSm),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed:
                                    (summary?.availableBalancePaise ?? 0) > 0
                                    ? () => context.push('/trip-pay/pay')
                                    : null,
                                icon: const Icon(
                                  Icons.payment_rounded,
                                  size: 18,
                                ),
                                label: const Text('Pay from Trip Pot'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppConstants.spaceLg),

                        // Navigation Tabs
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildSectionChip('Transaction History', 0, () {
                                setState(() => _activeSection = 0);
                                AnalyticsService.logTransactionHistoryOpened(
                                  activeTrip.id,
                                );
                              }),
                              const SizedBox(width: AppConstants.spaceSm),
                              _buildSectionChip(
                                'Crew Activity',
                                1,
                                () => setState(() => _activeSection = 1),
                              ),
                              const SizedBox(width: AppConstants.spaceSm),
                              _buildSectionChip(
                                'Settlement',
                                2,
                                () => setState(() => _activeSection = 2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppConstants.spaceMd),

                        // SECTION 0: COMPLETE TRANSACTION HISTORY
                        if (_activeSection == 0) ...[
                          // 1. Search Bar (Search by merchant / notes)
                          TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search by merchant, note, or member...',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                    )
                                  : null,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onChanged: (val) {
                              setState(() => _searchQuery = val);
                            },
                          ),
                          const SizedBox(height: AppConstants.spaceSm),

                          // 2. Filter Chips
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: TripPayFilter.values.map((filter) {
                                final isActive =
                                    tripPayState.activeFilter == filter;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: FilterChip(
                                    label: Text(
                                      filter.label,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isActive
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                    selected: isActive,
                                    onSelected: (_) {
                                      ref
                                          .read(tripPayProvider.notifier)
                                          .setFilter(filter);
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: AppConstants.spaceSm),

                          // 3. Grouped Transaction List with Date Headers & Running Balances
                          if (filteredTx.isEmpty)
                            AppEmptyState(
                              icon: Icons.receipt_long_rounded,
                              title: _searchQuery.isNotEmpty
                                  ? 'No matching transactions'
                                  : 'No transactions yet',
                              message: _searchQuery.isNotEmpty
                                  ? 'No transactions found matching "$_searchQuery".'
                                  : 'Trip activity will appear here once contributions or payments are made.',
                            )
                          else
                            ...groupedTx.entries.expand((entry) {
                              return [
                                _buildDateHeader(theme, entry.key),
                                ...entry.value.map(
                                  (tx) => _buildTransactionTile(theme, tx),
                                ),
                              ];
                            }),
                        ],

                        // SECTION 1: CREW SPENDING ACTIVITY
                        if (_activeSection == 1) ...[
                          Text(
                            'CREW ACTIVITY',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppConstants.spaceSm),
                          if (memberContribs.isEmpty)
                            const AppEmptyState(
                              icon: Icons.insights_rounded,
                              title: 'No activity yet',
                              message:
                                  'Crew activity will appear once payments are initiated from the Trip Pot.',
                            )
                          else
                            ...memberContribs.map(
                              (mc) => _buildActivityTile(theme, mc),
                            ),
                        ],

                        // SECTION 2: TRIP-END SETTLEMENT PREVIEW
                        if (_activeSection == 2) ...[
                          _buildSettlementPreview(
                            context,
                            ref,
                            theme,
                            summary,
                            tripPayState.settlementPlan,
                            tripPayState.memberNames,
                            activeTrip.id,
                            tripPayState.isProcessing,
                          ),
                        ],

                        const SizedBox(height: AppConstants.space2xl),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildDateHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSandboxBanner() {
    final tripPayState = ref.watch(tripPayProvider);
    final isRazorpay =
        tripPayState.providerType == PaymentProviderType.razorpay;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: Color(0xFFB45309), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isRazorpay
                  ? 'TripCrew Pay • PAYMENT TEST MODE • Razorpay Orders API • No real money is transferred.'
                  : 'PAYMENT TEST MODE • Sandbox UPI Simulator • No real money is transferred.',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF92400E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingRecoveryBanner(
    ThemeData theme,
    PaymentAttempt attempt,
    String tripId,
  ) {
    final isRetryingThis =
        _isRetryingVerification && _retryingAttemptId == attempt.id;

    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: const Color(0xFF3B82F6)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF2563EB),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pending Payment Confirmation',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E40AF),
                  ),
                ),
                Text(
                  '${CurrencyFormatter.formatUnits(attempt.amountPaise)} contribution pending verification.',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
              ],
            ),
          ),
          if (isRetryingThis)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF2563EB),
                ),
              ),
            )
          else
            TextButton(
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _isRetryingVerification
                  ? null
                  : () async {
                      setState(() {
                        _isRetryingVerification = true;
                        _retryingAttemptId = attempt.id;
                      });

                      final success = await ref
                          .read(tripPayProvider.notifier)
                          .retryVerifyPendingAttempt(
                            attempt: attempt,
                            tripId: tripId,
                          );

                      if (!mounted) return;

                      final err = ref.read(tripPayProvider).error;
                      setState(() {
                        _isRetryingVerification = false;
                        _retryingAttemptId = null;
                      });

                      if (success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Payment verified! ${CurrencyFormatter.formatUnits(attempt.amountPaise)} credited to Trip Pot.',
                            ),
                            backgroundColor: const Color(0xFF10B981),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              err ??
                                  'Verification retry failed. Please try again.',
                            ),
                            backgroundColor: Colors.red.shade700,
                            action: SnackBarAction(
                              label: 'Dismiss',
                              textColor: Colors.white,
                              onPressed: () {},
                            ),
                          ),
                        );
                      }
                    },
              child: const Text(
                'Verify Now',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPotCard(
    ThemeData theme,
    dynamic summary,
    String tripName,
    int myContributionPaise,
  ) {
    final contributed = summary?.totalContributedPaise ?? 0;
    final spent = summary?.totalSpentPaise ?? 0;
    final available = summary?.availableBalancePaise ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spaceLg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F4C81), Color(0xFF10B981)],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SHARED TRIP POT',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 1.0,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  tripName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            CurrencyFormatter.formatUnits(available as int),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Trip Pot Balance • Available',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildPotMetric(
                'Total Added',
                CurrencyFormatter.formatUnits(contributed as int),
                Icons.arrow_downward_rounded,
                const Color(0xFF10B981),
              ),
              const SizedBox(width: 8),
              _buildPotMetric(
                'Total Spent',
                CurrencyFormatter.formatUnits(spent as int),
                Icons.arrow_upward_rounded,
                const Color(0xFFF97316),
              ),
              const SizedBox(width: 8),
              _buildPotMetric(
                'Your Share',
                CurrencyFormatter.formatUnits(myContributionPaise),
                Icons.person_outline_rounded,
                const Color(0xFF60A5FA),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPotMetric(
    String label,
    String value,
    IconData icon,
    Color iconColor,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContributionProgressCard(
    ThemeData theme,
    int targetPaise,
    int collectedPaise,
    String percent,
    double progress,
    List<MemberContribution> memberContribs,
  ) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'CONTRIBUTION PROGRESS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '$percent%',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: Color(0xFF10B981),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF10B981),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Trip Target: ${CurrencyFormatter.formatUnits(targetPaise)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  'Collected: ${CurrencyFormatter.formatUnits(collectedPaise)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF10B981),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Text(
              'Crew Contributions',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            if (memberContribs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'No crew members registered yet.',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ...memberContribs.map((mc) {
                final hasContributed = mc.totalContributedPaise > 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Text(
                          mc.displayName.isNotEmpty
                              ? mc.displayName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          mc.displayName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (hasContributed) ...[
                        Text(
                          CurrencyFormatter.formatUnits(
                            mc.totalContributedPaise,
                          ),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF10B981),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF10B981),
                          size: 16,
                        ),
                      ] else ...[
                        Text(
                          'Not added',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionChip(String label, int index, VoidCallback onSelected) {
    final isSelected = _activeSection == index;
    final theme = Theme.of(context);

    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F4C81) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF0F4C81)
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// Transaction History Tile displaying:
  /// - Member Avatar & Initials
  /// - Merchant Name / Description & Category
  /// - Initiator Name & Smart Time
  /// - Transaction Amount (+/-)
  /// - Running Balance Post-Transaction
  Widget _buildTransactionTile(ThemeData theme, TripPayTransaction tx) {
    final isCredit = tx.isCredit;
    final title = tx.merchantName?.isNotEmpty == true
        ? tx.merchantName!
        : (tx.description.isNotEmpty ? tx.description : tx.type.label);

    final subtitleDetail = tx.merchantName?.isNotEmpty == true &&
            tx.description.isNotEmpty
        ? '${tx.description} • ${tx.category}'
        : tx.category;

    final String initiatorStr = tx.initiatedByName.isNotEmpty
        ? tx.initiatedByName
        : 'Crew Member';

    final initial = initiatorStr.isNotEmpty ? initiatorStr[0].toUpperCase() : '?';

    final formattedTime = DateFormat('h:mm a').format(tx.createdAt);
    final headerDate = _formatDateHeader(tx.createdAt);

    return Card(
      margin: const EdgeInsets.only(bottom: AppConstants.spaceSm),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        onTap: () => _showTransactionDetails(context, tx),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceMd),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Member Avatar with Initial
              CircleAvatar(
                radius: 20,
                backgroundColor: isCredit
                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                    : const Color(0xFFEF4444).withValues(alpha: 0.15),
                child: Text(
                  initial,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: isCredit
                        ? const Color(0xFF047857)
                        : const Color(0xFFB91C1C),
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spaceSm),

              // Transaction Info (Title, Subtitle, Initiator, Date)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$subtitleDetail • by $initiatorStr',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$headerDate • $formattedTime',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Transaction Amount & Running Balance
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isCredit ? '+' : '-'}${CurrencyFormatter.formatUnits(tx.amountPaise)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: isCredit
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Bal: ${CurrencyFormatter.formatUnits(tx.balanceAfterPaise)}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTransactionDetails(BuildContext context, TripPayTransaction tx) {
    final activeTrip = ref.read(activeTripProvider);
    final isPayment = tx.type == TripPayTransactionType.payment ||
        tx.type == TripPayTransactionType.expense;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Transaction Details',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'SANDBOX',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: tx.isCredit
                      ? const Color(0xFF10B981).withValues(alpha: 0.12)
                      : const Color(0xFFEF4444).withValues(alpha: 0.12),
                  child: Icon(
                    tx.isCredit
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    color: tx.isCredit
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                  ),
                ),
                title: Text(
                  tx.merchantName?.isNotEmpty == true
                      ? '${tx.merchantName} (${tx.description})'
                      : tx.description,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${tx.type.label} • ${DateFormat('dd MMM yyyy, h:mm a').format(tx.createdAt)}',
                ),
                trailing: Text(
                  '${tx.isCredit ? '+' : '-'}${CurrencyFormatter.formatUnits(tx.amountPaise)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: tx.isCredit
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                  ),
                ),
              ),
              const Divider(),
              _detailRow('Initiated By', tx.initiatedByName),
              if (tx.merchantName != null && tx.merchantName!.isNotEmpty)
                _detailRow('Merchant', tx.merchantName!),
              _detailRow('Category', tx.category),
              _detailRow(
                'Payment Provider',
                tx.type == TripPayTransactionType.contribution
                    ? 'UPI (Sandbox)'
                    : 'Trip Pot (Sandbox)',
              ),
              _detailRow('Verification Status', 'Verified Successful'),
              _detailRow(
                'Pot Balance Before',
                CurrencyFormatter.formatUnits(tx.balanceBeforePaise),
              ),
              _detailRow(
                'Pot Balance After',
                CurrencyFormatter.formatUnits(tx.balanceAfterPaise),
              ),
              if (tx.relatedExpenseId != null)
                _detailRow('Linked Expense ID', tx.relatedExpenseId!),
              if (tx.relatedTransactionId != null)
                _detailRow('Original Transaction ID', tx.relatedTransactionId!),
              const SizedBox(height: 16),
              if (isPayment && activeTrip != null)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          title: const Text('Sandbox Refund'),
                          content: Text(
                            'Initiate sandbox refund of ${CurrencyFormatter.formatUnits(tx.amountPaise)} back to the Trip Pot?\n\nMode: SANDBOX (no real money moves).',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(dCtx, true),
                              child: const Text('Confirm Refund'),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true) {
                        final reqId =
                            'ref_${DateTime.now().millisecondsSinceEpoch}_${tx.id}';
                        final success = await ref
                            .read(tripPayProvider.notifier)
                            .refundPayment(
                              tripId: activeTrip.id,
                              originalTransactionId: tx.id,
                              amountPaise: tx.amountPaise,
                              clientRequestId: reqId,
                            );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                success
                                    ? 'Sandbox refund completed! ${CurrencyFormatter.formatUnits(tx.amountPaise)} restored to Trip Pot.'
                                    : 'Refund failed.',
                              ),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.replay_rounded, size: 18),
                    label: const Text('Sandbox Refund to Pot'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityTile(ThemeData theme, MemberContribution mc) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppConstants.spaceSm),
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: Text(
                mc.displayName.isNotEmpty
                    ? mc.displayName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ),
            const SizedBox(width: AppConstants.spaceSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mc.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Contributed: ${CurrencyFormatter.formatUnits(mc.totalContributedPaise)}',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'Payments initiated: ${mc.paymentsInitiated}',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'Trip Pot spending initiated: ${CurrencyFormatter.formatUnits(mc.totalSpendingInitiatedPaise)}',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettlementPreview(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    dynamic summary,
    SettlementPlan plan,
    Map<String, String> memberNames,
    String tripId,
    bool isProcessing,
  ) {
    final contributed = plan.totalContributedPaise;
    final spent = plan.totalSpentPaise;
    final remaining = plan.remainingPotPaise;
    final isSettled = plan.isSettled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'TRIP-END BALANCE',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (isSettled)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF10B981)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 14, color: Color(0xFF047857)),
                    SizedBox(width: 4),
                    Text(
                      'SETTLED',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF047857),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: AppConstants.spaceSm),
        Card(
          color: theme.colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.spaceLg),
            child: Column(
              children: [
                _buildSettlementRow(
                  theme,
                  'Total contributed',
                  CurrencyFormatter.formatUnits(contributed),
                ),
                const Divider(height: 16),
                _buildSettlementRow(
                  theme,
                  'Total spent',
                  CurrencyFormatter.formatUnits(spent),
                ),
                const Divider(height: 16),
                _buildSettlementRow(
                  theme,
                  'Remaining Pot',
                  CurrencyFormatter.formatUnits(remaining),
                  bold: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppConstants.spaceLg),

        // MEMBER BALANCES
        Text(
          'MEMBER BALANCES',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppConstants.spaceSm),
        if (plan.memberBalances.isEmpty)
          const AppEmptyState(
            icon: Icons.group_outlined,
            title: 'No member data',
            message: 'Member balances will be calculated when trip members exist.',
          )
        else
          ...plan.memberBalances.map((mb) {
            final isCreditor = mb.netBalancePaise > 0;
            final isDebtor = mb.netBalancePaise < 0;
            final badgeColor = isCreditor
                ? const Color(0xFF10B981)
                : (isDebtor ? const Color(0xFFEF4444) : theme.colorScheme.outline);
            final badgeBg = isCreditor
                ? const Color(0xFFD1FAE5)
                : (isDebtor ? const Color(0xFFFEE2E2) : const Color(0xFFF3F4F6));
            final badgeText = isCreditor
                ? '+${CurrencyFormatter.formatUnits(mb.netBalancePaise)} (Gets refund)'
                : (isDebtor
                    ? '${CurrencyFormatter.formatUnits(mb.netBalancePaise)} (Owes payment)'
                    : 'Balanced');

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.spaceMd),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        mb.displayName.isNotEmpty
                            ? mb.displayName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mb.displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Contributed: ${CurrencyFormatter.formatUnits(mb.totalContributedPaise)} • Fair share: ${CurrencyFormatter.formatUnits(mb.fairSharePaise)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: badgeColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

        const SizedBox(height: AppConstants.spaceLg),

        // WHO PAYS WHOM / SETTLEMENT TRANSFERS
        Text(
          'WHO PAYS WHOM',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppConstants.spaceSm),
        if (plan.transfers.isEmpty)
          Card(
            color: theme.colorScheme.surfaceContainerLow,
            child: const Padding(
              padding: EdgeInsets.all(AppConstants.spaceLg),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: Color(0xFF10B981)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'All accounts are completely balanced. No settlement transfers needed.',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...plan.transfers.map((transfer) {
            final isPotRefund = transfer.type == 'pot_refund';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isPotRefund
                      ? const Color(0xFFD1FAE5)
                      : theme.colorScheme.secondaryContainer,
                  child: Icon(
                    isPotRefund
                        ? Icons.savings_outlined
                        : Icons.swap_horiz_rounded,
                    color: isPotRefund
                        ? const Color(0xFF047857)
                        : theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                title: Row(
                  children: [
                    Text(
                      transfer.fromName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      transfer.toName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  isPotRefund ? 'Pot Refund' : 'Peer-to-Peer Settlement',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: Text(
                  CurrencyFormatter.formatUnits(transfer.amountPaise),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: isPotRefund
                        ? const Color(0xFF10B981)
                        : theme.colorScheme.primary,
                  ),
                ),
              ),
            );
          }),

        const SizedBox(height: AppConstants.spaceLg),

        // SETTLEMENT ACTION BUTTON
        if (!isSettled)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isProcessing
                  ? null
                  : () => _confirmAndExecuteSettlement(context, ref, tripId, plan),
              icon: isProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.gavel_rounded),
              label: Text(
                isProcessing ? 'Settling Trip...' : 'Execute Atomic Settlement',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: const Color(0xFF059669),
              ),
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppConstants.spaceMd),
            decoration: BoxDecoration(
              color: const Color(0xFFD1FAE5),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(color: const Color(0xFF10B981)),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_outline, color: Color(0xFF047857), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Trip Settlement Completed. Ledger is locked and final balance has been set to 0.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF047857),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _confirmAndExecuteSettlement(
    BuildContext context,
    WidgetRef ref,
    String tripId,
    SettlementPlan plan,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.gavel_rounded, color: Color(0xFF059669)),
            SizedBox(width: 8),
            Text('Execute Settlement?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This action will atomically finalize the Trip Pot ledger on Firestore:\n',
              style: TextStyle(fontSize: 13),
            ),
            Text(
              '• Create ${plan.transfers.length} settlement transaction(s)',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const Text(
              '• Set remaining Trip Pot balance to ₹0.00',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const Text(
              '• Lock trip settlement status',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              'Are you sure you want to proceed?',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await ref
                  .read(tripPayProvider.notifier)
                  .executeSettlement(tripId: tripId);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Trip settlement executed successfully!'
                          : 'Settlement failed. Please check network connection.',
                    ),
                    backgroundColor:
                        success ? const Color(0xFF059669) : Colors.red,
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
            ),
            child: const Text('Confirm Settlement'),
          ),
        ],
      ),
    );
  }

  Widget _buildSettlementRow(
    ThemeData theme,
    String label,
    String value, {
    bool bold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: bold ? 16 : 14,
            color: bold ? theme.colorScheme.primary : null,
          ),
        ),
      ],
    );
  }
}
