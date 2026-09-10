import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tripcrew/core/constants/app_constants.dart';
import 'package:tripcrew/core/services/analytics_service.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Screen 18: After-Trip Recap & Analytics screen matching UI design mockup.
class TripRecapScreen extends ConsumerWidget {
  const TripRecapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activeTrip = ref.watch(activeTripProvider);

    AnalyticsService.logRecapViewed(activeTrip?.id ?? 'trip_goa_01');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Analytics'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppConstants.spaceSm),
              Text(
                'Your ${activeTrip?.name ?? 'Goa Trip'}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Trip complete • 4 days of shared memories with your crew',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: AppConstants.spaceLg),

              // 2x2 Key Metrics Grid
              Row(
                children: [
                  _buildMetricCard(
                    context,
                    label: 'Total Spending',
                    value: '₹18,420',
                    icon: Icons.account_balance_wallet_outlined,
                    color: const Color(0xFFF59E0B),
                  ),
                  const SizedBox(width: AppConstants.spaceMd),
                  _buildMetricCard(
                    context,
                    label: 'Distance',
                    value: '486 km',
                    icon: Icons.directions_car_rounded,
                    color: const Color(0xFF10B981),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spaceMd),
              Row(
                children: [
                  _buildMetricCard(
                    context,
                    label: 'Places Visited',
                    value: '14',
                    icon: Icons.place_outlined,
                    color: const Color(0xFF3B82F6),
                  ),
                  const SizedBox(width: AppConstants.spaceMd),
                  _buildMetricCard(
                    context,
                    label: 'Photos',
                    value: '183',
                    icon: Icons.photo_library_outlined,
                    color: const Color(0xFF8B5CF6),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spaceXl),

              // Highlights List
              Text(
                'Crew Highlights',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppConstants.spaceSm),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFFEF3C7),
                        child: Icon(
                          Icons.restaurant_rounded,
                          color: Color(0xFFD97706),
                          size: 20,
                        ),
                      ),
                      title: const Text(
                        'Food Stops',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      trailing: const Text(
                        '7 Stops',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFDBEAFE),
                        child: Icon(
                          Icons.star_rounded,
                          color: Color(0xFF2563EB),
                          size: 20,
                        ),
                      ),
                      title: const Text(
                        'Most Active Explorer',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      trailing: const Text(
                        'Rahul',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFD1FAE5),
                        child: Icon(
                          Icons.beach_access_rounded,
                          color: Color(0xFF059669),
                          size: 20,
                        ),
                      ),
                      title: const Text(
                        'Top Category',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      trailing: const Text(
                        'Beaches',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // View Trip Replay Button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Trip Replay ✨'),
                        content: const Text(
                          'Your personalized multimedia Trip Story is generated and ready to share to Instagram / WhatsApp stories!',
                        ),
                        actions: [
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Share Story'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('View Trip Replay'),
                ),
              ),
              const SizedBox(height: AppConstants.spaceLg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);

    return Expanded(
      child: Card(
        color: theme.colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 8),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
