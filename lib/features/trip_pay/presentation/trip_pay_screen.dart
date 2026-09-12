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

/// Main TripCrew Pay hub screen.
/// Displays the shared Trip Pot balance, contribution progress & crew status,
/// transaction history with smart timestamps, crew spending activity,
/// and trip-end settlement preview.
class TripPayScreen extends ConsumerStatefulWidget {
  const TripPayScreen({super.key});

  @override
  ConsumerState<TripPayScreen> createState() => _TripPayScreenState();
}

class _TripPayScreenState extends ConsumerState<TripPayScreen> {
  int _activeSection = 0; // 0: History, 1: Crew Activity, 2: Settlement

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

  String _formatTransactionTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final txDate = DateTime(dt.year, dt.month, dt.day);
    final timeStr = DateFormat('h:mm a').format(dt);

    if (txDate == today) {
      return 'Today • $timeStr';
    } else if (txDate == yesterday) {
      return 'Yesterday • $timeStr';
    } else {
      return '${DateFormat("dd MMM").format(dt)} • $timeStr';
    }
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
    final filteredTx = tripPayState.filteredTransactions(currentUser?.uid);
    final memberContribs = tripPayState.memberContributions;
    final settlements = tripPayState.calculateSettlementPreview();

    // Calculate user's personal contribution
    int myContributionPaise = 0;
    if (currentUser != null) {
      for (final mc in memberContribs) {
        if (mc.uid == currentUser.uid) {
          myContributionPaise = mc.totalContributedPaise;
          break;
        }
      }
    }

    // Target calculation: trip budget in paise
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

                        // Sandbox Mode Header Banner
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

                        // Section Tabs: Transaction History, Crew Activity, Settlement
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

                        // Section 0: Transaction History
                        if (_activeSection == 0) ...[
                          // Filter Chips
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

                          if (filteredTx.isEmpty)
                            const AppEmptyState(
                              icon: Icons.receipt_long_rounded,
                              title: 'No transactions yet',
                              message:
                                  'Trip activity will appear here once contributions or payments are made.',
                            )
                          else
                            ...filteredTx.map(
                              (tx) => _buildTransactionTile(theme, tx),
                            ),
                        ],

                        // Section 1: Crew Spending Activity
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

                        // Section 2: Trip-End Settlement Preview
                        if (_activeSection == 2) ...[
                          _buildSettlementPreview(
                            theme,
                            summary,
                            settlements,
                            tripPayState.memberNames,
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

  Widget _buildSandboxBanner() {
    final tripPayState = ref.watch(tripPayProvider);
    final isSetu = tripPayState.providerType == PaymentProviderType.setu;

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
              isSetu
                  ? 'TripCrew Pay • UPI TEST MODE • Setu UAT Sandbox • No real money is transferred.'
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
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () {
              ref.read(tripPayProvider.notifier).recoverPendingPayments(tripId);
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

  /// Prioritized Pot Card per Item 3:
  /// SHARED TRIP POT
  /// Available: ₹X
  /// Total Added: ₹X
  /// Total Spent: ₹X
  /// Your Contribution: ₹X
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

  /// Contribution Progress per Item 4:
  /// Trip Target: ₹20,000
  /// Collected: ₹15,000
  /// 75%
  /// Crew: A ₹5,000 ✅, B ₹5,000 ✅, C ₹5,000 ✅, D Not added
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
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: const Color(0xFF10B981),
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

  /// Transaction History Tile per Item 7:
  /// WHO initiated it, WHAT it was for, HOW MUCH, WHEN
  /// Example:
  /// Dinner
  /// -₹1,200
  /// Initiated by Arun
  /// Today • 8:42 PM
  Widget _buildTransactionTile(ThemeData theme, TripPayTransaction tx) {
    final isCredit = tx.isCredit;

    String initiatorPrefix;
    if (tx.type == TripPayTransactionType.payment) {
      initiatorPrefix = 'Initiated by ${tx.initiatedByName}';
    } else if (tx.type == TripPayTransactionType.contribution) {
      initiatorPrefix = 'Added by ${tx.initiatedByName}';
    } else if (tx.type == TripPayTransactionType.refund) {
      initiatorPrefix = 'Refunded by ${tx.initiatedByName}';
    } else {
      initiatorPrefix = 'Initiated by ${tx.initiatedByName}';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: AppConstants.spaceSm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showTransactionDetails(context, tx),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceMd),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: isCredit
                    ? const Color(0xFF10B981).withValues(alpha: 0.12)
                    : const Color(0xFFEF4444).withValues(alpha: 0.12),
                child: Icon(
                  isCredit
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  color: isCredit
                      ? const Color(0xFF10B981)
                      : const Color(0xFFEF4444),
                  size: 20,
                ),
              ),
              const SizedBox(width: AppConstants.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx.description.isNotEmpty
                          ? tx.description
                          : tx.type.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            initiatorPrefix,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (tx.type == TripPayTransactionType.contribution) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF10B981,
                              ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'UPI • Successful',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF047857),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatTransactionTime(tx.createdAt),
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
            ],
          ),
        ),
      ),
    );
  }

  void _showTransactionDetails(BuildContext context, TripPayTransaction tx) {
    final activeTrip = ref.read(activeTripProvider);
    final isPayment = tx.type == TripPayTransactionType.payment;

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
                  tx.description,
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

  /// Member Activity Tile per Item 8:
  /// Contributed, Payments initiated, Amount of Trip Pot spending initiated
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
    ThemeData theme,
    dynamic summary,
    Map<String, int> settlements,
    Map<String, String> memberNames,
  ) {
    final contributed = summary?.totalContributedPaise ?? 0;
    final spent = summary?.totalSpentPaise ?? 0;
    final remaining = summary?.availableBalancePaise ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TRIP-END BALANCE',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: theme.colorScheme.onSurfaceVariant,
          ),
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
                  CurrencyFormatter.formatUnits(contributed as int),
                ),
                const Divider(height: 16),
                _buildSettlementRow(
                  theme,
                  'Spent',
                  CurrencyFormatter.formatUnits(spent as int),
                ),
                const Divider(height: 16),
                _buildSettlementRow(
                  theme,
                  'Remaining',
                  CurrencyFormatter.formatUnits(remaining as int),
                  bold: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppConstants.spaceMd),
        if (remaining > 0 && settlements.isNotEmpty) ...[
          Text(
            'SANDBOX SETTLEMENT PREVIEW',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppConstants.spaceSm),
          Container(
            padding: const EdgeInsets.all(AppConstants.spaceMd),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(color: const Color(0xFFF59E0B)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Color(0xFFB45309), size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Proportional refund based on actual contributions. Real settlement requires a payment partner.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF92400E)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spaceSm),
          ...settlements.entries.map((entry) {
            final name = memberNames[entry.key] ?? 'Member';
            return Card(
              margin: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                title: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                trailing: Text(
                  CurrencyFormatter.formatUnits(entry.value),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF10B981),
                    fontSize: 14,
                  ),
                ),
              ),
            );
          }),
        ] else if (remaining == 0)
          const AppEmptyState(
            icon: Icons.check_circle_outline,
            title: 'All funds used',
            message: 'The Trip Pot has been fully spent. No settlement needed.',
          ),
      ],
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
