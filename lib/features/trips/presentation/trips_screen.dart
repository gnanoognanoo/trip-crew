import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/widgets/app_empty_state.dart';
import 'package:tripcrew/features/trips/models/trip_model.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Trips list screen with tabs for Active, Upcoming, Completed and navigation into workspaces.
class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tripsState = ref.watch(tripsProvider);

    final activeTrips = tripsState.trips
        .where((t) => t.isActive)
        .toList();
    final upcomingTrips = tripsState.trips
        .where((t) => !t.isActive && t.status == 'upcoming')
        .toList();
    final completedTrips = tripsState.trips
        .where((t) => !t.isActive && t.status == 'completed')
        .toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Trips'),
          bottom: TabBar(
            indicatorColor: theme.colorScheme.primary,
            indicatorWeight: 3,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
            tabs: const [
              Tab(text: 'Active'),
              Tab(text: 'Upcoming'),
              Tab(text: 'Completed'),
            ],
          ),
        ),
        body: Column(
          children: [
            // Action Buttons Bar
            Padding(
              padding: const EdgeInsets.all(AppConstants.spaceMd),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => context.push('/create-trip'),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Create Trip'),
                    ),
                  ),
                  const SizedBox(width: AppConstants.spaceSm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/join-trip'),
                      icon: const Icon(Icons.group_add_outlined, size: 18),
                      label: const Text('Join Trip'),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Tab Views
            Expanded(
              child: TabBarView(
                children: [
                  _buildTripList(
                    context,
                    ref,
                    trips: activeTrips,
                    emptyTitle: 'No active trips',
                    emptySubtitle:
                        'Start a journey to collaborate with your crew in real-time.',
                  ),
                  _buildTripList(
                    context,
                    ref,
                    trips: upcomingTrips,
                    emptyTitle: 'No upcoming trips',
                    emptySubtitle: 'Plan your next adventure with friends.',
                  ),
                  _buildTripList(
                    context,
                    ref,
                    trips: completedTrips,
                    emptyTitle: 'No completed trips',
                    emptySubtitle:
                        'Past trips and recap stories will be archived here.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripList(
    BuildContext context,
    WidgetRef ref, {
    required List<TripModel> trips,
    required String emptyTitle,
    required String emptySubtitle,
  }) {
    if (trips.isEmpty) {
      return AppEmptyState(
        icon: Icons.flight_takeoff_rounded,
        title: emptyTitle,
        message: emptySubtitle,
        actionLabel: 'Create Trip',
        onActionPressed: () => context.push('/create-trip'),
      );
    }

    final dateFormat = DateFormat('dd MMM yyyy');

    return ListView.builder(
      padding: const EdgeInsets.all(AppConstants.spaceLg),
      itemCount: trips.length,
      itemBuilder: (context, index) {
        final trip = trips[index];
        return Card(
          margin: const EdgeInsets.only(bottom: AppConstants.spaceMd),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.travel_explore_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: Text(
              trip.name,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text('${trip.startingPlace} → ${trip.destination}'),
                Text(
                  '${dateFormat.format(trip.startDate)} • ${trip.memberCount} Members',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: () {
              ref.read(tripsProvider.notifier).setActiveTrip(trip.id);
              context.push('/workspace');
            },
          ),
        );
      },
    );
  }
}
