import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/widgets/app_empty_state.dart';
import 'package:tripcrew/features/auth/providers/auth_provider.dart';
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
                          title: 'Map',
                          icon: Icons.map_rounded,
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
