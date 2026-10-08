import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/utils/currency_formatter.dart';
import 'package:tripcrew/core/widgets/app_empty_state.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
import 'package:tripcrew/features/trip_pay/providers/trip_pay_notifier.dart';
import 'package:tripcrew/features/trips/models/trip_model.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Screen 3: Home Dashboard matching the startup UI mockup.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedFilter = 0; // 0: Active, 1: Upcoming, 2: Past

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authUser = ref.watch(authProvider).user;
    final tripsState = ref.watch(tripsProvider);
    final activeTrip = tripsState.activeTrip;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Top App Bar Greeting
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spaceLg,
                  AppConstants.spaceMd,
                  AppConstants.spaceLg,
                  AppConstants.spaceSm,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Good morning,',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              authUser?.name ?? 'Traveler',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text('👋', style: TextStyle(fontSize: 18)),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.notifications_none_rounded),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('No new notifications'),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => context.go('/profile'),
                          borderRadius: BorderRadius.circular(20),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: Text(
                              (authUser?.name.isNotEmpty == true
                                      ? authUser!.name[0]
                                      : 'U')
                                  .toUpperCase(),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Filter Tabs (Active, Upcoming, Past)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceLg,
                  vertical: AppConstants.spaceSm,
                ),
                child: Row(
                  children: [
                    _buildFilterChip('Active', 0),
                    const SizedBox(width: AppConstants.spaceSm),
                    _buildFilterChip('Upcoming', 1),
                    const SizedBox(width: AppConstants.spaceSm),
                    _buildFilterChip('Past', 2),
                  ],
                ),
              ),
            ),

            // Active Trip Banner Card
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceLg,
                  vertical: AppConstants.spaceSm,
                ),
                child: activeTrip != null
                    ? _buildActiveTripCard(context, activeTrip)
                    : Card(
                        child: AppEmptyState(
                          icon: Icons.explore_off_outlined,
                          title: 'No active trip',
                          message:
                              'Create or join a trip to launch your crew workspace.',
                          actionLabel: 'Create Trip',
                          onActionPressed: () => context.push('/create-trip'),
                        ),
                      ),
              ),
            ),

            // TripCrew Pay Quick Action when active trip exists
            if (activeTrip != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spaceLg,
                    vertical: AppConstants.spaceXs,
                  ),
                  child: _buildTripPayQuickActionCard(
                    context,
                    tripsState.trips
                        .where((t) => t.isActive)
                        .toList(),
                    activeTrip,
                  ),
                ),
              ),

            // Quick Hub Grid (Itinerary, Expenses, Map, Packing, Memories, Crew)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceLg,
                  vertical: AppConstants.spaceMd,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildHubItem(
                          context,
                          title: 'Itinerary',
                          icon: Icons.calendar_today_rounded,
                          color: const Color(0xFFEF4444),
                          onTap: () => context.push('/itinerary'),
                        ),
                        const SizedBox(width: AppConstants.spaceMd),
                        _buildHubItem(
                          context,
                          title: 'Expenses',
                          icon: Icons.account_balance_wallet_rounded,
                          color: const Color(0xFFF59E0B),
                          onTap: () => context.push('/expenses'),
                        ),
                        const SizedBox(width: AppConstants.spaceMd),
                        _buildHubItem(
                          context,
                          title: 'Live Crew',
                          icon: Icons.radar_rounded,
                          color: const Color(0xFF10B981),
                          onTap: () => context.push('/live-location'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppConstants.spaceMd),
                    Row(
                      children: [
                        _buildHubItem(
                          context,
                          title: 'Packing',
                          icon: Icons.backpack_rounded,
                          color: const Color(0xFFF97316),
                          onTap: () => context.push('/checklist'),
                        ),
                        const SizedBox(width: AppConstants.spaceMd),
                        _buildHubItem(
                          context,
                          title: 'Memories',
                          icon: Icons.photo_library_rounded,
                          color: const Color(0xFF8B5CF6),
                          onTap: () => context.push('/memories'),
                        ),
                        const SizedBox(width: AppConstants.spaceMd),
                        _buildHubItem(
                          context,
                          title: 'Crew',
                          icon: Icons.groups_rounded,
                          color: const Color(0xFF06B6D4),
                          onTap: () => context.push('/crew'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Upcoming Trips Section Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spaceLg,
                  AppConstants.spaceSm,
                  AppConstants.spaceLg,
                  AppConstants.spaceSm,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Upcoming Trips',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                      onPressed: () => context.push('/create-trip'),
                    ),
                  ],
                ),
              ),
            ),

            // Upcoming Trips List
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spaceLg,
                  0,
                  AppConstants.spaceLg,
                  AppConstants.space2xl,
                ),
                child: Column(
                  children: tripsState.upcomingTrips.isEmpty
                      ? [
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('No upcoming trips planned yet.'),
                            ),
                          ),
                        ]
                      : tripsState.upcomingTrips.map((trip) {
                          return Card(
                            margin: const EdgeInsets.only(
                              bottom: AppConstants.spaceSm,
                            ),
                            child: ListTile(
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(
                                    AppConstants.radiusMd,
                                  ),
                                ),
                                child: Icon(
                                  Icons.nature_people_rounded,
                                  color: theme.colorScheme.secondary,
                                ),
                              ),
                              title: Text(
                                trip.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '${trip.startingPlace} → ${trip.destination}',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                ref
                                    .read(tripsProvider.notifier)
                                    .setActiveTrip(trip.id);
                                context.push('/workspace');
                              },
                            ),
                          );
                        }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openTripPot(List<TripModel> activeTrips, TripModel defaultTrip) {
    if (activeTrips.length > 1) {
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
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.savings_rounded,
                        color: Color(0xFF10B981),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Select Active Trip',
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Multiple trips are currently active. Choose which Trip Pot you want to open:',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: AppConstants.spaceMd),
                ...activeTrips.map(
                  (t) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: const Color(
                        0xFF0F4C81,
                      ).withValues(alpha: 0.1),
                      child: const Icon(
                        Icons.luggage_rounded,
                        color: Color(0xFF0F4C81),
                        size: 20,
                      ),
                    ),
                    title: Text(
                      t.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text('${t.startingPlace} → ${t.destination}'),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () {
                      Navigator.pop(ctx);
                      ref.read(tripsProvider.notifier).setActiveTrip(t.id);
                      context.push('/trip-pay');
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      final tripId = activeTrips.isNotEmpty
          ? activeTrips.first.id
          : defaultTrip.id;
      ref.read(tripsProvider.notifier).setActiveTrip(tripId);
      context.push('/trip-pay');
    }
  }

  Widget _buildTripPayQuickActionCard(
    BuildContext context,
    List<TripModel> activeTrips,
    TripModel activeTrip,
  ) {
    final theme = Theme.of(context);
    final tripPayState = ref.watch(tripPayProvider);
    final availablePaise = tripPayState.summary?.availableBalancePaise ?? 0;
    final formattedBalance = CurrencyFormatter.formatUnits(availablePaise);

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        side: BorderSide(
          color: const Color(0xFF10B981).withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: InkWell(
        onTap: () => _openTripPot(activeTrips, activeTrip),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceLg,
            vertical: AppConstants.spaceMd,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF0F4C81).withValues(alpha: 0.06),
                const Color(0xFF10B981).withValues(alpha: 0.12),
              ],
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F4C81), Color(0xFF10B981)],
                  ),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: const Icon(
                  Icons.savings_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppConstants.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'TripCrew Pay',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        if (activeTrips.length > 1) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${activeTrips.length} active',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$formattedBalance available',
                      style: const TextStyle(
                        color: Color(0xFF059669),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: () => _openTripPot(activeTrips, activeTrip),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text(
                  'Open Trip Pot',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final isSelected = _selectedFilter == index;
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => setState(() => _selectedFilter = index),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTripCard(BuildContext context, TripModel trip) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
      ),
      child: InkWell(
        onTap: () {
          ref.read(tripsProvider.notifier).setActiveTrip(trip.id);
          context.push('/workspace');
        },
        child: Container(
          height: 180,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F4C81), Color(0xFF1E6091), Color(0xFF2E86AB)],
            ),
          ),
          child: Stack(
            children: [
              // Subtle background travel overlay
              Positioned(
                right: -20,
                bottom: -20,
                child: Icon(
                  Icons.surfing_rounded,
                  size: 140,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppConstants.spaceLg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              trip.name,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${trip.startingPlace} → ${trip.destination}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        // Days to go badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.timer_outlined,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${trip.daysToGo} days to go',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Crew avatars stack
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.35),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.groups_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '${trip.memberCount} ${trip.memberCount == 1 ? "member" : "members"}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () {
                            ref
                                .read(tripsProvider.notifier)
                                .setActiveTrip(trip.id);
                            context.push('/pulse');
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(
                                AppConstants.radiusMd,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('⚡', style: TextStyle(fontSize: 12)),
                                SizedBox(width: 4),
                                Text(
                                  'Pulse',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            ref
                                .read(tripsProvider.notifier)
                                .setActiveTrip(trip.id);
                            context.push('/trip-pay');
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(
                                AppConstants.radiusMd,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.savings_rounded,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Trip Pot',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusMd,
                            ),
                          ),
                          child: const Row(
                            children: [
                              Text(
                                'Open Hub',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHubItem(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
